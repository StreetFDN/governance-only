# Street Governance Backend - Operations Runbook

## Overview

Backend indexer and API for Street Governance dApp on Base L2.

**Components:**
- **Indexer**: Consumes contract events, handles reorgs, maintains state
- **API**: Serves frontend, rate-limited, idempotent
- **Database**: PostgreSQL with soft-delete reorg handling

---

## Quick Start

```bash
# Install dependencies
npm install

# Set environment variables
cp .env.example .env
# Edit .env with your configuration

# Run database migrations
psql $DATABASE_URL < src/db/schema.sql

# Start development server
npm run dev

# Run tests
npm run test
```

---

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | - | PostgreSQL connection string |
| `BASE_RPC_URL` | Yes | - | Base L2 RPC endpoint |
| `PORT` | No | 3000 | API server port |
| `GOVERNOR_ADDRESS` | Yes | - | StreetGovernor contract address |
| `EDIT_SUGGESTIONS_ADDRESS` | Yes | - | EditSuggestions contract address |
| `INDEXER_START_BLOCK` | No | 0 | Block to start indexing from |
| `INDEXER_CONFIRMATION_DEPTH` | No | 64 | Blocks to wait for finality |
| `INDEXER_BATCH_SIZE` | No | 1000 | Events to process per batch |
| `INDEXER_POLL_INTERVAL_MS` | No | 2000 | Polling interval in ms |

### Example .env

```env
DATABASE_URL=postgresql://governance:password@localhost:5432/street_governance
BASE_RPC_URL=https://mainnet.base.org
PORT=3000

GOVERNOR_ADDRESS=0x...
EDIT_SUGGESTIONS_ADDRESS=0x...

# Optional tuning
INDEXER_START_BLOCK=12345678
INDEXER_CONFIRMATION_DEPTH=64
INDEXER_BATCH_SIZE=1000
```

---

## Reorg Handling Strategy

### Base L2 Characteristics

- **Block time**: ~2 seconds
- **Confirmation depth**: 64 blocks (~2 minutes)
- **Reorg frequency**: Rare, but possible during sequencer issues

### Our Strategy

1. **Confirmation Depth**: Only process blocks that have 64+ confirmations
2. **Block Hash Verification**: Store block hash with every event
3. **Reorg Detection**: On each cycle, verify stored hashes match chain
4. **Soft Delete Recovery**: Mark affected events as `is_reorged = true`
5. **Automatic Re-indexing**: Resume from last valid block

### Reorg Detection Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Indexing Loop                           │
├─────────────────────────────────────────────────────────────┤
│  1. Get chain head                                          │
│  2. Calculate safe block (head - 64)                        │
│  3. Check last 10 indexed blocks for hash mismatches        │
│     ├─ If mismatch found → Handle reorg                     │
│     └─ If no mismatch → Process new blocks                  │
│  4. Fetch events in batch                                   │
│  5. Process within DB transaction                           │
│  6. Update checkpoint                                       │
│  7. Sleep and repeat                                        │
└─────────────────────────────────────────────────────────────┘
```

### Reorg Handling Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Reorg Handler                            │
├─────────────────────────────────────────────────────────────┤
│  1. Reorg detected at block N                               │
│  2. Call mark_reorged_from_block(N)                         │
│     - UPDATE proposals SET is_reorged=true WHERE block>=N   │
│     - UPDATE votes SET is_reorged=true WHERE block>=N       │
│     - UPDATE edit_suggestions SET is_reorged=true...        │
│     - UPDATE suggestion_votes SET is_reorged=true...        │
│     - UPDATE slashes SET is_reorged=true...                 │
│  3. Roll back checkpoint to block N-1                       │
│  4. Resume indexing from block N                            │
└─────────────────────────────────────────────────────────────┘
```

### Key Database Constraints

- **Idempotency**: `UNIQUE(tx_hash, log_index)` on all event tables
- **Soft Delete**: All queries include `WHERE NOT is_reorged`
- **Atomic Processing**: Events processed within transactions

---

## API Endpoints

### Health

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Basic health check |
| `GET /health/indexer` | Indexer status, lag, last error |

### Proposals

| Endpoint | Description |
|----------|-------------|
| `GET /api/proposals` | List proposals (paginated) |
| `GET /api/proposals/:id` | Get proposal with suggestions |
| `GET /api/proposals/:id/votes` | Get votes for proposal |

**Query Parameters:**
- `page` (default: 1)
- `limit` (default: 20, max: 100)
- `status` (filter: pending, active, defeated, succeeded, executed, canceled, expired)
- `proposer` (filter: 0x address)

### Votes

| Endpoint | Description |
|----------|-------------|
| `GET /api/votes/voter/:address` | Get votes by voter |

### Statistics

| Endpoint | Description |
|----------|-------------|
| `GET /api/stats` | Governance statistics |

---

## Monitoring

### Key Metrics to Watch

1. **Indexer Lag**: `chainHead - lastIndexedBlock`
   - Alert if > 100 blocks
   - Check RPC connectivity

2. **Reorg Count**: `reorgsHandled`
   - Normally 0
   - Spike indicates chain issues

3. **Error Rate**: API 5xx responses
   - Check database connectivity
   - Check disk space

### Health Check Responses

**Healthy:**
```json
{
  "status": "ok",
  "indexer": {
    "isRunning": true,
    "lastIndexedBlock": "12345678",
    "chainHead": "12345742",
    "lag": 64
  }
}
```

**Lagging (warning):**
```json
{
  "status": "lagging",
  "indexer": {
    "lag": 150
  }
}
```

**Down (error):**
```json
{
  "status": "error",
  "message": "Indexer not running"
}
```

---

## Troubleshooting

### Indexer Not Starting

1. Check database connectivity:
   ```bash
   psql $DATABASE_URL -c "SELECT 1"
   ```

2. Check RPC connectivity:
   ```bash
   curl -X POST $BASE_RPC_URL \
     -H "Content-Type: application/json" \
     -d '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'
   ```

3. Check contract addresses are valid

### Indexer Lagging

1. Check RPC rate limits
2. Increase batch size (if RPC allows)
3. Check database performance
4. Consider multiple indexer instances (future)

### Duplicate Events

Events should be idempotent due to `ON CONFLICT DO NOTHING`. If duplicates appear:

1. Check `UNIQUE(tx_hash, log_index)` constraint exists
2. Verify constraint isn't disabled

### Reorg Loop

If indexer is constantly handling reorgs:

1. Increase confirmation depth (e.g., 128 blocks)
2. Check chain health
3. Consider switching RPC provider

### Missing Events

1. Check indexer start block
2. Verify contract addresses
3. Query logs directly:
   ```sql
   SELECT * FROM proposals
   WHERE NOT is_reorged
   ORDER BY block_number DESC
   LIMIT 10;
   ```

---

## Database Operations

### Manual Checkpoint Reset

```sql
-- Reset to specific block (DANGEROUS - requires re-index)
UPDATE indexer_checkpoint
SET last_indexed_block = 12345000,
    last_indexed_hash = '0x...',
    updated_at = NOW()
WHERE id = 1;
```

### Clear Reorged Events

```sql
-- Delete soft-deleted events (run during maintenance)
DELETE FROM votes WHERE is_reorged = true AND reorged_at < NOW() - INTERVAL '7 days';
DELETE FROM proposals WHERE is_reorged = true AND reorged_at < NOW() - INTERVAL '7 days';
-- etc.
```

### Recalculate Vote Totals

```sql
-- If vote counts are wrong after reorg
SELECT recalculate_proposal_votes('12345');
```

### Check Index Health

```sql
-- Events by day
SELECT DATE(created_at), COUNT(*)
FROM votes
WHERE NOT is_reorged
GROUP BY DATE(created_at);

-- Reorged events
SELECT COUNT(*) as reorged,
       MAX(reorged_at) as last_reorg
FROM proposals
WHERE is_reorged = true;
```

---

## Deployment Checklist

### Pre-deployment

- [ ] Database migrations applied
- [ ] Environment variables set
- [ ] Contract addresses verified
- [ ] Start block configured
- [ ] RPC endpoint tested

### Post-deployment

- [ ] `/health` returns OK
- [ ] `/health/indexer` shows running
- [ ] First events being indexed
- [ ] API endpoints responding

### Rollback

1. Stop application
2. Restore database from backup
3. Reset checkpoint to pre-deployment block
4. Restart with previous version

---

## Event Types Indexed

| Event | Contract | Description |
|-------|----------|-------------|
| `ProposalCreated` | StreetGovernor | New proposal with stake |
| `VoteCast` | StreetGovernor | Vote on proposal |
| `ProposalExecuted` | StreetGovernor | Proposal executed |
| `ProposalCanceled` | StreetGovernor | Proposal canceled |
| `Slashed` | StreetGovernor | Proposer stake slashed |
| `EditSuggested` | EditSuggestions | Edit suggestion created |
| `SuggestionVoted` | EditSuggestions | Vote on edit suggestion |

---

## Contacts

- **Backend**: BE team
- **Contracts**: SOL team
- **Infrastructure**: OPS team

---

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-20 | BE | Initial runbook |
