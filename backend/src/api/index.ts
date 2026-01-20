/**
 * Governance API Module - Street Governance
 *
 * REST API for querying indexed governance data.
 *
 * ## Endpoints
 *
 * ### Proposals
 * - GET /api/proposals - List proposals (paginated, filterable)
 * - GET /api/proposals/:id - Get proposal details with suggestions
 * - GET /api/proposals/:id/votes - Get votes for a proposal
 *
 * ### Votes
 * - GET /api/votes/voter/:address - Get votes by voter
 *
 * ### Suggestions
 * - GET /api/suggestions/:id - Get suggestion details
 * - GET /api/suggestions/:id/votes - Get votes for a suggestion
 *
 * ### Statistics
 * - GET /api/stats - Overall governance statistics
 *
 * ### Treasury (Futarchy)
 * - GET /api/treasury/proposals - List futarchy proposals
 * - GET /api/treasury/proposals/:id - Get futarchy proposal details
 * - GET /api/treasury/proposals/:id/trades - Get trades for proposal
 * - GET /api/treasury/prices/:id - Get current YES/NO prices
 * - GET /api/treasury/stats - Treasury statistics
 *
 * ### Health
 * - GET /health - API health check
 * - GET /health/indexer - Indexer status and lag
 */

import express, {
  type Express,
  type Request,
  type Response,
  type NextFunction,
} from "express";
import { getIndexerStatus } from "../indexer/index.js";
import {
  getProposals,
  getProposalById,
  getVotesByProposal,
  getVotesByVoter,
  getStats,
  getCheckpoint,
  getFutarchyProposals,
  getFutarchyProposalById,
  getFutarchyTradesByProposal,
  getFutarchyPrices,
  getTreasuryStats,
} from "../db/index.js";
import type { ProposalStatus, FutarchyProposalStatus, PaginationParams } from "../types/index.js";

// =============================================================================
// Configuration
// =============================================================================

export interface ApiConfig {
  port: number;
  rateLimitWindowMs?: number;
  rateLimitMaxRequests?: number;
}

// =============================================================================
// Middleware
// =============================================================================

/**
 * Simple in-memory rate limiter (use Redis in production)
 */
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

function createRateLimiter(windowMs: number, maxRequests: number) {
  return (req: Request, res: Response, next: NextFunction) => {
    const ip = req.ip ?? req.socket.remoteAddress ?? "unknown";
    const now = Date.now();
    const entry = rateLimitMap.get(ip);

    if (!entry || now > entry.resetAt) {
      rateLimitMap.set(ip, { count: 1, resetAt: now + windowMs });
      return next();
    }

    if (entry.count >= maxRequests) {
      res.status(429).json({
        error: "Too many requests",
        retryAfter: Math.ceil((entry.resetAt - now) / 1000),
      });
      return;
    }

    entry.count++;
    next();
  };
}

/**
 * Validate Ethereum address format
 */
function isValidAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

/**
 * Parse pagination params with defaults and limits
 */
function parsePagination(query: Request["query"]): PaginationParams {
  const page = Math.max(1, parseInt(query.page as string, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(query.limit as string, 10) || 20));
  return { page, limit };
}

/**
 * Async route wrapper for error handling
 */
function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>
) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

// =============================================================================
// Server
// =============================================================================

let app: Express | null = null;
let server: ReturnType<Express["listen"]> | null = null;

/**
 * Initialize and start the API server
 */
export async function startApi(config: ApiConfig): Promise<void> {
  const {
    port,
    rateLimitWindowMs = 60_000, // 1 minute
    rateLimitMaxRequests = 100, // 100 requests per minute
  } = config;

  app = express();

  // ==========================================================================
  // Global Middleware
  // ==========================================================================

  app.use(express.json({ limit: "1mb" }));

  // CORS headers for frontend integration
  app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.header(
      "Access-Control-Allow-Headers",
      "Origin, X-Requested-With, Content-Type, Accept"
    );
    if (req.method === "OPTIONS") {
      res.sendStatus(204);
      return;
    }
    next();
  });

  // Rate limiting
  app.use(createRateLimiter(rateLimitWindowMs, rateLimitMaxRequests));

  // Request logging (simple)
  app.use((req, res, next) => {
    const start = Date.now();
    res.on("finish", () => {
      const duration = Date.now() - start;
      console.log(`[API] ${req.method} ${req.path} ${res.statusCode} ${duration}ms`);
    });
    next();
  });

  // ==========================================================================
  // Health Endpoints
  // ==========================================================================

  app.get("/health", (req: Request, res: Response) => {
    res.json({
      status: "ok",
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version ?? "0.1.0",
    });
  });

  app.get(
    "/health/indexer",
    asyncHandler(async (req: Request, res: Response) => {
      const indexerStatus = getIndexerStatus();
      const checkpoint = await getCheckpoint();

      if (!indexerStatus?.isRunning) {
        res.status(503).json({
          status: "error",
          message: "Indexer not running",
          indexer: indexerStatus,
          checkpoint: checkpoint
            ? {
                lastBlock: checkpoint.lastIndexedBlock,
                lastHash: checkpoint.lastIndexedHash,
                updatedAt: checkpoint.updatedAt.toISOString(),
              }
            : null,
        });
        return;
      }

      const lastIndexed = BigInt(indexerStatus.lastIndexedBlock);
      const chainHead = BigInt(indexerStatus.chainHead ?? indexerStatus.lastIndexedBlock);
      const lag = Number(chainHead - lastIndexed);

      res.json({
        status: lag < 100 ? "ok" : "lagging",
        indexer: {
          isRunning: indexerStatus.isRunning,
          lastIndexedBlock: indexerStatus.lastIndexedBlock,
          chainHead: indexerStatus.chainHead,
          lag,
          lastUpdateAt: checkpoint?.updatedAt.toISOString() ?? null,
        },
      });
    })
  );

  // ==========================================================================
  // Proposal Endpoints
  // ==========================================================================

  /**
   * GET /api/proposals
   * List proposals with pagination and optional filters
   *
   * Query params:
   * - page: number (default: 1)
   * - limit: number (default: 20, max: 100)
   * - status: ProposalStatus (optional filter)
   * - proposer: address (optional filter)
   */
  app.get(
    "/api/proposals",
    asyncHandler(async (req: Request, res: Response) => {
      const pagination = parsePagination(req.query);
      const filters: { status?: ProposalStatus; proposer?: string } = {};

      if (req.query.status) {
        const validStatuses = [
          "pending",
          "active",
          "defeated",
          "succeeded",
          "executed",
          "canceled",
          "expired",
        ];
        if (validStatuses.includes(req.query.status as string)) {
          filters.status = req.query.status as ProposalStatus;
        }
      }

      if (req.query.proposer) {
        const proposer = req.query.proposer as string;
        if (isValidAddress(proposer)) {
          filters.proposer = proposer;
        } else {
          res.status(400).json({ error: "Invalid proposer address format" });
          return;
        }
      }

      const result = await getProposals(pagination, filters);
      res.json(result);
    })
  );

  /**
   * GET /api/proposals/:id
   * Get single proposal by ID with suggestions
   */
  app.get(
    "/api/proposals/:id",
    asyncHandler(async (req: Request, res: Response) => {
      const id = req.params.id;

      // Validate proposal ID (should be a valid uint256 as string)
      if (!id || !/^\d+$/.test(id) || id.length > 78) {
        res.status(400).json({ error: "Invalid proposal ID format" });
        return;
      }

      const proposal = await getProposalById(id);

      if (!proposal) {
        res.status(404).json({ error: "Proposal not found" });
        return;
      }

      res.json(proposal);
    })
  );

  /**
   * GET /api/proposals/:id/votes
   * Get votes for a specific proposal
   */
  app.get(
    "/api/proposals/:id/votes",
    asyncHandler(async (req: Request, res: Response) => {
      const id = req.params.id;

      if (!id || !/^\d+$/.test(id) || id.length > 78) {
        res.status(400).json({ error: "Invalid proposal ID format" });
        return;
      }

      // Verify proposal exists
      const proposal = await getProposalById(id);
      if (!proposal) {
        res.status(404).json({ error: "Proposal not found" });
        return;
      }

      const pagination = parsePagination(req.query);
      const result = await getVotesByProposal(id, pagination);
      res.json(result);
    })
  );

  // ==========================================================================
  // Vote Endpoints
  // ==========================================================================

  /**
   * GET /api/votes/voter/:address
   * Get all votes by a specific voter address
   */
  app.get(
    "/api/votes/voter/:address",
    asyncHandler(async (req: Request, res: Response) => {
      const address = req.params.address;

      if (!address || !isValidAddress(address)) {
        res.status(400).json({ error: "Invalid address format" });
        return;
      }

      const pagination = parsePagination(req.query);
      const result = await getVotesByVoter(address, pagination);
      res.json(result);
    })
  );

  // ==========================================================================
  // Statistics Endpoints
  // ==========================================================================

  /**
   * GET /api/stats
   * Get overall governance statistics
   */
  app.get(
    "/api/stats",
    asyncHandler(async (req: Request, res: Response) => {
      const stats = await getStats();
      res.json(stats);
    })
  );

  // ==========================================================================
  // Treasury (Futarchy) Endpoints
  // ==========================================================================

  /**
   * GET /api/treasury/proposals
   * List futarchy treasury proposals with pagination and optional filters
   *
   * Query params:
   * - page: number (default: 1)
   * - limit: number (default: 20, max: 100)
   * - status: FutarchyProposalStatus (optional filter)
   * - recipient: address (optional filter)
   */
  app.get(
    "/api/treasury/proposals",
    asyncHandler(async (req: Request, res: Response) => {
      const pagination = parsePagination(req.query);
      const filters: { status?: FutarchyProposalStatus; recipient?: string } = {};

      if (req.query.status) {
        const validStatuses = ["active", "resolved", "executed", "expired"];
        if (validStatuses.includes(req.query.status as string)) {
          filters.status = req.query.status as FutarchyProposalStatus;
        }
      }

      if (req.query.recipient) {
        const recipient = req.query.recipient as string;
        if (isValidAddress(recipient)) {
          filters.recipient = recipient;
        } else {
          res.status(400).json({ error: "Invalid recipient address format" });
          return;
        }
      }

      const result = await getFutarchyProposals(pagination, filters);
      res.json(result);
    })
  );

  /**
   * GET /api/treasury/proposals/:id
   * Get single futarchy proposal by ID
   */
  app.get(
    "/api/treasury/proposals/:id",
    asyncHandler(async (req: Request, res: Response) => {
      const id = req.params.id;

      // Validate proposal ID (should be a valid uint256 as string)
      if (!id || !/^\d+$/.test(id) || id.length > 78) {
        res.status(400).json({ error: "Invalid proposal ID format" });
        return;
      }

      const proposal = await getFutarchyProposalById(id);

      if (!proposal) {
        res.status(404).json({ error: "Treasury proposal not found" });
        return;
      }

      res.json(proposal);
    })
  );

  /**
   * GET /api/treasury/proposals/:id/trades
   * Get trades for a futarchy proposal
   */
  app.get(
    "/api/treasury/proposals/:id/trades",
    asyncHandler(async (req: Request, res: Response) => {
      const id = req.params.id;

      if (!id || !/^\d+$/.test(id) || id.length > 78) {
        res.status(400).json({ error: "Invalid proposal ID format" });
        return;
      }

      // Verify proposal exists
      const proposal = await getFutarchyProposalById(id);
      if (!proposal) {
        res.status(404).json({ error: "Treasury proposal not found" });
        return;
      }

      const pagination = parsePagination(req.query);
      const result = await getFutarchyTradesByProposal(id, pagination);
      res.json(result);
    })
  );

  /**
   * GET /api/treasury/prices/:id
   * Get current YES/NO prices for a futarchy proposal
   */
  app.get(
    "/api/treasury/prices/:id",
    asyncHandler(async (req: Request, res: Response) => {
      const id = req.params.id;

      if (!id || !/^\d+$/.test(id) || id.length > 78) {
        res.status(400).json({ error: "Invalid proposal ID format" });
        return;
      }

      const prices = await getFutarchyPrices(id);

      if (!prices) {
        res.status(404).json({ error: "Treasury proposal not found" });
        return;
      }

      res.json(prices);
    })
  );

  /**
   * GET /api/treasury/stats
   * Get treasury statistics
   */
  app.get(
    "/api/treasury/stats",
    asyncHandler(async (req: Request, res: Response) => {
      const stats = await getTreasuryStats();
      res.json(stats);
    })
  );

  // ==========================================================================
  // Error Handling
  // ==========================================================================

  // 404 handler
  app.use((req: Request, res: Response) => {
    res.status(404).json({ error: "Not found" });
  });

  // Global error handler
  app.use((err: Error, req: Request, res: Response, _next: NextFunction) => {
    console.error(`[API] Error: ${err.message}`, err.stack);

    // Don't leak internal error details in production
    const isDev = process.env.NODE_ENV === "development";
    res.status(500).json({
      error: "Internal server error",
      ...(isDev && { message: err.message, stack: err.stack }),
    });
  });

  // ==========================================================================
  // Start Server
  // ==========================================================================

  return new Promise((resolve) => {
    server = app!.listen(port, () => {
      console.log(`[API] Server started on port ${port}`);
      resolve();
    });
  });
}

/**
 * Stop the API server gracefully
 */
export async function stopApi(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!server) {
      resolve();
      return;
    }

    server.close((err) => {
      if (err) {
        reject(err);
      } else {
        console.log("[API] Server stopped");
        server = null;
        app = null;
        resolve();
      }
    });
  });
}

/**
 * Get the Express app instance (for testing)
 */
export function getApp(): Express | null {
  return app;
}
