/**
 * Database Module - Street Governance
 *
 * PostgreSQL database layer with:
 * - Connection pooling
 * - Idempotent inserts (ON CONFLICT DO NOTHING)
 * - Reorg-aware queries (WHERE NOT is_reorged)
 * - Transaction support for atomic batches
 */

import type {
  Proposal,
  Vote,
  EditSuggestion,
  SuggestionVote,
  SlashRecord,
  IndexerCheckpoint,
  ProposalStatus,
  SuggestionStatus,
  VoteSupport,
  PaginationParams,
  PaginatedResponse,
  ProposalListItem,
  ProposalDetail,
  VoteListItem,
  EditSuggestionListItem,
  GovernanceStats,
  FutarchyProposalStatus,
  FutarchyProposalListItem,
  FutarchyProposalDetail,
  FutarchyTradeListItem,
  FutarchyPriceData,
  TreasuryStats,
} from "../types/index.js";

// =============================================================================
// Configuration
// =============================================================================

export interface DatabaseConfig {
  connectionString: string;
  maxConnections?: number;
  idleTimeout?: number;
}

// =============================================================================
// Database Client Interface (abstraction for testing)
// =============================================================================

export interface DbClient {
  query<T = unknown>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>;
  end(): Promise<void>;
}

// Placeholder - will be replaced with actual pg Pool
let pool: DbClient | null = null;

// =============================================================================
// Initialization
// =============================================================================

/**
 * Initialize database connection pool
 */
export async function initDb(config: DatabaseConfig): Promise<void> {
  // TODO: Replace with actual pg Pool when pg is added to dependencies
  // import { Pool } from 'pg';
  // pool = new Pool({
  //   connectionString: config.connectionString,
  //   max: config.maxConnections ?? 10,
  //   idleTimeoutMillis: config.idleTimeout ?? 30000,
  // });

  console.log("[DB] Initializing database connection pool");
  console.log(
    `[DB] Connection string: ${config.connectionString.replace(/:[^:@]+@/, ":****@")}`
  );

  // Placeholder implementation
  pool = {
    query: async <T>(sql: string, params?: unknown[]): Promise<{ rows: T[] }> => {
      console.log(`[DB] Query: ${sql.slice(0, 100)}...`);
      return { rows: [] };
    },
    end: async () => {
      console.log("[DB] Connection pool closed");
    },
  };
}

/**
 * Close database connections
 */
export async function closeDb(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

/**
 * Get the database pool (for direct queries)
 */
export function getDb(): DbClient {
  if (!pool) {
    throw new Error("Database not initialized. Call initDb() first.");
  }
  return pool;
}

// =============================================================================
// Checkpoint Management
// =============================================================================

/**
 * Get the last indexed block checkpoint
 */
export async function getCheckpoint(): Promise<IndexerCheckpoint | null> {
  const db = getDb();
  const result = await db.query<{
    id: number;
    last_indexed_block: string;
    last_indexed_hash: string;
    updated_at: Date;
  }>(
    `SELECT id, last_indexed_block::TEXT, last_indexed_hash, updated_at
     FROM indexer_checkpoint
     LIMIT 1`
  );

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0]!;
  return {
    id: row.id,
    lastIndexedBlock: row.last_indexed_block,
    lastIndexedHash: row.last_indexed_hash,
    updatedAt: row.updated_at,
  };
}

/**
 * Update or create checkpoint
 */
export async function updateCheckpoint(
  block: bigint,
  hash: string,
  chainHead?: bigint
): Promise<void> {
  const db = getDb();
  await db.query(
    `INSERT INTO indexer_checkpoint (id, last_indexed_block, last_indexed_hash, chain_head_block, updated_at)
     VALUES (1, $1, $2, $3, NOW())
     ON CONFLICT ((true))
     DO UPDATE SET
       last_indexed_block = EXCLUDED.last_indexed_block,
       last_indexed_hash = EXCLUDED.last_indexed_hash,
       chain_head_block = EXCLUDED.chain_head_block,
       updated_at = NOW()`,
    [block.toString(), hash, chainHead?.toString() ?? null]
  );
}

// =============================================================================
// Proposal Operations
// =============================================================================

export interface InsertProposalParams {
  id: string;
  proposer: string;
  title: string;
  description: string;
  targets: string[];
  values: string[];
  calldatas: string[];
  startBlock: bigint;
  endBlock: bigint;
  stakeAmount: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert proposal with idempotency (ON CONFLICT DO NOTHING)
 */
export async function insertProposal(params: InsertProposalParams): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO proposals (
      id, proposer, title, description, targets, values, calldatas,
      start_block, end_block, stake_amount, status,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.id,
      params.proposer,
      params.title,
      params.description,
      JSON.stringify(params.targets),
      JSON.stringify(params.values),
      JSON.stringify(params.calldatas),
      params.startBlock.toString(),
      params.endBlock.toString(),
      params.stakeAmount,
      "pending" as ProposalStatus,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );
  return result.rows.length > 0;
}

/**
 * Update proposal status
 */
export async function updateProposalStatus(
  proposalId: string,
  status: ProposalStatus,
  timestamp?: Date
): Promise<void> {
  const db = getDb();
  const updates: string[] = ["status = $2"];
  const params: unknown[] = [proposalId, status];

  if (status === "executed" && timestamp) {
    updates.push(`executed_at = $${params.length + 1}`);
    params.push(timestamp);
  } else if (status === "canceled" && timestamp) {
    updates.push(`canceled_at = $${params.length + 1}`);
    params.push(timestamp);
  }

  await db.query(
    `UPDATE proposals SET ${updates.join(", ")} WHERE id = $1 AND NOT is_reorged`,
    params
  );
}

/**
 * Get proposals with pagination
 */
export async function getProposals(
  pagination: PaginationParams,
  filters?: { status?: ProposalStatus; proposer?: string }
): Promise<PaginatedResponse<ProposalListItem>> {
  const db = getDb();
  const conditions: string[] = ["NOT is_reorged"];
  const params: unknown[] = [];

  if (filters?.status) {
    params.push(filters.status);
    conditions.push(`status = $${params.length}`);
  }
  if (filters?.proposer) {
    params.push(filters.proposer.toLowerCase());
    conditions.push(`LOWER(proposer) = $${params.length}`);
  }

  const whereClause = conditions.join(" AND ");

  // Get total count
  const countResult = await db.query<{ count: string }>(
    `SELECT COUNT(*) as count FROM proposals WHERE ${whereClause}`,
    params
  );
  const total = parseInt(countResult.rows[0]?.count ?? "0", 10);

  // Get paginated results
  const offset = (pagination.page - 1) * pagination.limit;
  const dataResult = await db.query<{
    id: string;
    proposer: string;
    title: string;
    status: ProposalStatus;
    start_block: string;
    end_block: string;
    for_votes: string;
    against_votes: string;
    abstain_votes: string;
    created_at: Date;
  }>(
    `SELECT id, proposer, title, status, start_block::TEXT, end_block::TEXT,
            for_votes, against_votes, abstain_votes, created_at
     FROM proposals
     WHERE ${whereClause}
     ORDER BY block_number DESC
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, pagination.limit, offset]
  );

  return {
    data: dataResult.rows.map((row) => ({
      id: row.id,
      proposer: row.proposer,
      title: row.title,
      status: row.status,
      startBlock: row.start_block,
      endBlock: row.end_block,
      forVotes: row.for_votes,
      againstVotes: row.against_votes,
      abstainVotes: row.abstain_votes,
      createdAt: row.created_at.toISOString(),
    })),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total,
      totalPages: Math.ceil(total / pagination.limit),
    },
  };
}

/**
 * Get single proposal by ID with suggestions
 */
export async function getProposalById(id: string): Promise<ProposalDetail | null> {
  const db = getDb();
  const result = await db.query<{
    id: string;
    proposer: string;
    title: string;
    description: string;
    targets: string;
    values: string;
    calldatas: string;
    status: ProposalStatus;
    start_block: string;
    end_block: string;
    stake_amount: string;
    for_votes: string;
    against_votes: string;
    abstain_votes: string;
    executed_at: Date | null;
    canceled_at: Date | null;
    slashed_amount: string | null;
    created_at: Date;
  }>(
    `SELECT id, proposer, title, description, targets, values, calldatas,
            status, start_block::TEXT, end_block::TEXT, stake_amount,
            for_votes, against_votes, abstain_votes,
            executed_at, canceled_at, slashed_amount, created_at
     FROM proposals
     WHERE id = $1 AND NOT is_reorged`,
    [id]
  );

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0]!;

  // Get suggestions for this proposal
  const suggestionsResult = await db.query<{
    id: string;
    proposal_id: string;
    suggester: string;
    proposed_text: string;
    status: SuggestionStatus;
    for_votes: string;
    against_votes: string;
    vote_window_end: string;
    created_at: Date;
  }>(
    `SELECT id, proposal_id, suggester, proposed_text, status,
            for_votes, against_votes, vote_window_end::TEXT, created_at
     FROM edit_suggestions
     WHERE proposal_id = $1 AND NOT is_reorged
     ORDER BY created_at DESC`,
    [id]
  );

  return {
    id: row.id,
    proposer: row.proposer,
    title: row.title,
    description: row.description,
    targets: JSON.parse(row.targets),
    values: JSON.parse(row.values),
    calldatas: JSON.parse(row.calldatas),
    status: row.status,
    startBlock: row.start_block,
    endBlock: row.end_block,
    stakeAmount: row.stake_amount,
    forVotes: row.for_votes,
    againstVotes: row.against_votes,
    abstainVotes: row.abstain_votes,
    executedAt: row.executed_at?.toISOString() ?? null,
    canceledAt: row.canceled_at?.toISOString() ?? null,
    slashedAmount: row.slashed_amount,
    createdAt: row.created_at.toISOString(),
    suggestions: suggestionsResult.rows.map((s) => ({
      id: s.id,
      proposalId: s.proposal_id,
      suggester: s.suggester,
      proposedText: s.proposed_text,
      status: s.status,
      forVotes: s.for_votes,
      againstVotes: s.against_votes,
      voteWindowEnd: parseInt(s.vote_window_end, 10),
      createdAt: s.created_at.toISOString(),
    })),
  };
}

// =============================================================================
// Vote Operations
// =============================================================================

export interface InsertVoteParams {
  proposalId: string;
  voter: string;
  support: VoteSupport;
  weight: string;
  reason: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert vote with idempotency and update proposal totals
 */
export async function insertVote(params: InsertVoteParams): Promise<boolean> {
  const db = getDb();

  // Insert vote
  const result = await db.query(
    `INSERT INTO votes (
      proposal_id, voter, support, weight, reason,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.voter,
      params.support,
      params.weight,
      params.reason,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    // Update proposal vote totals
    const column =
      params.support === 1
        ? "for_votes"
        : params.support === 0
          ? "against_votes"
          : "abstain_votes";

    await db.query(
      `UPDATE proposals
       SET ${column} = (${column}::NUMERIC + $2::NUMERIC)::TEXT
       WHERE id = $1 AND NOT is_reorged`,
      [params.proposalId, params.weight]
    );
    return true;
  }
  return false;
}

/**
 * Get votes for a proposal
 */
export async function getVotesByProposal(
  proposalId: string,
  pagination: PaginationParams
): Promise<PaginatedResponse<VoteListItem>> {
  const db = getDb();

  const countResult = await db.query<{ count: string }>(
    `SELECT COUNT(*) as count FROM votes WHERE proposal_id = $1 AND NOT is_reorged`,
    [proposalId]
  );
  const total = parseInt(countResult.rows[0]?.count ?? "0", 10);

  const offset = (pagination.page - 1) * pagination.limit;
  const dataResult = await db.query<{
    proposal_id: string;
    voter: string;
    support: number;
    weight: string;
    reason: string;
    tx_hash: string;
    block_number: string;
    created_at: Date;
  }>(
    `SELECT proposal_id, voter, support, weight, reason, tx_hash,
            block_number::TEXT, created_at
     FROM votes
     WHERE proposal_id = $1 AND NOT is_reorged
     ORDER BY block_number DESC, log_index DESC
     LIMIT $2 OFFSET $3`,
    [proposalId, pagination.limit, offset]
  );

  return {
    data: dataResult.rows.map((row) => ({
      proposalId: row.proposal_id,
      voter: row.voter,
      support: row.support as VoteSupport,
      weight: row.weight,
      reason: row.reason,
      txHash: row.tx_hash,
      blockNumber: row.block_number,
      createdAt: row.created_at.toISOString(),
    })),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total,
      totalPages: Math.ceil(total / pagination.limit),
    },
  };
}

/**
 * Get votes by voter address
 */
export async function getVotesByVoter(
  voter: string,
  pagination: PaginationParams
): Promise<PaginatedResponse<VoteListItem>> {
  const db = getDb();

  const countResult = await db.query<{ count: string }>(
    `SELECT COUNT(*) as count FROM votes WHERE LOWER(voter) = LOWER($1) AND NOT is_reorged`,
    [voter]
  );
  const total = parseInt(countResult.rows[0]?.count ?? "0", 10);

  const offset = (pagination.page - 1) * pagination.limit;
  const dataResult = await db.query<{
    proposal_id: string;
    voter: string;
    support: number;
    weight: string;
    reason: string;
    tx_hash: string;
    block_number: string;
    created_at: Date;
  }>(
    `SELECT proposal_id, voter, support, weight, reason, tx_hash,
            block_number::TEXT, created_at
     FROM votes
     WHERE LOWER(voter) = LOWER($1) AND NOT is_reorged
     ORDER BY block_number DESC, log_index DESC
     LIMIT $2 OFFSET $3`,
    [voter, pagination.limit, offset]
  );

  return {
    data: dataResult.rows.map((row) => ({
      proposalId: row.proposal_id,
      voter: row.voter,
      support: row.support as VoteSupport,
      weight: row.weight,
      reason: row.reason,
      txHash: row.tx_hash,
      blockNumber: row.block_number,
      createdAt: row.created_at.toISOString(),
    })),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total,
      totalPages: Math.ceil(total / pagination.limit),
    },
  };
}

// =============================================================================
// Edit Suggestion Operations
// =============================================================================

export interface InsertSuggestionParams {
  id: string;
  proposalId: string;
  suggester: string;
  originalHash: string;
  proposedText: string;
  stakeAmount: string;
  editWindowEnd: number;
  voteWindowEnd: number;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert edit suggestion with idempotency
 */
export async function insertSuggestion(params: InsertSuggestionParams): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO edit_suggestions (
      id, proposal_id, suggester, original_hash, proposed_text,
      stake_amount, edit_window_end, vote_window_end, status,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.id,
      params.proposalId,
      params.suggester,
      params.originalHash,
      params.proposedText,
      params.stakeAmount,
      params.editWindowEnd,
      params.voteWindowEnd,
      "pending" as SuggestionStatus,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );
  return result.rows.length > 0;
}

export interface InsertSuggestionVoteParams {
  suggestionId: string;
  voter: string;
  support: boolean;
  weight: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert suggestion vote with idempotency
 */
export async function insertSuggestionVote(
  params: InsertSuggestionVoteParams
): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO suggestion_votes (
      suggestion_id, voter, support, weight,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.suggestionId,
      params.voter,
      params.support,
      params.weight,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    const column = params.support ? "for_votes" : "against_votes";
    await db.query(
      `UPDATE edit_suggestions
       SET ${column} = (${column}::NUMERIC + $2::NUMERIC)::TEXT
       WHERE id = $1 AND NOT is_reorged`,
      [params.suggestionId, params.weight]
    );
    return true;
  }
  return false;
}

// =============================================================================
// Slash Operations
// =============================================================================

export interface InsertSlashParams {
  proposalId: string;
  proposer: string;
  slashedAmount: string;
  returnedAmount: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert slash record with idempotency
 */
export async function insertSlash(params: InsertSlashParams): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO slashes (
      proposal_id, proposer, slashed_amount, returned_amount,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.proposer,
      params.slashedAmount,
      params.returnedAmount,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    // Update proposal with slash amount
    await db.query(
      `UPDATE proposals SET slashed_amount = $2 WHERE id = $1 AND NOT is_reorged`,
      [params.proposalId, params.slashedAmount]
    );
    return true;
  }
  return false;
}

// =============================================================================
// Execution/Cancellation Event Operations
// =============================================================================

export interface InsertEventParams {
  proposalId: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert proposal execution event
 */
export async function insertExecution(params: InsertEventParams): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO proposal_executions (
      proposal_id, tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    await updateProposalStatus(
      params.proposalId,
      "executed" as ProposalStatus,
      new Date(params.blockTimestamp * 1000)
    );
    return true;
  }
  return false;
}

/**
 * Insert proposal cancellation event
 */
export async function insertCancellation(params: InsertEventParams): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO proposal_cancellations (
      proposal_id, tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    await updateProposalStatus(
      params.proposalId,
      "canceled" as ProposalStatus,
      new Date(params.blockTimestamp * 1000)
    );
    return true;
  }
  return false;
}

// =============================================================================
// Reorg Handling
// =============================================================================

export interface ReorgStats {
  proposalsAffected: number;
  votesAffected: number;
  suggestionsAffected: number;
  suggestionVotesAffected: number;
  slashesAffected: number;
}

/**
 * Mark all events from a block as reorged (soft delete)
 */
export async function markReorgedFromBlock(fromBlock: bigint): Promise<ReorgStats> {
  const db = getDb();
  const result = await db.query<{
    proposals_affected: string;
    votes_affected: string;
    suggestions_affected: string;
    suggestion_votes_affected: string;
    slashes_affected: string;
  }>(`SELECT * FROM mark_reorged_from_block($1)`, [fromBlock.toString()]);

  const row = result.rows[0];
  return {
    proposalsAffected: parseInt(row?.proposals_affected ?? "0", 10),
    votesAffected: parseInt(row?.votes_affected ?? "0", 10),
    suggestionsAffected: parseInt(row?.suggestions_affected ?? "0", 10),
    suggestionVotesAffected: parseInt(row?.suggestion_votes_affected ?? "0", 10),
    slashesAffected: parseInt(row?.slashes_affected ?? "0", 10),
  };
}

/**
 * Get block hash at a specific block number
 */
export async function getStoredBlockHash(blockNumber: bigint): Promise<string | null> {
  const db = getDb();
  const result = await db.query<{ block_hash: string }>(
    `SELECT DISTINCT block_hash FROM proposals
     WHERE block_number = $1 AND NOT is_reorged
     LIMIT 1`,
    [blockNumber.toString()]
  );
  return result.rows[0]?.block_hash ?? null;
}

// =============================================================================
// Statistics
// =============================================================================

/**
 * Get governance statistics
 */
export async function getStats(): Promise<GovernanceStats> {
  const db = getDb();

  const result = await db.query<{
    total_proposals: string;
    active_proposals: string;
    total_votes: string;
    unique_voters: string;
    total_staked: string;
    total_slashed: string;
  }>(`
    SELECT
      (SELECT COUNT(*) FROM proposals WHERE NOT is_reorged) as total_proposals,
      (SELECT COUNT(*) FROM proposals WHERE NOT is_reorged AND status = 'active') as active_proposals,
      (SELECT COUNT(*) FROM votes WHERE NOT is_reorged) as total_votes,
      (SELECT COUNT(DISTINCT voter) FROM votes WHERE NOT is_reorged) as unique_voters,
      (SELECT COALESCE(SUM(stake_amount::NUMERIC), 0)::TEXT FROM proposals WHERE NOT is_reorged) as total_staked,
      (SELECT COALESCE(SUM(slashed_amount::NUMERIC), 0)::TEXT FROM slashes WHERE NOT is_reorged) as total_slashed
  `);

  const row = result.rows[0]!;
  const totalProposals = parseInt(row.total_proposals, 10);
  const totalVotes = parseInt(row.total_votes, 10);

  return {
    totalProposals,
    activeProposals: parseInt(row.active_proposals, 10),
    totalVotes,
    uniqueVoters: parseInt(row.unique_voters, 10),
    totalStaked: row.total_staked,
    totalSlashed: row.total_slashed,
    participationRate: totalProposals > 0 ? totalVotes / totalProposals : 0,
  };
}

// =============================================================================
// Transaction Helper
// =============================================================================

/**
 * Execute a function within a database transaction
 */
export async function withTransaction<T>(fn: () => Promise<T>): Promise<T> {
  const db = getDb();
  await db.query("BEGIN");
  try {
    const result = await fn();
    await db.query("COMMIT");
    return result;
  } catch (error) {
    await db.query("ROLLBACK");
    throw error;
  }
}

// =============================================================================
// Futarchy Treasury Operations
// =============================================================================

export interface InsertFutarchyProposalParams {
  id: string;
  description: string;
  amount: string;
  recipient: string;
  marketEndTime: number;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert futarchy proposal with idempotency
 */
export async function insertFutarchyProposal(
  params: InsertFutarchyProposalParams
): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO futarchy_proposals (
      id, description, amount, recipient, market_end_time, status,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.id,
      params.description,
      params.amount,
      params.recipient,
      params.marketEndTime,
      "active" as FutarchyProposalStatus,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );
  return result.rows.length > 0;
}

export interface InsertFutarchyTradeParams {
  proposalId: string;
  trader: string;
  isYes: boolean;
  amountIn: string;
  amountOut: string;
  newPrice: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert futarchy trade with idempotency and update proposal prices/volumes
 */
export async function insertFutarchyTrade(
  params: InsertFutarchyTradeParams
): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO futarchy_trades (
      proposal_id, trader, is_yes, amount_in, amount_out, new_price,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.trader,
      params.isYes,
      params.amountIn,
      params.amountOut,
      params.newPrice,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    // Update proposal price and volume
    const priceColumn = params.isYes ? "yes_price" : "no_price";
    const volumeColumn = params.isYes ? "total_yes_volume" : "total_no_volume";

    await db.query(
      `UPDATE futarchy_proposals
       SET ${priceColumn} = $2,
           ${volumeColumn} = (${volumeColumn}::NUMERIC + $3::NUMERIC)::TEXT,
           total_trades = total_trades + 1
       WHERE id = $1 AND NOT is_reorged`,
      [params.proposalId, params.newPrice, params.amountIn]
    );
    return true;
  }
  return false;
}

export interface InsertFutarchyResolutionParams {
  proposalId: string;
  passed: boolean;
  yesPrice: string;
  noPrice: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert futarchy resolution with idempotency and update proposal status
 */
export async function insertFutarchyResolution(
  params: InsertFutarchyResolutionParams
): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO futarchy_resolutions (
      proposal_id, passed, yes_price, no_price,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.passed,
      params.yesPrice,
      params.noPrice,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );

  if (result.rows.length > 0) {
    // Update proposal with resolution details
    await db.query(
      `UPDATE futarchy_proposals
       SET status = 'resolved',
           passed = $2,
           final_yes_price = $3,
           final_no_price = $4,
           resolved_at = NOW()
       WHERE id = $1 AND NOT is_reorged`,
      [params.proposalId, params.passed, params.yesPrice, params.noPrice]
    );
    return true;
  }
  return false;
}

export interface InsertFutarchyRedemptionParams {
  proposalId: string;
  user: string;
  amount: string;
  txHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  blockTimestamp: number;
}

/**
 * Insert futarchy redemption with idempotency
 */
export async function insertFutarchyRedemption(
  params: InsertFutarchyRedemptionParams
): Promise<boolean> {
  const db = getDb();
  const result = await db.query(
    `INSERT INTO futarchy_redemptions (
      proposal_id, user_address, amount,
      tx_hash, log_index, block_number, block_hash, block_timestamp
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    ON CONFLICT (tx_hash, log_index) DO NOTHING
    RETURNING id`,
    [
      params.proposalId,
      params.user,
      params.amount,
      params.txHash,
      params.logIndex,
      params.blockNumber.toString(),
      params.blockHash,
      params.blockTimestamp,
    ]
  );
  return result.rows.length > 0;
}

// =============================================================================
// Futarchy Treasury Queries
// =============================================================================

/**
 * Get futarchy proposals with pagination
 */
export async function getFutarchyProposals(
  pagination: PaginationParams,
  filters?: { status?: FutarchyProposalStatus; recipient?: string }
): Promise<PaginatedResponse<FutarchyProposalListItem>> {
  const db = getDb();
  const conditions: string[] = ["NOT is_reorged"];
  const params: unknown[] = [];

  if (filters?.status) {
    params.push(filters.status);
    conditions.push(`status = $${params.length}`);
  }
  if (filters?.recipient) {
    params.push(filters.recipient.toLowerCase());
    conditions.push(`LOWER(recipient) = $${params.length}`);
  }

  const whereClause = conditions.join(" AND ");

  // Get total count
  const countResult = await db.query<{ count: string }>(
    `SELECT COUNT(*) as count FROM futarchy_proposals WHERE ${whereClause}`,
    params
  );
  const total = parseInt(countResult.rows[0]?.count ?? "0", 10);

  // Get paginated results
  const offset = (pagination.page - 1) * pagination.limit;
  const dataResult = await db.query<{
    id: string;
    description: string;
    amount: string;
    recipient: string;
    market_end_time: string;
    status: FutarchyProposalStatus;
    yes_price: string;
    no_price: string;
    total_trades: number;
    created_at: Date;
  }>(
    `SELECT id, description, amount, recipient, market_end_time::TEXT,
            status, yes_price, no_price, total_trades, created_at
     FROM futarchy_proposals
     WHERE ${whereClause}
     ORDER BY block_number DESC
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, pagination.limit, offset]
  );

  return {
    data: dataResult.rows.map((row) => ({
      id: row.id,
      description: row.description,
      amount: row.amount,
      recipient: row.recipient,
      marketEndTime: parseInt(row.market_end_time, 10),
      status: row.status,
      yesPrice: row.yes_price,
      noPrice: row.no_price,
      totalTrades: row.total_trades,
      createdAt: row.created_at.toISOString(),
    })),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total,
      totalPages: Math.ceil(total / pagination.limit),
    },
  };
}

/**
 * Get single futarchy proposal by ID
 */
export async function getFutarchyProposalById(
  id: string
): Promise<FutarchyProposalDetail | null> {
  const db = getDb();
  const result = await db.query<{
    id: string;
    description: string;
    amount: string;
    recipient: string;
    market_end_time: string;
    status: FutarchyProposalStatus;
    yes_price: string;
    no_price: string;
    total_yes_volume: string;
    total_no_volume: string;
    total_trades: number;
    final_yes_price: string | null;
    final_no_price: string | null;
    passed: boolean | null;
    resolved_at: Date | null;
    created_at: Date;
  }>(
    `SELECT id, description, amount, recipient, market_end_time::TEXT,
            status, yes_price, no_price, total_yes_volume, total_no_volume,
            total_trades, final_yes_price, final_no_price, passed,
            resolved_at, created_at
     FROM futarchy_proposals
     WHERE id = $1 AND NOT is_reorged`,
    [id]
  );

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0]!;
  return {
    id: row.id,
    description: row.description,
    amount: row.amount,
    recipient: row.recipient,
    marketEndTime: parseInt(row.market_end_time, 10),
    status: row.status,
    yesPrice: row.yes_price,
    noPrice: row.no_price,
    totalYesVolume: row.total_yes_volume,
    totalNoVolume: row.total_no_volume,
    totalTrades: row.total_trades,
    finalYesPrice: row.final_yes_price,
    finalNoPrice: row.final_no_price,
    passed: row.passed,
    resolvedAt: row.resolved_at?.toISOString() ?? null,
    createdAt: row.created_at.toISOString(),
  };
}

/**
 * Get trades for a futarchy proposal
 */
export async function getFutarchyTradesByProposal(
  proposalId: string,
  pagination: PaginationParams
): Promise<PaginatedResponse<FutarchyTradeListItem>> {
  const db = getDb();

  const countResult = await db.query<{ count: string }>(
    `SELECT COUNT(*) as count FROM futarchy_trades
     WHERE proposal_id = $1 AND NOT is_reorged`,
    [proposalId]
  );
  const total = parseInt(countResult.rows[0]?.count ?? "0", 10);

  const offset = (pagination.page - 1) * pagination.limit;
  const dataResult = await db.query<{
    proposal_id: string;
    trader: string;
    is_yes: boolean;
    amount_in: string;
    amount_out: string;
    new_price: string;
    tx_hash: string;
    block_number: string;
    created_at: Date;
  }>(
    `SELECT proposal_id, trader, is_yes, amount_in, amount_out, new_price,
            tx_hash, block_number::TEXT, created_at
     FROM futarchy_trades
     WHERE proposal_id = $1 AND NOT is_reorged
     ORDER BY block_number DESC, log_index DESC
     LIMIT $2 OFFSET $3`,
    [proposalId, pagination.limit, offset]
  );

  return {
    data: dataResult.rows.map((row) => ({
      proposalId: row.proposal_id,
      trader: row.trader,
      isYes: row.is_yes,
      amountIn: row.amount_in,
      amountOut: row.amount_out,
      newPrice: row.new_price,
      txHash: row.tx_hash,
      blockNumber: row.block_number,
      createdAt: row.created_at.toISOString(),
    })),
    pagination: {
      page: pagination.page,
      limit: pagination.limit,
      total,
      totalPages: Math.ceil(total / pagination.limit),
    },
  };
}

/**
 * Get current prices for a futarchy proposal
 */
export async function getFutarchyPrices(
  proposalId: string
): Promise<FutarchyPriceData | null> {
  const db = getDb();

  // Get proposal data
  const proposalResult = await db.query<{
    id: string;
    yes_price: string;
    no_price: string;
    market_end_time: string;
    status: FutarchyProposalStatus;
  }>(
    `SELECT id, yes_price, no_price, market_end_time::TEXT, status
     FROM futarchy_proposals
     WHERE id = $1 AND NOT is_reorged`,
    [proposalId]
  );

  if (proposalResult.rows.length === 0) {
    return null;
  }

  const proposal = proposalResult.rows[0]!;

  // Get last trade timestamp
  const lastTradeResult = await db.query<{ created_at: Date }>(
    `SELECT created_at FROM futarchy_trades
     WHERE proposal_id = $1 AND NOT is_reorged
     ORDER BY block_number DESC, log_index DESC
     LIMIT 1`,
    [proposalId]
  );

  const yesPrice = BigInt(proposal.yes_price);
  const impliedProbability = Number(yesPrice * 100n / BigInt("1000000000000000000"));
  const marketEndTime = parseInt(proposal.market_end_time, 10);
  const now = Math.floor(Date.now() / 1000);

  return {
    proposalId: proposal.id,
    yesPrice: proposal.yes_price,
    noPrice: proposal.no_price,
    impliedProbability,
    lastTradeAt: lastTradeResult.rows[0]?.created_at.toISOString() ?? null,
    marketEndTime,
    isActive: proposal.status === "active" && marketEndTime > now,
  };
}

/**
 * Get treasury statistics
 */
export async function getTreasuryStats(): Promise<TreasuryStats> {
  const db = getDb();

  const result = await db.query<{
    total_proposals: string;
    active_proposals: string;
    total_volume: string;
    total_trades: string;
    proposals_passed: string;
    proposals_failed: string;
    total_allocated: string;
  }>(`
    SELECT
      (SELECT COUNT(*) FROM futarchy_proposals WHERE NOT is_reorged) as total_proposals,
      (SELECT COUNT(*) FROM futarchy_proposals WHERE NOT is_reorged AND status = 'active') as active_proposals,
      (SELECT COALESCE(SUM(amount_in::NUMERIC), 0)::TEXT FROM futarchy_trades WHERE NOT is_reorged) as total_volume,
      (SELECT COUNT(*) FROM futarchy_trades WHERE NOT is_reorged) as total_trades,
      (SELECT COUNT(*) FROM futarchy_proposals WHERE NOT is_reorged AND passed = true) as proposals_passed,
      (SELECT COUNT(*) FROM futarchy_proposals WHERE NOT is_reorged AND passed = false) as proposals_failed,
      (SELECT COALESCE(SUM(amount::NUMERIC), 0)::TEXT FROM futarchy_proposals WHERE NOT is_reorged AND passed = true) as total_allocated
  `);

  const row = result.rows[0]!;
  return {
    totalProposals: parseInt(row.total_proposals, 10),
    activeProposals: parseInt(row.active_proposals, 10),
    totalVolume: row.total_volume,
    totalTrades: parseInt(row.total_trades, 10),
    proposalsPassed: parseInt(row.proposals_passed, 10),
    proposalsFailed: parseInt(row.proposals_failed, 10),
    totalAllocated: row.total_allocated,
  };
}
