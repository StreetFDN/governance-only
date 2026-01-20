/**
 * Street Governance Backend - Entry Point
 *
 * Initializes and coordinates:
 * - Database connection
 * - Event indexer (background)
 * - REST API server
 *
 * Handles graceful shutdown on SIGTERM/SIGINT.
 */

import "dotenv/config";
import { startIndexer, stopIndexer } from "./indexer/index.js";
import { startApi, stopApi } from "./api/index.js";
import { initDb, closeDb } from "./db/index.js";
import type { Address } from "viem";

// =============================================================================
// Configuration
// =============================================================================

const config = {
  // API
  port: parseInt(process.env.PORT ?? "3000", 10),

  // Database
  databaseUrl: process.env.DATABASE_URL ?? "",

  // RPC
  rpcUrl: process.env.BASE_RPC_URL ?? "https://mainnet.base.org",
  isTestnet: process.env.BASE_TESTNET === "true",

  // Contract addresses (required)
  governorAddress: process.env.GOVERNOR_ADDRESS as Address | undefined,
  editSuggestionsAddress: process.env.EDIT_SUGGESTIONS_ADDRESS as Address | undefined,
  futarchyTreasuryAddress: process.env.FUTARCHY_TREASURY_ADDRESS as Address | undefined,

  // Indexer tuning
  startBlock: process.env.INDEXER_START_BLOCK
    ? BigInt(process.env.INDEXER_START_BLOCK)
    : 0n,
  confirmationDepth: parseInt(process.env.INDEXER_CONFIRMATION_DEPTH ?? "64", 10),
  batchSize: parseInt(process.env.INDEXER_BATCH_SIZE ?? "1000", 10),
  pollIntervalMs: parseInt(process.env.INDEXER_POLL_INTERVAL_MS ?? "2000", 10),
};

// =============================================================================
// Validation
// =============================================================================

function validateConfig(): void {
  const errors: string[] = [];

  if (!config.databaseUrl) {
    errors.push("DATABASE_URL is required");
  }

  if (!config.governorAddress) {
    errors.push("GOVERNOR_ADDRESS is required");
  }

  if (!config.editSuggestionsAddress) {
    errors.push("EDIT_SUGGESTIONS_ADDRESS is required");
  }

  if (!config.futarchyTreasuryAddress) {
    errors.push("FUTARCHY_TREASURY_ADDRESS is required");
  }

  if (errors.length > 0) {
    console.error("Configuration errors:");
    errors.forEach((e) => console.error(`  - ${e}`));
    process.exit(1);
  }
}

// =============================================================================
// Main
// =============================================================================

async function main(): Promise<void> {
  console.log("=".repeat(60));
  console.log("Street Governance Backend");
  console.log("=".repeat(60));

  // Validate configuration
  validateConfig();

  console.log("\nConfiguration:");
  console.log(`  Port: ${config.port}`);
  console.log(`  RPC: ${config.rpcUrl}`);
  console.log(`  Testnet: ${config.isTestnet}`);
  console.log(`  Governor: ${config.governorAddress}`);
  console.log(`  EditSuggestions: ${config.editSuggestionsAddress}`);
  console.log(`  FutarchyTreasury: ${config.futarchyTreasuryAddress}`);
  console.log(`  Start Block: ${config.startBlock}`);
  console.log(`  Confirmation Depth: ${config.confirmationDepth}`);
  console.log("");

  // Initialize database connection
  console.log("[Main] Initializing database...");
  await initDb({ connectionString: config.databaseUrl });

  // Start the indexer (runs in background)
  console.log("[Main] Starting indexer...");
  await startIndexer({
    rpcUrl: config.rpcUrl,
    governorAddress: config.governorAddress!,
    editSuggestionsAddress: config.editSuggestionsAddress!,
    futarchyTreasuryAddress: config.futarchyTreasuryAddress!,
    startBlock: config.startBlock,
    confirmationDepth: config.confirmationDepth,
    batchSize: config.batchSize,
    pollIntervalMs: config.pollIntervalMs,
    isTestnet: config.isTestnet,
  });

  // Start the API server
  console.log("[Main] Starting API server...");
  await startApi({ port: config.port });

  console.log("\n" + "=".repeat(60));
  console.log(`Backend running on http://localhost:${config.port}`);
  console.log("=".repeat(60) + "\n");
}

// =============================================================================
// Graceful Shutdown
// =============================================================================

async function shutdown(signal: string): Promise<void> {
  console.log(`\n[Main] Received ${signal}, shutting down gracefully...`);

  try {
    // Stop accepting new requests
    await stopApi();
    console.log("[Main] API stopped");

    // Stop indexer
    await stopIndexer();
    console.log("[Main] Indexer stopped");

    // Close database connections
    await closeDb();
    console.log("[Main] Database connections closed");

    console.log("[Main] Shutdown complete");
    process.exit(0);
  } catch (error) {
    console.error("[Main] Error during shutdown:", error);
    process.exit(1);
  }
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

// Handle uncaught errors
process.on("uncaughtException", (error) => {
  console.error("[Main] Uncaught exception:", error);
  shutdown("uncaughtException").catch(() => process.exit(1));
});

process.on("unhandledRejection", (reason) => {
  console.error("[Main] Unhandled rejection:", reason);
  shutdown("unhandledRejection").catch(() => process.exit(1));
});

// Start the application
main().catch((error) => {
  console.error("[Main] Fatal error during startup:", error);
  process.exit(1);
});
