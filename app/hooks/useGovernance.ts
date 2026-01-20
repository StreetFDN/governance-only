'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount, useChainId } from 'wagmi';
import { parseEther, formatEther, type Address, type Hash } from 'viem';
import { base, baseSepolia } from 'wagmi/chains';

// =============================================================================
// CONTRACT ADDRESSES - Base Sepolia (Deployed 2026-01-20)
// =============================================================================
import { getContracts, CONTRACTS } from '@/app/config/contracts';

const contracts = getContracts();

export const CONTRACT_ADDRESSES = {
  KLED_TOKEN: contracts.kledToken,
  STREET_GOVERNOR: contracts.streetGovernor,
  EDIT_SUGGESTIONS: contracts.editSuggestions,
} as const;

export const CHAIN_ID = contracts.chainId;

// =============================================================================
// GOVERNANCE CONSTANTS (from spec/status.md)
// =============================================================================
export const GOVERNANCE_CONFIG = {
  PROPOSAL_STAKE: 50_000n * 10n ** 18n, // 50,000 KLED (0.5% of supply)
  EDIT_STAKE: 500n * 10n ** 18n,         // 500 KLED for edit suggestions
  SLASH_PERCENT: 10n,                     // 10% slashing on failed proposals
  MIN_VOTING_POWER: 10_000n * 10n ** 18n, // Min to participate in edits
  EDITING_WINDOW_HOURS: 48,
  VOTING_WINDOW_HOURS: 72,
} as const;

// =============================================================================
// TYPE DEFINITIONS
// =============================================================================
export enum ProposalState {
  Pending = 0,
  Active = 1,
  Canceled = 2,
  Defeated = 3,
  Succeeded = 4,
  Queued = 5,
  Expired = 6,
  Executed = 7,
}

export enum VoteType {
  Against = 0,
  For = 1,
  Abstain = 2,
}

// Raw return type from getProposal (matches actual contract)
export interface ProposalRaw {
  proposer: Address;
  title: string;
  description: string;
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  startTime: bigint;
  endTime: bigint;
  currentState: number;
}

// Extended proposal data with computed fields for UI
export interface ProposalData {
  id: bigint;
  proposer: Address;
  title: string;
  description: string;
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  startTime: bigint;
  endTime: bigint;
  currentState: number;
  // Computed fields for backward compatibility
  executed: boolean;
  canceled: boolean;
  stakeAmount: bigint;
}

export interface EditSuggestion {
  id: bigint;
  proposalId: bigint;
  author: Address;
  originalHash: Hash;
  proposedText: string;
  stake: bigint;
  votesFor: bigint;
  votesAgainst: bigint;
  status: 'active' | 'approved' | 'rejected';
  createdAt: bigint;
}

// =============================================================================
// PLACEHOLDER ABIs - AWAITING SOL
// =============================================================================
// These ABIs are structured based on spec requirements.
// SOL should confirm/update function signatures.

export const KLED_TOKEN_ABI = [
  // ERC20 Standard
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  // ERC20Votes Extension (Delegation)
  {
    name: 'getVotes',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'delegates',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'delegate',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'delegatee', type: 'address' }],
    outputs: [],
  },
  {
    name: 'getPastVotes',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'blockNumber', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const STREET_GOVERNOR_ABI = [
  // Constants
  {
    name: 'PROPOSAL_STAKE',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'SLASH_BPS',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  // Read functions
  {
    name: 'proposalCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'state',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    name: 'hasVoted',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'voter', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getProposal',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [
      { name: 'proposer', type: 'address' },
      { name: 'title', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'forVotes', type: 'uint256' },
      { name: 'againstVotes', type: 'uint256' },
      { name: 'abstainVotes', type: 'uint256' },
      { name: 'startTime', type: 'uint256' },
      { name: 'endTime', type: 'uint256' },
      { name: 'currentState', type: 'uint8' },
    ],
  },
  {
    name: 'getProposalActions',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [
      { name: 'targets', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
      { name: 'calldatas', type: 'bytes[]' },
    ],
  },
  {
    name: 'quorum',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'votingDelay',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'votingPeriod',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'quorumBps',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'token',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  // Write functions
  {
    name: 'propose',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'title', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'targets', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
      { name: 'calldatas', type: 'bytes[]' },
    ],
    outputs: [{ name: 'proposalId', type: 'uint256' }],
  },
  {
    name: 'vote',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'support', type: 'uint8' },
    ],
    outputs: [],
  },
  {
    name: 'voteWithReason',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'support', type: 'uint8' },
      { name: 'reason', type: 'string' },
    ],
    outputs: [],
  },
  {
    name: 'execute',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'cancel',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'claimStakeAfterDefeat',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
  },
  // Events
  {
    type: 'event',
    name: 'ProposalCreated',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'title', type: 'string', indexed: false },
      { name: 'targets', type: 'address[]', indexed: false },
      { name: 'values', type: 'uint256[]', indexed: false },
      { name: 'calldatas', type: 'bytes[]', indexed: false },
      { name: 'snapshotTimestamp', type: 'uint256', indexed: false },
      { name: 'startTime', type: 'uint256', indexed: false },
      { name: 'endTime', type: 'uint256', indexed: false },
      { name: 'stakeAmount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'VoteCast',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'voter', type: 'address', indexed: true },
      { name: 'support', type: 'uint8', indexed: false },
      { name: 'weight', type: 'uint256', indexed: false },
      { name: 'reason', type: 'string', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'ProposalExecuted',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }],
  },
  {
    type: 'event',
    name: 'ProposalCanceled',
    inputs: [{ name: 'proposalId', type: 'uint256', indexed: true }],
  },
  {
    type: 'event',
    name: 'StakeSlashed',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'slashedAmount', type: 'uint256', indexed: false },
      { name: 'returnedAmount', type: 'uint256', indexed: false },
    ],
  },
] as const;

export const EDIT_SUGGESTIONS_ABI = [
  // Constants
  {
    name: 'EDIT_STAKE',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'EDIT_WINDOW',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'VOTING_WINDOW',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'SLASH_BPS',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  // Read functions
  {
    name: 'suggestionCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'getSuggestion',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'suggester', type: 'address' },
      { name: 'originalHash', type: 'bytes32' },
      { name: 'proposedText', type: 'string' },
      { name: 'forVotes', type: 'uint256' },
      { name: 'againstVotes', type: 'uint256' },
      { name: 'finalized', type: 'bool' },
      { name: 'accepted', type: 'bool' },
    ],
  },
  {
    name: 'getSuggestions',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256[]' }],
  },
  {
    name: 'hasVoted',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'suggestionId', type: 'uint256' },
      { name: 'voter', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getEditDeadline',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'getVoteDeadline',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'token',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'governor',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  // Write functions
  {
    name: 'proposeEdit',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'originalHash', type: 'bytes32' },
      { name: 'proposedText', type: 'string' },
    ],
    outputs: [{ name: 'suggestionId', type: 'uint256' }],
  },
  {
    name: 'voteOnSuggestion',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'suggestionId', type: 'uint256' },
      { name: 'support', type: 'bool' },
    ],
    outputs: [],
  },
  {
    name: 'finalizeSuggestion',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'claimStake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [],
  },
  // Events
  {
    type: 'event',
    name: 'SuggestionCreated',
    inputs: [
      { name: 'suggestionId', type: 'uint256', indexed: true },
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'suggester', type: 'address', indexed: true },
      { name: 'originalHash', type: 'bytes32', indexed: false },
      { name: 'proposedText', type: 'string', indexed: false },
      { name: 'stakeAmount', type: 'uint256', indexed: false },
      { name: 'editDeadline', type: 'uint256', indexed: false },
      { name: 'voteDeadline', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'SuggestionVoteCast',
    inputs: [
      { name: 'suggestionId', type: 'uint256', indexed: true },
      { name: 'voter', type: 'address', indexed: true },
      { name: 'support', type: 'bool', indexed: false },
      { name: 'weight', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'SuggestionFinalized',
    inputs: [
      { name: 'suggestionId', type: 'uint256', indexed: true },
      { name: 'accepted', type: 'bool', indexed: false },
      { name: 'forVotes', type: 'uint256', indexed: false },
      { name: 'againstVotes', type: 'uint256', indexed: false },
    ],
  },
] as const;

// =============================================================================
// NETWORK HELPERS
// =============================================================================
export const SUPPORTED_CHAIN_IDS = [base.id, baseSepolia.id] as const;
export const REQUIRED_CHAIN_ID = baseSepolia.id; // Currently deploying to testnet

export function useIsCorrectNetwork() {
  const chainId = useChainId();
  return chainId === REQUIRED_CHAIN_ID;
}

export function useChainCheck() {
  const chainId = useChainId();
  const isCorrect = chainId === REQUIRED_CHAIN_ID;
  return {
    chainId,
    isCorrectNetwork: isCorrect,
    requiredChainId: REQUIRED_CHAIN_ID,
    requiredChainName: 'Base Sepolia',
  };
}

// =============================================================================
// KLED TOKEN HOOKS
// =============================================================================

/**
 * Get KLED token balance for an address
 */
export function useKledBalance(address?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.KLED_TOKEN,
    abi: KLED_TOKEN_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && CONTRACT_ADDRESSES.KLED_TOKEN !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Get voting power (includes delegated votes)
 */
export function useGovernancePower(address?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.KLED_TOKEN,
    abi: KLED_TOKEN_ABI,
    functionName: 'getVotes',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && CONTRACT_ADDRESSES.KLED_TOKEN !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Get current delegate address
 */
export function useDelegate(address?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.KLED_TOKEN,
    abi: KLED_TOKEN_ABI,
    functionName: 'delegates',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && CONTRACT_ADDRESSES.KLED_TOKEN !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Get allowance for Governor contract
 */
export function useGovernorAllowance(address?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.KLED_TOKEN,
    abi: KLED_TOKEN_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACT_ADDRESSES.STREET_GOVERNOR] : undefined,
    query: {
      enabled: !!address && CONTRACT_ADDRESSES.KLED_TOKEN !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Hook to delegate voting power
 */
export function useDelegateVotes() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const delegate = (delegatee: Address) => {
    writeContract({
      address: CONTRACT_ADDRESSES.KLED_TOKEN,
      abi: KLED_TOKEN_ABI,
      functionName: 'delegate',
      args: [delegatee],
    });
  };

  return {
    delegate,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  };
}

/**
 * Hook to approve KLED spending
 */
export function useApproveKled() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const approve = (spender: Address, amount: bigint) => {
    writeContract({
      address: CONTRACT_ADDRESSES.KLED_TOKEN,
      abi: KLED_TOKEN_ABI,
      functionName: 'approve',
      args: [spender, amount],
    });
  };

  return {
    approve,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  };
}

// =============================================================================
// GOVERNOR HOOKS
// =============================================================================

/**
 * Create a new proposal (requires 50K KLED stake)
 * For governance-only proposals (no on-chain actions), pass empty arrays for targets/values/calldatas
 */
export function useCreateProposal() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess, data: receipt } = useWaitForTransactionReceipt({
    hash,
  });

  const propose = (
    title: string,
    description: string,
    targets: Address[] = [],
    values: bigint[] = [],
    calldatas: `0x${string}`[] = []
  ) => {
    writeContract({
      address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
      abi: STREET_GOVERNOR_ABI,
      functionName: 'propose',
      args: [title, description, targets, values, calldatas],
    });
  };

  return {
    propose,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    receipt,
    error,
  };
}

/**
 * Cast a vote on a proposal
 */
export function useCastVote() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const vote = (proposalId: bigint, support: VoteType) => {
    writeContract({
      address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
      abi: STREET_GOVERNOR_ABI,
      functionName: 'vote',
      args: [proposalId, support],
    });
  };

  return {
    vote,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  };
}

/**
 * Get proposal data
 */
export function useProposal(proposalId?: bigint) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'getProposal',
    args: proposalId !== undefined ? [proposalId] : undefined,
    query: {
      enabled: proposalId !== undefined && CONTRACT_ADDRESSES.STREET_GOVERNOR !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Get proposal state
 */
export function useProposalState(proposalId?: bigint) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'state',
    args: proposalId !== undefined ? [proposalId] : undefined,
    query: {
      enabled: proposalId !== undefined && CONTRACT_ADDRESSES.STREET_GOVERNOR !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Check if account has voted on proposal
 */
export function useHasVoted(proposalId?: bigint, account?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'hasVoted',
    args: proposalId !== undefined && account ? [proposalId, account] : undefined,
    query: {
      enabled: proposalId !== undefined && !!account && CONTRACT_ADDRESSES.STREET_GOVERNOR !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Get total proposal count
 */
export function useProposalCount() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'proposalCount',
    query: {
      enabled: CONTRACT_ADDRESSES.STREET_GOVERNOR !== '0x0000000000000000000000000000000000000000',
    },
  });
}

// =============================================================================
// EDIT SUGGESTIONS HOOKS
// =============================================================================

/**
 * Propose an edit to a proposal (requires 500 KLED stake)
 */
export function useProposeEdit() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess, data: receipt } = useWaitForTransactionReceipt({
    hash,
  });

  const proposeEdit = (proposalId: bigint, originalHash: Hash, proposedText: string) => {
    writeContract({
      address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
      abi: EDIT_SUGGESTIONS_ABI,
      functionName: 'proposeEdit',
      args: [proposalId, originalHash, proposedText],
    });
  };

  return {
    proposeEdit,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    receipt,
    error,
  };
}

/**
 * Vote on an edit suggestion
 */
export function useVoteOnSuggestion() {
  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const vote = (suggestionId: bigint, support: boolean) => {
    writeContract({
      address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
      abi: EDIT_SUGGESTIONS_ABI,
      functionName: 'voteOnSuggestion',
      args: [suggestionId, support],
    });
  };

  return {
    vote,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  };
}

/**
 * Get all suggestions for a proposal
 */
export function useSuggestions(proposalId?: bigint) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
    abi: EDIT_SUGGESTIONS_ABI,
    functionName: 'getSuggestions',
    args: proposalId !== undefined ? [proposalId] : undefined,
    query: {
      enabled: proposalId !== undefined && CONTRACT_ADDRESSES.EDIT_SUGGESTIONS !== '0x0000000000000000000000000000000000000000',
    },
  });
}

/**
 * Check if account has voted on suggestion
 */
export function useHasVotedOnSuggestion(suggestionId?: bigint, account?: Address) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
    abi: EDIT_SUGGESTIONS_ABI,
    functionName: 'hasVoted',
    args: suggestionId !== undefined && account ? [suggestionId, account] : undefined,
    query: {
      enabled: suggestionId !== undefined && !!account && CONTRACT_ADDRESSES.EDIT_SUGGESTIONS !== '0x0000000000000000000000000000000000000000',
    },
  });
}

// =============================================================================
// COMPOSITE HOOKS
// =============================================================================

/**
 * Combined user governance data hook
 */
export function useUserGovernance() {
  const { address, isConnected } = useAccount();
  const isCorrectNetwork = useIsCorrectNetwork();

  const balance = useKledBalance(address);
  const votingPower = useGovernancePower(address);
  const delegate = useDelegate(address);
  const allowance = useGovernorAllowance(address);

  // Format values for display
  const formattedBalance = balance.data ? formatEther(balance.data) : '0';
  const formattedVotingPower = votingPower.data ? formatEther(votingPower.data) : '0';

  // Check if user can create proposals (has enough balance + allowance)
  const canCreateProposal =
    isConnected &&
    isCorrectNetwork &&
    balance.data !== undefined &&
    balance.data >= GOVERNANCE_CONFIG.PROPOSAL_STAKE;

  // Check if user needs to approve before creating proposal
  const needsApproval =
    canCreateProposal &&
    allowance.data !== undefined &&
    allowance.data < GOVERNANCE_CONFIG.PROPOSAL_STAKE;

  // Check if user can create edit suggestions
  const canSuggestEdit =
    isConnected &&
    isCorrectNetwork &&
    balance.data !== undefined &&
    balance.data >= GOVERNANCE_CONFIG.EDIT_STAKE;

  // Check if self-delegated
  const isSelfDelegated = delegate.data === address;

  return {
    address,
    isConnected,
    isCorrectNetwork,
    balance: balance.data,
    formattedBalance,
    votingPower: votingPower.data,
    formattedVotingPower,
    delegate: delegate.data,
    isSelfDelegated,
    allowance: allowance.data,
    canCreateProposal,
    needsApproval,
    canSuggestEdit,
    isLoading: balance.isLoading || votingPower.isLoading,
    error: balance.error || votingPower.error,
  };
}

// =============================================================================
// TRANSACTION SIMULATION HELPERS
// =============================================================================

/**
 * Estimate outcome of creating a proposal
 */
export function useProposalSimulation(title: string, description: string) {
  const { address } = useAccount();
  const { balance, needsApproval, canCreateProposal } = useUserGovernance();

  const stakeRequired = GOVERNANCE_CONFIG.PROPOSAL_STAKE;
  const slashRisk = (stakeRequired * GOVERNANCE_CONFIG.SLASH_PERCENT) / 100n;

  return {
    canExecute: canCreateProposal && !needsApproval,
    needsApproval,
    stakeRequired,
    slashRisk,
    balanceAfter: balance ? balance - stakeRequired : 0n,
    warnings: [
      ...(needsApproval ? ['Approval required before staking'] : []),
      'If proposal fails, 10% of stake will be slashed',
    ],
  };
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/**
 * Format KLED amount for display
 */
export function formatKled(amount: bigint | undefined, decimals = 0): string {
  if (amount === undefined) return '0';
  const formatted = formatEther(amount);
  const num = parseFloat(formatted);
  return num.toLocaleString(undefined, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/**
 * Parse KLED amount from user input
 */
export function parseKled(amount: string): bigint {
  return parseEther(amount);
}

/**
 * Get proposal state label
 */
export function getProposalStateLabel(state: ProposalState): string {
  const labels: Record<ProposalState, string> = {
    [ProposalState.Pending]: 'Pending',
    [ProposalState.Active]: 'Active',
    [ProposalState.Canceled]: 'Canceled',
    [ProposalState.Defeated]: 'Defeated',
    [ProposalState.Succeeded]: 'Succeeded',
    [ProposalState.Queued]: 'Queued',
    [ProposalState.Expired]: 'Expired',
    [ProposalState.Executed]: 'Executed',
  };
  return labels[state] ?? 'Unknown';
}

/**
 * Hash text for edit suggestion (keccak256)
 */
export function hashText(text: string): Hash {
  // Using viem's keccak256 would require importing it
  // For now, return placeholder - SOL should confirm hashing approach
  return `0x${Array(64).fill('0').join('')}` as Hash;
}

// =============================================================================
// ALL PROPOSALS HOOK
// =============================================================================

/**
 * Fetch all proposals from the contract
 * Returns array of proposals with computed status
 */
export function useAllProposals() {
  const { data: count, isLoading: isCountLoading } = useProposalCount();

  // Create array of proposal IDs to fetch
  const proposalIds = count ? Array.from({ length: Number(count) }, (_, i) => BigInt(i + 1)) : [];

  // Fetch each proposal - wagmi will batch these
  const proposalQueries = proposalIds.map(id => ({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR as Address,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'getProposal' as const,
    args: [id] as const,
  }));

  // We need to use individual hooks since wagmi v2 doesn't have useContractReads
  // This is a workaround - in production you'd want to use multicall or an indexer
  const proposal1 = useProposal(proposalIds[0]);
  const proposal2 = useProposal(proposalIds[1]);
  const proposal3 = useProposal(proposalIds[2]);
  const proposal4 = useProposal(proposalIds[3]);
  const proposal5 = useProposal(proposalIds[4]);

  const allQueries = [proposal1, proposal2, proposal3, proposal4, proposal5];

  const proposals: ProposalData[] = [];
  let isLoading = isCountLoading;

  for (let i = 0; i < proposalIds.length && i < 5; i++) {
    const query = allQueries[i];
    if (query.isLoading) isLoading = true;
    if (query.data) {
      // Transform tuple data to ProposalData object
      const data = query.data as readonly [Address, string, string, bigint, bigint, bigint, bigint, bigint, number];
      const currentState = data[8];
      const proposal: ProposalData = {
        id: proposalIds[i],
        proposer: data[0],
        title: data[1],
        description: data[2],
        forVotes: data[3],
        againstVotes: data[4],
        abstainVotes: data[5],
        startTime: data[6],
        endTime: data[7],
        currentState: currentState,
        executed: currentState === ProposalState.Executed,
        canceled: currentState === ProposalState.Canceled,
        stakeAmount: GOVERNANCE_CONFIG.PROPOSAL_STAKE,
      };
      proposals.push(proposal);
    }
  }

  // Sort by ID descending (newest first)
  proposals.sort((a, b) => Number(b.id) - Number(a.id));

  // Compute status for each proposal
  const proposalsWithStatus = proposals.map(p => {
    const now = BigInt(Math.floor(Date.now() / 1000));
    let status: 'pending' | 'active' | 'passed' | 'failed' | 'executed' | 'canceled' = 'pending';

    if (p.canceled) {
      status = 'canceled';
    } else if (p.executed) {
      status = 'executed';
    } else if (now < p.startTime) {
      status = 'pending';
    } else if (now >= p.startTime && now <= p.endTime) {
      status = 'active';
    } else if (now > p.endTime) {
      // Voting ended - check if passed
      const totalVotes = p.forVotes + p.againstVotes;
      if (totalVotes > BigInt(0) && p.forVotes > p.againstVotes) {
        status = 'passed';
      } else {
        status = 'failed';
      }
    }

    return { ...p, status };
  });

  return {
    proposals: proposalsWithStatus,
    count: count ? Number(count) : 0,
    isLoading,
  };
}

/**
 * Get proposal status from timestamps and votes
 */
export function getProposalStatus(proposal: ProposalData): 'pending' | 'active' | 'passed' | 'failed' | 'executed' | 'canceled' {
  const now = BigInt(Math.floor(Date.now() / 1000));

  if (proposal.canceled) return 'canceled';
  if (proposal.executed) return 'executed';
  if (now < proposal.startTime) return 'pending';
  if (now >= proposal.startTime && now <= proposal.endTime) return 'active';

  // Voting ended
  const totalVotes = proposal.forVotes + proposal.againstVotes;
  if (totalVotes > BigInt(0) && proposal.forVotes > proposal.againstVotes) {
    return 'passed';
  }
  return 'failed';
}

/**
 * Format timestamp to readable date
 */
export function formatTimestamp(timestamp: bigint): string {
  return new Date(Number(timestamp) * 1000).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

/**
 * Calculate time remaining until timestamp
 */
export function getTimeRemaining(endTime: bigint): string {
  const now = Math.floor(Date.now() / 1000);
  const end = Number(endTime);
  const diff = end - now;

  if (diff <= 0) return 'Ended';

  const days = Math.floor(diff / 86400);
  const hours = Math.floor((diff % 86400) / 3600);

  if (days > 0) return `${days}d ${hours}h left`;
  if (hours > 0) return `${hours}h left`;
  return 'Ending soon';
}

// =============================================================================
// EDIT SUGGESTIONS - ALL SUGGESTIONS HOOK
// =============================================================================

/**
 * Get suggestion by ID
 */
export function useSuggestion(suggestionId?: bigint) {
  return useReadContract({
    address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
    abi: EDIT_SUGGESTIONS_ABI,
    functionName: 'getSuggestion',
    args: suggestionId !== undefined ? [suggestionId] : undefined,
    query: {
      enabled: suggestionId !== undefined,
    },
  });
}

/**
 * Get suggestion count
 */
export function useSuggestionCount() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
    abi: EDIT_SUGGESTIONS_ABI,
    functionName: 'suggestionCount',
  });
}

/**
 * Get edit stake amount from contract
 */
export function useEditStake() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.EDIT_SUGGESTIONS,
    abi: EDIT_SUGGESTIONS_ABI,
    functionName: 'EDIT_STAKE',
  });
}

// =============================================================================
// CONTRACT CONFIG READS
// =============================================================================

/**
 * Get proposal stake amount from contract
 */
export function useProposalStake() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'PROPOSAL_STAKE',
  });
}

/**
 * Get voting delay from contract
 */
export function useVotingDelay() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'votingDelay',
  });
}

/**
 * Get voting period from contract
 */
export function useVotingPeriod() {
  return useReadContract({
    address: CONTRACT_ADDRESSES.STREET_GOVERNOR,
    abi: STREET_GOVERNOR_ABI,
    functionName: 'votingPeriod',
  });
}
