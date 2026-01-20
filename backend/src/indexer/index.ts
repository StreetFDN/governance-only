/**
 * Governance Indexer Module - Street Governance
 *
 * Indexes governance events from Base L2 with:
 * - Reorg detection and recovery via block hash verification
 * - Confirmation depth for finality (64 blocks for Base L2)
 * - Idempotent event processing via (txHash, logIndex) keys
 * - Checkpoint-based resumable indexing
 * - Batch processing for efficiency
 *
 * ## Base L2 Reorg Handling Strategy
 *
 * Base L2 (OP Stack) has ~2 second block times with 64-block confirmation depth.
 * Reorgs are rare but possible during sequencer issues or L1 reorganizations.
 *
 * Our strategy:
 * 1. Only process blocks that have reached confirmation depth (latest - 64)
 * 2. Store block hash with each event for verification
 * 3. On each indexing cycle, verify the stored hash matches chain state
 * 4. If mismatch detected (reorg), soft-delete affected events and re-index
 * 5. Use database transactions for atomic batch processing
 */

import {
  createPublicClient,
  http,
  type PublicClient,
  type Log,
  parseAbiItem,
  decodeEventLog,
  type Address,
} from "viem";

// Block type with the fields we actually need
interface IndexedBlock {
  number: bigint | null;
  hash: `0x${string}` | null;
  timestamp: bigint;
}
import { base, baseSepolia } from "viem/chains";
import {
  getCheckpoint,
  updateCheckpoint,
  markReorgedFromBlock,
  getStoredBlockHash,
  insertProposal,
  insertVote,
  insertSuggestion,
  insertSuggestionVote,
  insertSlash,
  insertExecution,
  insertCancellation,
  insertFutarchyProposal,
  insertFutarchyTrade,
  insertFutarchyResolution,
  insertFutarchyRedemption,
  withTransaction,
} from "../db/index.js";
import type { VoteSupport } from "../types/index.js";

// =============================================================================
// Configuration
// =============================================================================

export interface IndexerConfig {
  rpcUrl: string;
  governorAddress: Address;
  editSuggestionsAddress: Address;
  futarchyTreasuryAddress: Address;
  startBlock?: bigint;
  confirmationDepth?: number;
  batchSize?: number;
  pollIntervalMs?: number;
  isTestnet?: boolean;
}

export interface IndexerState {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: PublicClient<any, any>;
  config: IndexerConfig;
  lastIndexedBlock: bigint;
  lastIndexedHash: string;
  chainHead: bigint;
  isRunning: boolean;
  isPaused: boolean;
  lastError: Error | null;
  processedEvents: number;
  reorgsHandled: number;
}

// =============================================================================
// Event ABIs (placeholder - will be replaced with actual ABIs from SOL)
// =============================================================================

/**
 * Event ABI definitions for parsing logs
 * TODO: Replace with actual contract ABIs from SOL team
 */
const EVENT_ABIS = {
  // StreetGovernor events
  ProposalCreated: parseAbiItem(
    "event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, string description, address[] targets, uint256[] values, bytes[] calldatas, uint256 startBlock, uint256 endBlock, uint256 stakeAmount)"
  ),
  VoteCast: parseAbiItem(
    "event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight, string reason)"
  ),
  ProposalExecuted: parseAbiItem(
    "event ProposalExecuted(uint256 indexed proposalId)"
  ),
  ProposalCanceled: parseAbiItem(
    "event ProposalCanceled(uint256 indexed proposalId)"
  ),
  Slashed: parseAbiItem(
    "event Slashed(uint256 indexed proposalId, address indexed proposer, uint256 slashedAmount, uint256 returnedAmount)"
  ),

  // EditSuggestions events
  EditSuggested: parseAbiItem(
    "event EditSuggested(uint256 indexed suggestionId, uint256 indexed proposalId, address indexed suggester, bytes32 originalHash, string proposedText, uint256 stakeAmount, uint256 editWindowEnd, uint256 voteWindowEnd)"
  ),
  SuggestionVoted: parseAbiItem(
    "event SuggestionVoted(uint256 indexed suggestionId, address indexed voter, bool support, uint256 weight)"
  ),

  // FutarchyTreasury events
  FutarchyProposalCreated: parseAbiItem(
    "event FutarchyProposalCreated(uint256 indexed proposalId, string description, uint256 amount, address indexed recipient, uint256 marketEndTime)"
  ),
  TradePlaced: parseAbiItem(
    "event TradePlaced(uint256 indexed proposalId, address indexed trader, bool isYes, uint256 amountIn, uint256 amountOut, uint256 newPrice)"
  ),
  ProposalResolved: parseAbiItem(
    "event ProposalResolved(uint256 indexed proposalId, bool passed, uint256 yesPrice, uint256 noPrice)"
  ),
  CollateralRedeemed: parseAbiItem(
    "event CollateralRedeemed(uint256 indexed proposalId, address indexed user, uint256 amount)"
  ),
} as const;

// =============================================================================
// Indexer State
// =============================================================================

let indexerState: IndexerState | null = null;

// =============================================================================
// Public API
// =============================================================================

/**
 * Initialize and start the indexer
 */
export async function startIndexer(config: IndexerConfig): Promise<void> {
  const {
    rpcUrl,
    governorAddress,
    editSuggestionsAddress,
    futarchyTreasuryAddress,
    startBlock = 0n,
    confirmationDepth = 64, // Base L2: ~2 min at 2s blocks
    batchSize = 1000,
    pollIntervalMs = 2000,
    isTestnet = false,
  } = config;

  console.log("[Indexer] Starting indexer...");
  console.log(`[Indexer] RPC: ${rpcUrl}`);
  console.log(`[Indexer] Governor: ${governorAddress}`);
  console.log(`[Indexer] EditSuggestions: ${editSuggestionsAddress}`);
  console.log(`[Indexer] FutarchyTreasury: ${futarchyTreasuryAddress}`);
  console.log(`[Indexer] Confirmation depth: ${confirmationDepth} blocks`);

  // Create viem client for Base L2
  const chain = isTestnet ? baseSepolia : base;
  const client = createPublicClient({
    chain,
    transport: http(rpcUrl),
  });

  // Load checkpoint or start from configured block
  const checkpoint = await getCheckpoint();
  const lastIndexedBlock = checkpoint
    ? BigInt(checkpoint.lastIndexedBlock)
    : startBlock > 0n
      ? startBlock - 1n
      : 0n;
  const lastIndexedHash = checkpoint?.lastIndexedHash ?? "";

  // Get current chain head
  const chainHead = await client.getBlockNumber();

  indexerState = {
    client,
    config: {
      rpcUrl,
      governorAddress,
      editSuggestionsAddress,
      futarchyTreasuryAddress,
      startBlock,
      confirmationDepth,
      batchSize,
      pollIntervalMs,
      isTestnet,
    },
    lastIndexedBlock,
    lastIndexedHash,
    chainHead,
    isRunning: true,
    isPaused: false,
    lastError: null,
    processedEvents: 0,
    reorgsHandled: 0,
  };

  console.log(`[Indexer] Starting from block ${lastIndexedBlock}`);
  console.log(`[Indexer] Chain head: ${chainHead}`);

  // Start the main indexing loop
  runIndexingLoop().catch((err) => {
    console.error("[Indexer] Fatal error in indexing loop:", err);
    if (indexerState) {
      indexerState.lastError = err;
      indexerState.isRunning = false;
    }
  });
}

/**
 * Stop the indexer gracefully
 */
export async function stopIndexer(): Promise<void> {
  if (indexerState) {
    console.log("[Indexer] Stopping indexer...");
    indexerState.isRunning = false;

    // Wait for current batch to complete (max 10 seconds)
    let waited = 0;
    while (indexerState.isPaused === false && waited < 10000) {
      await sleep(100);
      waited += 100;
    }

    console.log("[Indexer] Indexer stopped");
  }
}

/**
 * Get current indexer status
 */
export function getIndexerStatus(): {
  isRunning: boolean;
  lastIndexedBlock: string;
  chainHead: string;
  processedEvents: number;
  reorgsHandled: number;
  lastError: string | null;
} | null {
  if (!indexerState) return null;

  return {
    isRunning: indexerState.isRunning,
    lastIndexedBlock: indexerState.lastIndexedBlock.toString(),
    chainHead: indexerState.chainHead.toString(),
    processedEvents: indexerState.processedEvents,
    reorgsHandled: indexerState.reorgsHandled,
    lastError: indexerState.lastError?.message ?? null,
  };
}

/**
 * Pause indexer (for maintenance)
 */
export function pauseIndexer(): void {
  if (indexerState) {
    indexerState.isPaused = true;
    console.log("[Indexer] Paused");
  }
}

/**
 * Resume indexer
 */
export function resumeIndexer(): void {
  if (indexerState) {
    indexerState.isPaused = false;
    console.log("[Indexer] Resumed");
  }
}

// =============================================================================
// Main Indexing Loop
// =============================================================================

/**
 * Main indexing loop that runs continuously
 */
async function runIndexingLoop(): Promise<void> {
  if (!indexerState) return;

  const { client, config } = indexerState;
  const { confirmationDepth, batchSize, pollIntervalMs } = config;

  while (indexerState.isRunning) {
    // Wait if paused
    if (indexerState.isPaused) {
      await sleep(1000);
      continue;
    }

    try {
      // 1. Get current chain head
      const chainHead = await client.getBlockNumber();
      indexerState.chainHead = chainHead;

      // 2. Calculate safe block (with confirmation depth)
      const safeBlock = chainHead - BigInt(confirmationDepth ?? 64);

      // Nothing to index if we're caught up
      if (safeBlock <= indexerState.lastIndexedBlock) {
        await sleep(pollIntervalMs ?? 2000);
        continue;
      }

      // 3. Check for reorgs before processing new blocks
      const reorgDetected = await detectReorg();
      if (reorgDetected) {
        await handleReorg(reorgDetected);
        continue; // Re-check after handling reorg
      }

      // 4. Calculate batch range
      const fromBlock = indexerState.lastIndexedBlock + 1n;
      const toBlock =
        fromBlock + BigInt(batchSize ?? 1000) - 1n < safeBlock
          ? fromBlock + BigInt(batchSize ?? 1000) - 1n
          : safeBlock;

      console.log(`[Indexer] Processing blocks ${fromBlock} to ${toBlock}`);

      // 5. Fetch and process events in batch
      await processBlockRange(fromBlock, toBlock);

      // 6. Update checkpoint
      const finalBlock = await client.getBlock({ blockNumber: toBlock });
      indexerState.lastIndexedBlock = toBlock;
      indexerState.lastIndexedHash = finalBlock.hash;
      await updateCheckpoint(toBlock, finalBlock.hash, chainHead);

      console.log(`[Indexer] Checkpoint updated: block ${toBlock}`);
    } catch (error) {
      console.error("[Indexer] Error in indexing loop:", error);
      indexerState.lastError = error as Error;

      // Exponential backoff on errors (max 30 seconds)
      await sleep(Math.min(30000, (pollIntervalMs ?? 2000) * 2));
    }
  }
}

// =============================================================================
// Reorg Detection and Handling
// =============================================================================

/**
 * Detect if a reorg has occurred by comparing stored block hashes
 *
 * @returns Block number where reorg was detected, or null if no reorg
 */
async function detectReorg(): Promise<bigint | null> {
  if (!indexerState) return null;

  const { client } = indexerState;

  // Check the last few indexed blocks for hash mismatches
  // Start from most recent and work backwards
  const checkDepth = 10; // Check last 10 blocks
  const startCheck =
    indexerState.lastIndexedBlock - BigInt(checkDepth) > 0n
      ? indexerState.lastIndexedBlock - BigInt(checkDepth)
      : 1n;

  for (
    let blockNum = indexerState.lastIndexedBlock;
    blockNum >= startCheck;
    blockNum--
  ) {
    const storedHash = await getStoredBlockHash(blockNum);
    if (!storedHash) continue; // No events at this block

    try {
      const chainBlock = await client.getBlock({ blockNumber: blockNum });

      if (chainBlock.hash !== storedHash) {
        console.log(
          `[Indexer] Reorg detected at block ${blockNum}! ` +
            `Stored: ${storedHash}, Chain: ${chainBlock.hash}`
        );
        return blockNum;
      }
    } catch (error) {
      console.warn(
        `[Indexer] Failed to verify block ${blockNum}:`,
        error
      );
    }
  }

  return null;
}

/**
 * Handle a detected reorg by soft-deleting affected events and rolling back
 *
 * @param reorgBlock - Block number where reorg was detected
 */
async function handleReorg(reorgBlock: bigint): Promise<void> {
  if (!indexerState) return;

  console.log(`[Indexer] Handling reorg from block ${reorgBlock}`);

  // 1. Soft-delete all events from reorged blocks
  const stats = await markReorgedFromBlock(reorgBlock);
  console.log(`[Indexer] Marked as reorged:`, stats);

  // 2. Roll back checkpoint to before the reorg
  const rollbackBlock = reorgBlock - 1n;
  const { client } = indexerState;
  const safeBlock = await client.getBlock({ blockNumber: rollbackBlock });

  indexerState.lastIndexedBlock = rollbackBlock;
  indexerState.lastIndexedHash = safeBlock.hash;
  indexerState.reorgsHandled++;

  await updateCheckpoint(rollbackBlock, safeBlock.hash);

  console.log(`[Indexer] Rolled back to block ${rollbackBlock}`);
}

// =============================================================================
// Event Processing
// =============================================================================

/**
 * Process all governance events in a block range
 */
async function processBlockRange(
  fromBlock: bigint,
  toBlock: bigint
): Promise<void> {
  if (!indexerState) return;

  const { client, config } = indexerState;
  const { governorAddress, editSuggestionsAddress, futarchyTreasuryAddress } = config;

  // Fetch all events from all contracts in parallel
  const [governorLogs, suggestionLogs, futarchyLogs] = await Promise.all([
    client.getLogs({
      address: governorAddress,
      fromBlock,
      toBlock,
    }),
    client.getLogs({
      address: editSuggestionsAddress,
      fromBlock,
      toBlock,
    }),
    client.getLogs({
      address: futarchyTreasuryAddress,
      fromBlock,
      toBlock,
    }),
  ]);

  // Combine and sort by block/logIndex for deterministic processing
  const allLogs = [...governorLogs, ...suggestionLogs, ...futarchyLogs].sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) {
      return Number(a.blockNumber! - b.blockNumber!);
    }
    return Number(a.logIndex! - b.logIndex!);
  });

  if (allLogs.length === 0) {
    return;
  }

  console.log(`[Indexer] Processing ${allLogs.length} events`);

  // Get block timestamps for all unique blocks
  const blockNumbers = [...new Set(allLogs.map((l) => l.blockNumber!))];
  const blocks = await Promise.all(
    blockNumbers.map((bn) => client.getBlock({ blockNumber: bn }))
  );
  const blockMap = new Map<bigint, IndexedBlock>();
  for (const block of blocks) {
    blockMap.set(block.number!, block as unknown as IndexedBlock);
  }

  // Process events within a transaction for atomicity
  await withTransaction(async () => {
    for (const log of allLogs) {
      const block = blockMap.get(log.blockNumber!)!;
      await processEvent(log, block);
    }
  });

  indexerState.processedEvents += allLogs.length;
}

/**
 * Process a single event log
 */
async function processEvent(log: Log, block: IndexedBlock): Promise<void> {
  if (!indexerState) return;

  const { config } = indexerState;
  const eventMeta = {
    txHash: log.transactionHash!,
    logIndex: Number(log.logIndex!),
    blockNumber: log.blockNumber!,
    blockHash: log.blockHash!,
    blockTimestamp: Number(block.timestamp),
  };

  // Determine which contract emitted the event
  const logAddress = log.address.toLowerCase();
  const isGovernorEvent = logAddress === config.governorAddress.toLowerCase();
  const isSuggestionEvent = logAddress === config.editSuggestionsAddress.toLowerCase();
  const isFutarchyEvent = logAddress === config.futarchyTreasuryAddress.toLowerCase();

  try {
    if (isGovernorEvent) {
      await processGovernorEvent(log, eventMeta);
    } else if (isSuggestionEvent) {
      await processSuggestionEvent(log, eventMeta);
    } else if (isFutarchyEvent) {
      await processFutarchyEvent(log, eventMeta);
    }
  } catch (error) {
    // Log but don't fail on unknown events
    console.warn(
      `[Indexer] Unknown event at ${log.transactionHash}:${log.logIndex}`,
      error
    );
  }
}

/**
 * Process StreetGovernor contract events
 */
async function processGovernorEvent(
  log: Log,
  meta: {
    txHash: `0x${string}`;
    logIndex: number;
    blockNumber: bigint;
    blockHash: `0x${string}`;
    blockTimestamp: number;
  }
): Promise<void> {
  // Try to decode as each known event type
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.ProposalCreated],
      data: log.data,
      topics: log.topics,
    });

    await insertProposal({
      id: decoded.args.proposalId.toString(),
      proposer: decoded.args.proposer,
      title: decoded.args.title,
      description: decoded.args.description,
      targets: decoded.args.targets as string[],
      values: decoded.args.values.map((v) => v.toString()),
      calldatas: decoded.args.calldatas as string[],
      startBlock: decoded.args.startBlock,
      endBlock: decoded.args.endBlock,
      stakeAmount: decoded.args.stakeAmount.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a ProposalCreated event
  }

  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.VoteCast],
      data: log.data,
      topics: log.topics,
    });

    await insertVote({
      proposalId: decoded.args.proposalId.toString(),
      voter: decoded.args.voter,
      support: decoded.args.support as VoteSupport,
      weight: decoded.args.weight.toString(),
      reason: decoded.args.reason,
      ...meta,
    });
    return;
  } catch {
    // Not a VoteCast event
  }

  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.ProposalExecuted],
      data: log.data,
      topics: log.topics,
    });

    await insertExecution({
      proposalId: decoded.args.proposalId.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a ProposalExecuted event
  }

  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.ProposalCanceled],
      data: log.data,
      topics: log.topics,
    });

    await insertCancellation({
      proposalId: decoded.args.proposalId.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a ProposalCanceled event
  }

  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.Slashed],
      data: log.data,
      topics: log.topics,
    });

    await insertSlash({
      proposalId: decoded.args.proposalId.toString(),
      proposer: decoded.args.proposer,
      slashedAmount: decoded.args.slashedAmount.toString(),
      returnedAmount: decoded.args.returnedAmount.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a Slashed event
  }
}

/**
 * Process EditSuggestions contract events
 */
async function processSuggestionEvent(
  log: Log,
  meta: {
    txHash: `0x${string}`;
    logIndex: number;
    blockNumber: bigint;
    blockHash: `0x${string}`;
    blockTimestamp: number;
  }
): Promise<void> {
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.EditSuggested],
      data: log.data,
      topics: log.topics,
    });

    await insertSuggestion({
      id: decoded.args.suggestionId.toString(),
      proposalId: decoded.args.proposalId.toString(),
      suggester: decoded.args.suggester,
      originalHash: decoded.args.originalHash,
      proposedText: decoded.args.proposedText,
      stakeAmount: decoded.args.stakeAmount.toString(),
      editWindowEnd: Number(decoded.args.editWindowEnd),
      voteWindowEnd: Number(decoded.args.voteWindowEnd),
      ...meta,
    });
    return;
  } catch {
    // Not an EditSuggested event
  }

  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.SuggestionVoted],
      data: log.data,
      topics: log.topics,
    });

    await insertSuggestionVote({
      suggestionId: decoded.args.suggestionId.toString(),
      voter: decoded.args.voter,
      support: decoded.args.support,
      weight: decoded.args.weight.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a SuggestionVoted event
  }
}

/**
 * Process FutarchyTreasury contract events
 */
async function processFutarchyEvent(
  log: Log,
  meta: {
    txHash: `0x${string}`;
    logIndex: number;
    blockNumber: bigint;
    blockHash: `0x${string}`;
    blockTimestamp: number;
  }
): Promise<void> {
  // FutarchyProposalCreated
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.FutarchyProposalCreated],
      data: log.data,
      topics: log.topics,
    });

    await insertFutarchyProposal({
      id: decoded.args.proposalId.toString(),
      description: decoded.args.description,
      amount: decoded.args.amount.toString(),
      recipient: decoded.args.recipient,
      marketEndTime: Number(decoded.args.marketEndTime),
      ...meta,
    });
    return;
  } catch {
    // Not a FutarchyProposalCreated event
  }

  // TradePlaced
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.TradePlaced],
      data: log.data,
      topics: log.topics,
    });

    await insertFutarchyTrade({
      proposalId: decoded.args.proposalId.toString(),
      trader: decoded.args.trader,
      isYes: decoded.args.isYes,
      amountIn: decoded.args.amountIn.toString(),
      amountOut: decoded.args.amountOut.toString(),
      newPrice: decoded.args.newPrice.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a TradePlaced event
  }

  // ProposalResolved
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.ProposalResolved],
      data: log.data,
      topics: log.topics,
    });

    await insertFutarchyResolution({
      proposalId: decoded.args.proposalId.toString(),
      passed: decoded.args.passed,
      yesPrice: decoded.args.yesPrice.toString(),
      noPrice: decoded.args.noPrice.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a ProposalResolved event
  }

  // CollateralRedeemed
  try {
    const decoded = decodeEventLog({
      abi: [EVENT_ABIS.CollateralRedeemed],
      data: log.data,
      topics: log.topics,
    });

    await insertFutarchyRedemption({
      proposalId: decoded.args.proposalId.toString(),
      user: decoded.args.user,
      amount: decoded.args.amount.toString(),
      ...meta,
    });
    return;
  } catch {
    // Not a CollateralRedeemed event
  }
}

// =============================================================================
// Utilities
// =============================================================================

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
