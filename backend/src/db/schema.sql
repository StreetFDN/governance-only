-- Street Governance Database Schema
-- PostgreSQL schema for indexing governance events
--
-- Key Design Principles:
-- 1. Idempotency: UNIQUE(tx_hash, log_index) prevents duplicate events
-- 2. Reorg handling: is_reorged + reorged_at for soft deletes
-- 3. Auditability: All events retain full provenance (block, tx, log)

-- =============================================================================
-- Indexer State
-- =============================================================================

CREATE TABLE IF NOT EXISTS indexer_checkpoint (
    id SERIAL PRIMARY KEY,
    last_indexed_block BIGINT NOT NULL,
    last_indexed_hash VARCHAR(66) NOT NULL,
    chain_head_block BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Single row constraint for checkpoint
CREATE UNIQUE INDEX IF NOT EXISTS idx_indexer_checkpoint_singleton
    ON indexer_checkpoint ((true));

-- =============================================================================
-- Proposals
-- =============================================================================

CREATE TABLE IF NOT EXISTS proposals (
    id VARCHAR(78) PRIMARY KEY, -- uint256 as decimal string
    proposer VARCHAR(42) NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    targets JSONB NOT NULL DEFAULT '[]', -- array of addresses
    values JSONB NOT NULL DEFAULT '[]', -- array of bigint strings
    calldatas JSONB NOT NULL DEFAULT '[]', -- array of hex strings
    start_block BIGINT NOT NULL,
    end_block BIGINT NOT NULL,
    stake_amount VARCHAR(78) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',

    -- Aggregated vote counts (updated by triggers or app)
    for_votes VARCHAR(78) NOT NULL DEFAULT '0',
    against_votes VARCHAR(78) NOT NULL DEFAULT '0',
    abstain_votes VARCHAR(78) NOT NULL DEFAULT '0',

    -- Execution/cancellation
    executed_at TIMESTAMP WITH TIME ZONE,
    canceled_at TIMESTAMP WITH TIME ZONE,
    slashed_amount VARCHAR(78),

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT proposals_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_proposals_status ON proposals(status) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_proposals_proposer ON proposals(proposer) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_proposals_block ON proposals(block_number) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_proposals_start_block ON proposals(start_block) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_proposals_end_block ON proposals(end_block) WHERE NOT is_reorged;

-- =============================================================================
-- Votes
-- =============================================================================

CREATE TABLE IF NOT EXISTS votes (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES proposals(id),
    voter VARCHAR(42) NOT NULL,
    support SMALLINT NOT NULL CHECK (support IN (0, 1, 2)), -- Against, For, Abstain
    weight VARCHAR(78) NOT NULL,
    reason TEXT NOT NULL DEFAULT '',

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT votes_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_votes_proposal ON votes(proposal_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes(voter) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_votes_block ON votes(block_number) WHERE NOT is_reorged;

-- =============================================================================
-- Edit Suggestions
-- =============================================================================

CREATE TABLE IF NOT EXISTS edit_suggestions (
    id VARCHAR(78) PRIMARY KEY, -- suggestionId as decimal string
    proposal_id VARCHAR(78) NOT NULL REFERENCES proposals(id),
    suggester VARCHAR(42) NOT NULL,
    original_hash VARCHAR(66) NOT NULL,
    proposed_text TEXT NOT NULL,
    stake_amount VARCHAR(78) NOT NULL,
    edit_window_end BIGINT NOT NULL, -- Unix timestamp
    vote_window_end BIGINT NOT NULL, -- Unix timestamp
    status VARCHAR(20) NOT NULL DEFAULT 'pending',

    -- Aggregated vote counts
    for_votes VARCHAR(78) NOT NULL DEFAULT '0',
    against_votes VARCHAR(78) NOT NULL DEFAULT '0',

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT suggestions_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_suggestions_proposal ON edit_suggestions(proposal_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_suggestions_suggester ON edit_suggestions(suggester) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_suggestions_status ON edit_suggestions(status) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_suggestions_block ON edit_suggestions(block_number) WHERE NOT is_reorged;

-- =============================================================================
-- Suggestion Votes
-- =============================================================================

CREATE TABLE IF NOT EXISTS suggestion_votes (
    id SERIAL PRIMARY KEY,
    suggestion_id VARCHAR(78) NOT NULL REFERENCES edit_suggestions(id),
    voter VARCHAR(42) NOT NULL,
    support BOOLEAN NOT NULL,
    weight VARCHAR(78) NOT NULL,

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT suggestion_votes_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_suggestion_votes_suggestion ON suggestion_votes(suggestion_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_suggestion_votes_voter ON suggestion_votes(voter) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_suggestion_votes_block ON suggestion_votes(block_number) WHERE NOT is_reorged;

-- =============================================================================
-- Slashes
-- =============================================================================

CREATE TABLE IF NOT EXISTS slashes (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES proposals(id),
    proposer VARCHAR(42) NOT NULL,
    slashed_amount VARCHAR(78) NOT NULL,
    returned_amount VARCHAR(78) NOT NULL,

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT slashes_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_slashes_proposal ON slashes(proposal_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_slashes_proposer ON slashes(proposer) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_slashes_block ON slashes(block_number) WHERE NOT is_reorged;

-- =============================================================================
-- Proposal Executions (separate event tracking)
-- =============================================================================

CREATE TABLE IF NOT EXISTS proposal_executions (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES proposals(id),

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT executions_unique_event UNIQUE (tx_hash, log_index)
);

-- =============================================================================
-- Proposal Cancellations (separate event tracking)
-- =============================================================================

CREATE TABLE IF NOT EXISTS proposal_cancellations (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES proposals(id),

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT cancellations_unique_event UNIQUE (tx_hash, log_index)
);

-- =============================================================================
-- Futarchy Treasury Proposals
-- =============================================================================

CREATE TABLE IF NOT EXISTS futarchy_proposals (
    id VARCHAR(78) PRIMARY KEY, -- proposalId as decimal string
    description TEXT NOT NULL,
    amount VARCHAR(78) NOT NULL, -- Requested treasury amount
    recipient VARCHAR(42) NOT NULL,
    market_end_time BIGINT NOT NULL, -- Unix timestamp
    status VARCHAR(20) NOT NULL DEFAULT 'active',

    -- Current market prices (18 decimals, 0-1e18)
    yes_price VARCHAR(78) NOT NULL DEFAULT '500000000000000000', -- Start at 0.5
    no_price VARCHAR(78) NOT NULL DEFAULT '500000000000000000',

    -- Final prices (set on resolution)
    final_yes_price VARCHAR(78),
    final_no_price VARCHAR(78),
    passed BOOLEAN,

    -- Aggregated stats
    total_yes_volume VARCHAR(78) NOT NULL DEFAULT '0',
    total_no_volume VARCHAR(78) NOT NULL DEFAULT '0',
    total_trades INTEGER NOT NULL DEFAULT 0,

    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT futarchy_proposals_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_futarchy_proposals_status ON futarchy_proposals(status) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_proposals_recipient ON futarchy_proposals(recipient) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_proposals_block ON futarchy_proposals(block_number) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_proposals_market_end ON futarchy_proposals(market_end_time) WHERE NOT is_reorged;

-- =============================================================================
-- Futarchy Trades
-- =============================================================================

CREATE TABLE IF NOT EXISTS futarchy_trades (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES futarchy_proposals(id),
    trader VARCHAR(42) NOT NULL,
    is_yes BOOLEAN NOT NULL, -- true = YES market, false = NO market
    amount_in VARCHAR(78) NOT NULL, -- Collateral spent
    amount_out VARCHAR(78) NOT NULL, -- Outcome tokens received
    new_price VARCHAR(78) NOT NULL, -- Price after trade (18 decimals)

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT futarchy_trades_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_futarchy_trades_proposal ON futarchy_trades(proposal_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_trades_trader ON futarchy_trades(trader) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_trades_block ON futarchy_trades(block_number) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_trades_is_yes ON futarchy_trades(proposal_id, is_yes) WHERE NOT is_reorged;

-- =============================================================================
-- Futarchy Proposal Resolutions
-- =============================================================================

CREATE TABLE IF NOT EXISTS futarchy_resolutions (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES futarchy_proposals(id),
    passed BOOLEAN NOT NULL,
    yes_price VARCHAR(78) NOT NULL,
    no_price VARCHAR(78) NOT NULL,

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT futarchy_resolutions_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_futarchy_resolutions_proposal ON futarchy_resolutions(proposal_id) WHERE NOT is_reorged;

-- =============================================================================
-- Futarchy Collateral Redemptions
-- =============================================================================

CREATE TABLE IF NOT EXISTS futarchy_redemptions (
    id SERIAL PRIMARY KEY,
    proposal_id VARCHAR(78) NOT NULL REFERENCES futarchy_proposals(id),
    user_address VARCHAR(42) NOT NULL,
    amount VARCHAR(78) NOT NULL,

    -- Event provenance
    tx_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    block_number BIGINT NOT NULL,
    block_hash VARCHAR(66) NOT NULL,
    block_timestamp BIGINT NOT NULL,

    -- Reorg handling
    is_reorged BOOLEAN NOT NULL DEFAULT FALSE,
    reorged_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT futarchy_redemptions_unique_event UNIQUE (tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_futarchy_redemptions_proposal ON futarchy_redemptions(proposal_id) WHERE NOT is_reorged;
CREATE INDEX IF NOT EXISTS idx_futarchy_redemptions_user ON futarchy_redemptions(user_address) WHERE NOT is_reorged;

-- =============================================================================
-- Views for common queries
-- =============================================================================

-- Active proposals (non-reorged, within voting window)
CREATE OR REPLACE VIEW active_proposals AS
SELECT * FROM proposals
WHERE NOT is_reorged
  AND status = 'active';

-- Proposal summary with vote totals
CREATE OR REPLACE VIEW proposal_summaries AS
SELECT
    p.id,
    p.proposer,
    p.title,
    p.status,
    p.start_block,
    p.end_block,
    p.for_votes,
    p.against_votes,
    p.abstain_votes,
    p.stake_amount,
    p.created_at,
    COUNT(DISTINCT v.voter) as unique_voters
FROM proposals p
LEFT JOIN votes v ON v.proposal_id = p.id AND NOT v.is_reorged
WHERE NOT p.is_reorged
GROUP BY p.id;

-- Active futarchy proposals (market still open)
CREATE OR REPLACE VIEW active_futarchy_proposals AS
SELECT * FROM futarchy_proposals
WHERE NOT is_reorged
  AND status = 'active'
  AND market_end_time > EXTRACT(EPOCH FROM NOW());

-- Futarchy proposal summary with trade stats
CREATE OR REPLACE VIEW futarchy_proposal_summaries AS
SELECT
    fp.id,
    fp.description,
    fp.amount,
    fp.recipient,
    fp.market_end_time,
    fp.status,
    fp.yes_price,
    fp.no_price,
    fp.total_yes_volume,
    fp.total_no_volume,
    fp.total_trades,
    fp.passed,
    fp.created_at,
    COUNT(DISTINCT ft.trader) as unique_traders,
    MAX(ft.created_at) as last_trade_at
FROM futarchy_proposals fp
LEFT JOIN futarchy_trades ft ON ft.proposal_id = fp.id AND NOT ft.is_reorged
WHERE NOT fp.is_reorged
GROUP BY fp.id;

-- =============================================================================
-- Functions for reorg handling
-- =============================================================================

-- Mark all events from a block as reorged (soft delete)
CREATE OR REPLACE FUNCTION mark_reorged_from_block(from_block BIGINT)
RETURNS TABLE(
    proposals_affected BIGINT,
    votes_affected BIGINT,
    suggestions_affected BIGINT,
    suggestion_votes_affected BIGINT,
    slashes_affected BIGINT,
    futarchy_proposals_affected BIGINT,
    futarchy_trades_affected BIGINT
) AS $$
DECLARE
    p_count BIGINT;
    v_count BIGINT;
    s_count BIGINT;
    sv_count BIGINT;
    sl_count BIGINT;
    fp_count BIGINT;
    ft_count BIGINT;
BEGIN
    UPDATE proposals
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS p_count = ROW_COUNT;

    UPDATE votes
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE edit_suggestions
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS s_count = ROW_COUNT;

    UPDATE suggestion_votes
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS sv_count = ROW_COUNT;

    UPDATE slashes
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS sl_count = ROW_COUNT;

    UPDATE proposal_executions
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;

    UPDATE proposal_cancellations
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;

    -- Futarchy tables
    UPDATE futarchy_proposals
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS fp_count = ROW_COUNT;

    UPDATE futarchy_trades
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;
    GET DIAGNOSTICS ft_count = ROW_COUNT;

    UPDATE futarchy_resolutions
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;

    UPDATE futarchy_redemptions
    SET is_reorged = TRUE, reorged_at = NOW()
    WHERE block_number >= from_block AND NOT is_reorged;

    RETURN QUERY SELECT p_count, v_count, s_count, sv_count, sl_count, fp_count, ft_count;
END;
$$ LANGUAGE plpgsql;

-- Recalculate vote totals for a proposal (after reorg recovery)
CREATE OR REPLACE FUNCTION recalculate_proposal_votes(p_id VARCHAR(78))
RETURNS VOID AS $$
BEGIN
    UPDATE proposals SET
        for_votes = COALESCE((
            SELECT SUM(weight::NUMERIC)::VARCHAR(78)
            FROM votes
            WHERE proposal_id = p_id AND support = 1 AND NOT is_reorged
        ), '0'),
        against_votes = COALESCE((
            SELECT SUM(weight::NUMERIC)::VARCHAR(78)
            FROM votes
            WHERE proposal_id = p_id AND support = 0 AND NOT is_reorged
        ), '0'),
        abstain_votes = COALESCE((
            SELECT SUM(weight::NUMERIC)::VARCHAR(78)
            FROM votes
            WHERE proposal_id = p_id AND support = 2 AND NOT is_reorged
        ), '0')
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;

-- Recalculate futarchy proposal volumes (after reorg recovery)
CREATE OR REPLACE FUNCTION recalculate_futarchy_volumes(fp_id VARCHAR(78))
RETURNS VOID AS $$
DECLARE
    latest_yes_price VARCHAR(78);
    latest_no_price VARCHAR(78);
BEGIN
    -- Get latest prices from most recent trades
    SELECT new_price INTO latest_yes_price
    FROM futarchy_trades
    WHERE proposal_id = fp_id AND is_yes = true AND NOT is_reorged
    ORDER BY block_number DESC, log_index DESC
    LIMIT 1;

    SELECT new_price INTO latest_no_price
    FROM futarchy_trades
    WHERE proposal_id = fp_id AND is_yes = false AND NOT is_reorged
    ORDER BY block_number DESC, log_index DESC
    LIMIT 1;

    UPDATE futarchy_proposals SET
        total_yes_volume = COALESCE((
            SELECT SUM(amount_in::NUMERIC)::VARCHAR(78)
            FROM futarchy_trades
            WHERE proposal_id = fp_id AND is_yes = true AND NOT is_reorged
        ), '0'),
        total_no_volume = COALESCE((
            SELECT SUM(amount_in::NUMERIC)::VARCHAR(78)
            FROM futarchy_trades
            WHERE proposal_id = fp_id AND is_yes = false AND NOT is_reorged
        ), '0'),
        total_trades = COALESCE((
            SELECT COUNT(*)
            FROM futarchy_trades
            WHERE proposal_id = fp_id AND NOT is_reorged
        ), 0),
        yes_price = COALESCE(latest_yes_price, '500000000000000000'),
        no_price = COALESCE(latest_no_price, '500000000000000000')
    WHERE id = fp_id;
END;
$$ LANGUAGE plpgsql;
