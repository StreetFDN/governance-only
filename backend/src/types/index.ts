/**
 * Street Governance - Type Definitions
 *
 * Core types for the governance indexer and API.
 */

// =============================================================================
// Blockchain Event Types (mapped from contract events)
// =============================================================================

/**
 * ProposalCreated event from StreetGovernor
 * Emitted when a new proposal is created with staked KLED
 */
export interface ProposalCreatedEvent {
  proposalId: bigint;
  proposer: `0x${string}`;
  title: string;
  description: string;
  targets: `0x${string}`[];
  values: bigint[];
  calldatas: `0x${string}`[];
  startBlock: bigint;
  endBlock: bigint;
  stakeAmount: bigint; // 50,000 KLED staked
}

/**
 * VoteCast event from StreetGovernor
 * Emitted when a user casts a vote
 */
export interface VoteCastEvent {
  proposalId: bigint;
  voter: `0x${string}`;
  support: VoteSupport;
  weight: bigint; // Voting power (KLED balance at snapshot)
  reason: string;
}

/**
 * Vote support values
 */
export enum VoteSupport {
  Against = 0,
  For = 1,
  Abstain = 2,
}

/**
 * ProposalExecuted event from StreetGovernor
 */
export interface ProposalExecutedEvent {
  proposalId: bigint;
}

/**
 * ProposalCanceled event from StreetGovernor
 */
export interface ProposalCanceledEvent {
  proposalId: bigint;
}

/**
 * Slashed event from StreetGovernor
 * Emitted when a proposal fails and proposer loses 10% stake
 */
export interface SlashedEvent {
  proposalId: bigint;
  proposer: `0x${string}`;
  slashedAmount: bigint;
  returnedAmount: bigint;
}

/**
 * EditSuggested event from EditSuggestions contract
 * Emitted when someone suggests an edit to a proposal
 */
export interface EditSuggestedEvent {
  suggestionId: bigint;
  proposalId: bigint;
  suggester: `0x${string}`;
  originalHash: `0x${string}`;
  proposedText: string;
  stakeAmount: bigint; // 500 KLED staked
  editWindowEnd: bigint; // timestamp
  voteWindowEnd: bigint; // timestamp
}

/**
 * SuggestionVoted event from EditSuggestions contract
 * Emitted when someone votes on an edit suggestion
 */
export interface SuggestionVotedEvent {
  suggestionId: bigint;
  voter: `0x${string}`;
  support: boolean;
  weight: bigint;
}

// =============================================================================
// Futarchy Treasury Event Types
// =============================================================================

/**
 * FutarchyProposalCreated event from FutarchyTreasury contract
 * Emitted when a new treasury allocation proposal is created with prediction markets
 */
export interface FutarchyProposalCreatedEvent {
  proposalId: bigint;
  description: string;
  amount: bigint; // Treasury amount requested
  recipient: `0x${string}`; // Where funds would go
  marketEndTime: bigint; // When prediction market closes
}

/**
 * TradePlaced event from FutarchyTreasury contract
 * Emitted when a user trades in the YES/NO prediction markets
 */
export interface TradePlacedEvent {
  proposalId: bigint;
  trader: `0x${string}`;
  isYes: boolean; // true = YES market, false = NO market
  amountIn: bigint; // Collateral spent
  amountOut: bigint; // Outcome tokens received
  newPrice: bigint; // New market price (18 decimals, 0-1e18)
}

/**
 * ProposalResolved event from FutarchyTreasury contract
 * Emitted when prediction market ends and proposal is resolved
 */
export interface ProposalResolvedEvent {
  proposalId: bigint;
  passed: boolean; // Did proposal pass based on market prices?
  yesPrice: bigint; // Final YES market price
  noPrice: bigint; // Final NO market price
}

/**
 * CollateralRedeemed event from FutarchyTreasury contract
 * Emitted when user redeems winning outcome tokens for collateral
 */
export interface CollateralRedeemedEvent {
  proposalId: bigint;
  user: `0x${string}`;
  amount: bigint; // Collateral redeemed
}

// =============================================================================
// Database Entity Types
// =============================================================================

/**
 * Event metadata stored with every indexed event
 */
export interface EventMeta {
  txHash: `0x${string}`;
  logIndex: number;
  blockNumber: bigint;
  blockHash: `0x${string}`;
  timestamp: number; // Unix timestamp from block
  isReorged: boolean;
  reorgedAt: Date | null;
}

/**
 * Proposal entity in database
 */
export interface Proposal extends EventMeta {
  id: string; // proposalId as string
  proposer: string;
  title: string;
  description: string;
  targets: string[]; // JSON array of addresses
  values: string[]; // JSON array of bigint strings
  calldatas: string[]; // JSON array of calldata hex strings
  startBlock: string;
  endBlock: string;
  stakeAmount: string;
  status: ProposalStatus;
  // Aggregated vote counts (updated on VoteCast)
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  // Execution/cancellation tracking
  executedAt: Date | null;
  canceledAt: Date | null;
  // Slashing tracking
  slashedAmount: string | null;
  createdAt: Date;
}

/**
 * Proposal status derived from events and block numbers
 */
export enum ProposalStatus {
  Pending = "pending", // Before startBlock
  Active = "active", // Voting in progress
  Defeated = "defeated", // Failed vote
  Succeeded = "succeeded", // Passed vote, awaiting execution
  Executed = "executed", // Successfully executed
  Canceled = "canceled", // Canceled by proposer
  Expired = "expired", // Not executed in time
}

/**
 * Vote entity in database
 */
export interface Vote extends EventMeta {
  id: number; // Auto-increment
  proposalId: string;
  voter: string;
  support: VoteSupport;
  weight: string; // bigint as string
  reason: string;
  createdAt: Date;
}

/**
 * Edit suggestion entity in database
 */
export interface EditSuggestion extends EventMeta {
  id: string; // suggestionId as string
  proposalId: string;
  suggester: string;
  originalHash: string;
  proposedText: string;
  stakeAmount: string;
  editWindowEnd: number; // Unix timestamp
  voteWindowEnd: number; // Unix timestamp
  status: SuggestionStatus;
  // Aggregated vote counts
  forVotes: string;
  againstVotes: string;
  createdAt: Date;
}

/**
 * Suggestion status
 */
export enum SuggestionStatus {
  Pending = "pending", // Within edit window
  Voting = "voting", // Within vote window
  Accepted = "accepted", // Passed vote
  Rejected = "rejected", // Failed vote
  Expired = "expired", // Vote window ended without resolution
}

/**
 * Suggestion vote entity in database
 */
export interface SuggestionVote extends EventMeta {
  id: number; // Auto-increment
  suggestionId: string;
  voter: string;
  support: boolean;
  weight: string;
  createdAt: Date;
}

/**
 * Slash event entity in database
 */
export interface SlashRecord extends EventMeta {
  id: number;
  proposalId: string;
  proposer: string;
  slashedAmount: string;
  returnedAmount: string;
  createdAt: Date;
}

// =============================================================================
// Futarchy Treasury Entity Types
// =============================================================================

/**
 * Futarchy proposal status
 */
export enum FutarchyProposalStatus {
  Active = "active", // Market is open for trading
  Resolved = "resolved", // Market closed, proposal resolved
  Executed = "executed", // Funds transferred (if passed)
  Expired = "expired", // Market ended without resolution
}

/**
 * Futarchy treasury proposal entity in database
 */
export interface FutarchyProposal extends EventMeta {
  id: string; // proposalId as string
  description: string;
  amount: string; // Requested treasury amount
  recipient: string;
  marketEndTime: number; // Unix timestamp
  status: FutarchyProposalStatus;
  // Current market prices (updated on each trade)
  yesPrice: string; // 18 decimals, 0-1e18
  noPrice: string;
  // Final prices (set on resolution)
  finalYesPrice: string | null;
  finalNoPrice: string | null;
  passed: boolean | null;
  // Aggregated stats
  totalYesVolume: string;
  totalNoVolume: string;
  totalTrades: number;
  resolvedAt: Date | null;
  createdAt: Date;
}

/**
 * Futarchy trade entity in database
 */
export interface FutarchyTrade extends EventMeta {
  id: number;
  proposalId: string;
  trader: string;
  isYes: boolean;
  amountIn: string;
  amountOut: string;
  newPrice: string;
  createdAt: Date;
}

/**
 * Futarchy collateral redemption entity in database
 */
export interface FutarchyRedemption extends EventMeta {
  id: number;
  proposalId: string;
  user: string;
  amount: string;
  createdAt: Date;
}

/**
 * Indexer checkpoint for resume and reorg handling
 */
export interface IndexerCheckpoint {
  id: number;
  lastIndexedBlock: string;
  lastIndexedHash: string;
  updatedAt: Date;
}

// =============================================================================
// API Response Types
// =============================================================================

export interface PaginationParams {
  page: number;
  limit: number;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

export interface ProposalListItem {
  id: string;
  proposer: string;
  title: string;
  status: ProposalStatus;
  startBlock: string;
  endBlock: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  createdAt: string;
}

export interface ProposalDetail extends ProposalListItem {
  description: string;
  targets: string[];
  values: string[];
  calldatas: string[];
  stakeAmount: string;
  executedAt: string | null;
  canceledAt: string | null;
  slashedAmount: string | null;
  suggestions: EditSuggestionListItem[];
}

export interface VoteListItem {
  proposalId: string;
  voter: string;
  support: VoteSupport;
  weight: string;
  reason: string;
  txHash: string;
  blockNumber: string;
  createdAt: string;
}

export interface EditSuggestionListItem {
  id: string;
  proposalId: string;
  suggester: string;
  proposedText: string;
  status: SuggestionStatus;
  forVotes: string;
  againstVotes: string;
  voteWindowEnd: number;
  createdAt: string;
}

export interface GovernanceStats {
  totalProposals: number;
  activeProposals: number;
  totalVotes: number;
  uniqueVoters: number;
  totalStaked: string;
  totalSlashed: string;
  participationRate: number;
}

export interface IndexerStatus {
  isRunning: boolean;
  lastIndexedBlock: string;
  chainHead: string;
  lag: number;
  lastUpdateAt: string;
}

// =============================================================================
// Futarchy Treasury API Response Types
// =============================================================================

export interface FutarchyProposalListItem {
  id: string;
  description: string;
  amount: string;
  recipient: string;
  marketEndTime: number;
  status: FutarchyProposalStatus;
  yesPrice: string;
  noPrice: string;
  totalTrades: number;
  createdAt: string;
}

export interface FutarchyProposalDetail extends FutarchyProposalListItem {
  totalYesVolume: string;
  totalNoVolume: string;
  finalYesPrice: string | null;
  finalNoPrice: string | null;
  passed: boolean | null;
  resolvedAt: string | null;
}

export interface FutarchyTradeListItem {
  proposalId: string;
  trader: string;
  isYes: boolean;
  amountIn: string;
  amountOut: string;
  newPrice: string;
  txHash: string;
  blockNumber: string;
  createdAt: string;
}

export interface FutarchyPriceData {
  proposalId: string;
  yesPrice: string;
  noPrice: string;
  impliedProbability: number; // YES price as percentage (0-100)
  lastTradeAt: string | null;
  marketEndTime: number;
  isActive: boolean;
}

export interface TreasuryStats {
  totalProposals: number;
  activeProposals: number;
  totalVolume: string;
  totalTrades: number;
  proposalsPassed: number;
  proposalsFailed: number;
  totalAllocated: string;
}

// =============================================================================
// Contract ABI Event Signatures (placeholder - waiting for SOL)
// =============================================================================

/**
 * Event signatures for filtering logs
 * TODO: Replace with actual ABI from SOL team
 */
export const EVENT_SIGNATURES = {
  // StreetGovernor events
  ProposalCreated:
    "ProposalCreated(uint256,address,string,string,address[],uint256[],bytes[],uint256,uint256,uint256)",
  VoteCast: "VoteCast(uint256,address,uint8,uint256,string)",
  ProposalExecuted: "ProposalExecuted(uint256)",
  ProposalCanceled: "ProposalCanceled(uint256)",
  Slashed: "Slashed(uint256,address,uint256,uint256)",

  // EditSuggestions events
  EditSuggested:
    "EditSuggested(uint256,uint256,address,bytes32,string,uint256,uint256,uint256)",
  SuggestionVoted: "SuggestionVoted(uint256,address,bool,uint256)",

  // FutarchyTreasury events
  FutarchyProposalCreated:
    "FutarchyProposalCreated(uint256,string,uint256,address,uint256)",
  TradePlaced: "TradePlaced(uint256,address,bool,uint256,uint256,uint256)",
  ProposalResolved: "ProposalResolved(uint256,bool,uint256,uint256)",
  CollateralRedeemed: "CollateralRedeemed(uint256,address,uint256)",
} as const;

/**
 * Contract addresses (placeholder - waiting for deployment)
 */
export interface ContractAddresses {
  kledToken: `0x${string}`;
  streetGovernor: `0x${string}`;
  editSuggestions: `0x${string}`;
  timelock: `0x${string}`;
  futarchyTreasury: `0x${string}`;
}
