# Governance Indexer & API

A Node.js/TypeScript backend for indexing and serving Base L2 governance data.

## Overview

This service consists of two main components:

1. **Indexer**: Monitors the Base L2 blockchain for governance events and stores them in a database
2. **API**: Provides REST endpoints for querying indexed governance data

## Getting Started

### Prerequisites

- Node.js >= 18.0.0
- A PostgreSQL database (or SQLite for development)
- Access to a Base L2 RPC endpoint

### Installation

```bash
npm install
```

### Configuration

Create a `.env` file in the project root:

```env
# RPC Configuration
BASE_RPC_URL=https://mainnet.base.org

# API Configuration
PORT=3000

# Database Configuration
DATABASE_URL=postgresql://user:password@localhost:5432/governance

# Indexer Configuration
INDEXER_START_BLOCK=0
INDEXER_CONFIRMATION_DEPTH=64
INDEXER_BATCH_SIZE=1000
```

### Running the Service

**Development mode** (with hot reload):
```bash
npm run dev
```

**Production mode**:
```bash
npm run build
npm start
```

**Run tests**:
```bash
npm test          # Watch mode
npm run test:run  # Single run
```

## Key Design Decisions

### Idempotency

The indexer is designed to be safely restartable at any point without creating duplicate data or missing events.

**Strategies employed:**

1. **Unique Constraints**: Each event is uniquely identified by `(txHash, logIndex)`. Database inserts use `ON CONFLICT DO NOTHING` to prevent duplicates.

2. **Checkpoint System**: After processing each batch of blocks, the indexer persists a checkpoint (block number + block hash). On restart, it resumes from the last checkpoint.

3. **Atomic Batches**: Events are processed in database transactions. If any operation fails, the entire batch is rolled back, ensuring no partial state.

4. **Deterministic Processing**: Event processing produces the same output given the same input. No timestamps or random values are used in derived data.

### Reorg Handling

Chain reorganizations can invalidate indexed data. The indexer handles this gracefully:

1. **Confirmation Depth**: By default, only blocks with 64+ confirmations are considered final (~2 minutes on Base L2). This prevents most reorgs from affecting indexed data.

2. **Block Hash Verification**: Each indexed block stores its hash. When fetching new blocks, the parent hash is verified against the stored hash of the previous block. A mismatch indicates a reorg.

3. **Soft Deletes**: When a reorg is detected, affected events are marked as `is_reorged = true` rather than deleted. This preserves an audit trail and allows for recovery if needed.

4. **Automatic Recovery**: After marking reorged events, the indexer rolls back its checkpoint and re-indexes from the fork point.

**Example reorg scenario:**
```
Original chain: ... -> Block 99 -> Block 100 -> Block 101
Reorged chain:  ... -> Block 99 -> Block 100' -> Block 101'

1. Indexer detects Block 100's parent hash doesn't match Block 99
2. Events in blocks >= 100 are soft-deleted
3. Checkpoint is reset to block 99
4. Indexer re-fetches and processes blocks 100', 101', ...
```

### Event Types Indexed

The indexer tracks these governance events:

| Event | Description |
|-------|-------------|
| `ProposalCreated` | New governance proposal submitted |
| `VoteCast` | Vote cast on a proposal |
| `ProposalExecuted` | Proposal successfully executed |
| `ProposalCanceled` | Proposal canceled by proposer |
| `QuorumUpdated` | Quorum threshold changed |
| `VotingDelayUpdated` | Voting delay parameter changed |
| `VotingPeriodUpdated` | Voting period parameter changed |

## Integration with Contracts

### Contract ABIs

The indexer requires ABIs for the governance contracts to decode events. Place ABI files in `src/abis/`:

```
src/abis/
  Governor.json
  GovernanceToken.json
```

### Contract Addresses

Configure contract addresses in `.env`:

```env
GOVERNOR_ADDRESS=0x...
GOVERNANCE_TOKEN_ADDRESS=0x...
```

### Adding New Contracts

To index events from additional contracts:

1. Add the contract ABI to `src/abis/`
2. Add the contract address to `.env`
3. Update `src/indexer/index.ts` to include the new event signatures
4. Add database schema for new event types in `src/db/index.ts`
5. Add API endpoints in `src/api/index.ts`

## API Endpoints

### Health

- `GET /health` - Service health check
- `GET /health/indexer` - Indexer status and last indexed block

### Proposals

- `GET /api/proposals` - List proposals (paginated)
- `GET /api/proposals/:id` - Get proposal details
- `GET /api/proposals/:id/votes` - Get votes for a proposal

### Votes

- `GET /api/votes` - List all votes (paginated)
- `GET /api/votes/voter/:address` - Get votes by voter address

### Statistics

- `GET /api/stats` - Overall governance statistics

## Project Structure

```
backend/
├── src/
│   ├── index.ts        # Entry point
│   ├── indexer/
│   │   └── index.ts    # Blockchain indexer
│   ├── api/
│   │   └── index.ts    # REST API
│   └── db/
│       └── index.ts    # Database operations
├── tests/
│   └── indexer.test.ts # Test suite
├── package.json
├── tsconfig.json
└── README.md
```

## Development

### Type Checking

```bash
npm run typecheck
```

### Linting

```bash
npm run lint
```

## License

MIT
