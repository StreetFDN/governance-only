/**
 * Contract ABIs for Street Governance
 * Minimal ABIs for frontend integration (wagmi compatible)
 * Generated from contract interfaces
 */

// ============ KLEDToken ABI ============
export const kledTokenAbi = [
  // Read functions
  {
    type: 'function',
    name: 'balanceOf',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getVotes',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'delegates',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'allowance',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'totalSupply',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getPastVotes',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'timepoint', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'delegate',
    inputs: [{ name: 'delegatee', type: 'address' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'approve',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'transfer',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'nonpayable',
  },
  // Events
  {
    type: 'event',
    name: 'Transfer',
    inputs: [
      { name: 'from', type: 'address', indexed: true },
      { name: 'to', type: 'address', indexed: true },
      { name: 'value', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Approval',
    inputs: [
      { name: 'owner', type: 'address', indexed: true },
      { name: 'spender', type: 'address', indexed: true },
      { name: 'value', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'DelegateChanged',
    inputs: [
      { name: 'delegator', type: 'address', indexed: true },
      { name: 'fromDelegate', type: 'address', indexed: true },
      { name: 'toDelegate', type: 'address', indexed: true },
    ],
  },
  {
    type: 'event',
    name: 'DelegateVotesChanged',
    inputs: [
      { name: 'delegate', type: 'address', indexed: true },
      { name: 'previousVotes', type: 'uint256', indexed: false },
      { name: 'newVotes', type: 'uint256', indexed: false },
    ],
  },
] as const;

// ============ StreetGovernor ABI ============
export const streetGovernorAbi = [
  // Constants
  {
    type: 'function',
    name: 'PROPOSAL_STAKE',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'SLASH_BPS',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Read functions
  {
    type: 'function',
    name: 'proposalCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'state',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint8' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'hasVoted',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'voter', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getProposal',
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
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getProposalActions',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [
      { name: 'targets', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
      { name: 'calldatas', type: 'bytes[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'quorum',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'votingDelay',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'votingPeriod',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'quorumBps',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'thresholdBps',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'token',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'propose',
    inputs: [
      { name: 'title', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'targets', type: 'address[]' },
      { name: 'values', type: 'uint256[]' },
      { name: 'calldatas', type: 'bytes[]' },
    ],
    outputs: [{ name: 'proposalId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'vote',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'support', type: 'uint8' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'voteWithReason',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'support', type: 'uint8' },
      { name: 'reason', type: 'string' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'execute',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'cancel',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'claimStakeAfterDefeat',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
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
    name: 'StakeClaimed',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
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

// ============ EditSuggestions ABI ============
export const editSuggestionsAbi = [
  // Constants
  {
    type: 'function',
    name: 'EDIT_STAKE',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'EDIT_WINDOW',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'VOTING_WINDOW',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'SLASH_BPS',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Read functions
  {
    type: 'function',
    name: 'suggestionCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getSuggestion',
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
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getSuggestions',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'hasVoted',
    inputs: [
      { name: 'suggestionId', type: 'uint256' },
      { name: 'voter', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getEditDeadline',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getVoteDeadline',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'token',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'governor',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'proposeEdit',
    inputs: [
      { name: 'proposalId', type: 'uint256' },
      { name: 'originalHash', type: 'bytes32' },
      { name: 'proposedText', type: 'string' },
    ],
    outputs: [{ name: 'suggestionId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'voteOnSuggestion',
    inputs: [
      { name: 'suggestionId', type: 'uint256' },
      { name: 'support', type: 'bool' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'finalizeSuggestion',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'claimStake',
    inputs: [{ name: 'suggestionId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
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
  {
    type: 'event',
    name: 'SuggestionStakeClaimed',
    inputs: [
      { name: 'suggestionId', type: 'uint256', indexed: true },
      { name: 'suggester', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'slashed', type: 'bool', indexed: false },
    ],
  },
] as const;

// ============ ProposalState Enum ============
export const ProposalState = {
  Pending: 0,
  Active: 1,
  Canceled: 2,
  Defeated: 3,
  Succeeded: 4,
  Executed: 5,
} as const;

// ============ VoteType Enum ============
export const VoteType = {
  Against: 0,
  For: 1,
  Abstain: 2,
} as const;

// ============ FutarchyTreasury ABI ============
export const futarchyTreasuryAbi = [
  // Read functions
  {
    type: 'function',
    name: 'proposalCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'id', type: 'uint256' },
          { name: 'proposer', type: 'address' },
          { name: 'title', type: 'string' },
          { name: 'description', type: 'string' },
          { name: 'amount', type: 'uint256' },
          { name: 'recipient', type: 'address' },
          { name: 'spendToken', type: 'address' },
          { name: 'conditionId', type: 'bytes32' },
          { name: 'marketId', type: 'bytes32' },
          { name: 'stakeAmount', type: 'uint256' },
          { name: 'marketEndTime', type: 'uint256' },
          { name: 'passPrice', type: 'uint256' },
          { name: 'failPrice', type: 'uint256' },
          { name: 'resolved', type: 'bool' },
          { name: 'passed', type: 'bool' },
          { name: 'executed', type: 'bool' },
          { name: 'canceled', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getTreasuryBalance',
    inputs: [{ name: 'token', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'proposalStake',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'marketDuration',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'marketFunding',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'amm',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'conditionalTokens',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'kledToken',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'deposit',
    inputs: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'depositETH',
    inputs: [],
    outputs: [],
    stateMutability: 'payable',
  },
  {
    type: 'function',
    name: 'createProposal',
    inputs: [
      { name: 'title', type: 'string' },
      { name: 'description', type: 'string' },
      { name: 'amount', type: 'uint256' },
      { name: 'recipient', type: 'address' },
      { name: 'spendToken', type: 'address' },
    ],
    outputs: [{ name: 'proposalId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'resolveProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'executeProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'cancelProposal',
    inputs: [{ name: 'proposalId', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  // Events
  {
    type: 'event',
    name: 'TreasuryProposalCreated',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'proposer', type: 'address', indexed: true },
      { name: 'title', type: 'string', indexed: false },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'recipient', type: 'address', indexed: false },
      { name: 'marketId', type: 'bytes32', indexed: false },
      { name: 'marketEndTime', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'TreasuryProposalResolved',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'passed', type: 'bool', indexed: false },
      { name: 'passMarketPrice', type: 'uint256', indexed: false },
      { name: 'failMarketPrice', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'TreasuryProposalExecuted',
    inputs: [
      { name: 'proposalId', type: 'uint256', indexed: true },
      { name: 'recipient', type: 'address', indexed: false },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'TreasuryDeposit',
    inputs: [
      { name: 'depositor', type: 'address', indexed: true },
      { name: 'token', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
] as const;

// ============ FutarchyAMM ABI ============
export const futarchyAmmAbi = [
  // Constants
  {
    type: 'function',
    name: 'SCALE',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'FEE_DENOMINATOR',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Read functions
  {
    type: 'function',
    name: 'marketCount',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getPrice',
    inputs: [
      { name: 'marketId', type: 'bytes32' },
      { name: 'outcomeIndex', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'calcBuyAmount',
    inputs: [
      { name: 'marketId', type: 'bytes32' },
      { name: 'outcomeIndex', type: 'uint256' },
      { name: 'investmentAmount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'calcSellReturn',
    inputs: [
      { name: 'marketId', type: 'bytes32' },
      { name: 'outcomeIndex', type: 'uint256' },
      { name: 'tokenAmount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getMarketInfo',
    inputs: [{ name: 'marketId', type: 'bytes32' }],
    outputs: [
      { name: 'conditionId', type: 'bytes32' },
      { name: 'collateralToken', type: 'address' },
      { name: 'funding', type: 'uint256' },
      { name: 'yesTokens', type: 'uint256' },
      { name: 'noTokens', type: 'uint256' },
      { name: 'endTime', type: 'uint256' },
      { name: 'fee', type: 'uint256' },
      { name: 'resolved', type: 'bool' },
      { name: 'winningOutcome', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'accumulatedFees',
    inputs: [{ name: 'marketId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'buy',
    inputs: [
      { name: 'marketId', type: 'bytes32' },
      { name: 'outcomeIndex', type: 'uint256' },
      { name: 'amount', type: 'uint256' },
      { name: 'minOutcomeTokens', type: 'uint256' },
    ],
    outputs: [{ name: 'outcomeTokensBought', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'sell',
    inputs: [
      { name: 'marketId', type: 'bytes32' },
      { name: 'outcomeIndex', type: 'uint256' },
      { name: 'tokenAmount', type: 'uint256' },
      { name: 'minReturn', type: 'uint256' },
    ],
    outputs: [{ name: 'returnAmount', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  // Events
  {
    type: 'event',
    name: 'MarketCreated',
    inputs: [
      { name: 'marketId', type: 'bytes32', indexed: true },
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'creator', type: 'address', indexed: true },
      { name: 'funding', type: 'uint256', indexed: false },
      { name: 'endTime', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Buy',
    inputs: [
      { name: 'marketId', type: 'bytes32', indexed: true },
      { name: 'buyer', type: 'address', indexed: true },
      { name: 'outcomeIndex', type: 'uint256', indexed: false },
      { name: 'investmentAmount', type: 'uint256', indexed: false },
      { name: 'outcomeTokensBought', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Sell',
    inputs: [
      { name: 'marketId', type: 'bytes32', indexed: true },
      { name: 'seller', type: 'address', indexed: true },
      { name: 'outcomeIndex', type: 'uint256', indexed: false },
      { name: 'returnAmount', type: 'uint256', indexed: false },
      { name: 'outcomeTokensSold', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'MarketResolved',
    inputs: [
      { name: 'marketId', type: 'bytes32', indexed: true },
      { name: 'winningOutcome', type: 'uint256', indexed: false },
      { name: 'yesPrice', type: 'uint256', indexed: false },
      { name: 'noPrice', type: 'uint256', indexed: false },
    ],
  },
] as const;

// ============ ConditionalTokens ABI ============
export const conditionalTokensAbi = [
  // Read functions
  {
    type: 'function',
    name: 'balanceOf',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'id', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getConditionId',
    inputs: [
      { name: 'oracle', type: 'address' },
      { name: 'questionId', type: 'bytes32' },
      { name: 'outcomeSlotCount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bytes32' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'getCollectionId',
    inputs: [
      { name: 'conditionId', type: 'bytes32' },
      { name: 'indexSet', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bytes32' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'getPositionId',
    inputs: [
      { name: 'collateralToken', type: 'address' },
      { name: 'collectionId', type: 'bytes32' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'isConditionResolved',
    inputs: [{ name: 'conditionId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getOutcomeSlotCount',
    inputs: [{ name: 'conditionId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isApprovedForAll',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'operator', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
  // Write functions
  {
    type: 'function',
    name: 'setApprovalForAll',
    inputs: [
      { name: 'operator', type: 'address' },
      { name: 'approved', type: 'bool' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'splitPosition',
    inputs: [
      { name: 'collateralToken', type: 'address' },
      { name: 'conditionId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'mergePositions',
    inputs: [
      { name: 'collateralToken', type: 'address' },
      { name: 'conditionId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'redeemPositions',
    inputs: [
      { name: 'collateralToken', type: 'address' },
      { name: 'conditionId', type: 'bytes32' },
      { name: 'indexSets', type: 'uint256[]' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  // Events
  {
    type: 'event',
    name: 'ConditionPreparation',
    inputs: [
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'oracle', type: 'address', indexed: true },
      { name: 'questionId', type: 'bytes32', indexed: true },
      { name: 'outcomeSlotCount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'ConditionResolution',
    inputs: [
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'oracle', type: 'address', indexed: true },
      { name: 'questionId', type: 'bytes32', indexed: true },
      { name: 'outcomeSlotCount', type: 'uint256', indexed: false },
      { name: 'payoutNumerators', type: 'uint256[]', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'PositionSplit',
    inputs: [
      { name: 'stakeholder', type: 'address', indexed: true },
      { name: 'collateralToken', type: 'address', indexed: true },
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'PositionsMerge',
    inputs: [
      { name: 'stakeholder', type: 'address', indexed: true },
      { name: 'collateralToken', type: 'address', indexed: true },
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'PayoutRedemption',
    inputs: [
      { name: 'redeemer', type: 'address', indexed: true },
      { name: 'collateralToken', type: 'address', indexed: true },
      { name: 'conditionId', type: 'bytes32', indexed: true },
      { name: 'indexSets', type: 'uint256[]', indexed: false },
      { name: 'payout', type: 'uint256', indexed: false },
    ],
  },
] as const;

// ============ Outcome Index Constants ============
export const OutcomeIndex = {
  YES: 0,
  NO: 1,
} as const;

// ============ Type exports for wagmi ============
export type KLEDTokenAbi = typeof kledTokenAbi;
export type StreetGovernorAbi = typeof streetGovernorAbi;
export type EditSuggestionsAbi = typeof editSuggestionsAbi;
export type FutarchyTreasuryAbi = typeof futarchyTreasuryAbi;
export type FutarchyAmmAbi = typeof futarchyAmmAbi;
export type ConditionalTokensAbi = typeof conditionalTokensAbi;
