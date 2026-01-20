'use client';

import { useReadContract, useWriteContract, useWaitForTransactionReceipt, useAccount } from 'wagmi';
import { formatEther, parseEther } from 'viem';
import { getContracts, FUTARCHY_TREASURY_ABI, FUTARCHY_AMM_ABI, KLED_TOKEN_ABI } from '@/app/config/contracts';

const contracts = getContracts();
const REQUIRED_CHAIN_ID = contracts.chainId;

// =============================================================================
// TYPES
// =============================================================================

export interface FutarchyProposal {
  id: bigint;
  proposer: `0x${string}`;
  title: string;
  description: string;
  amount: bigint;
  recipient: `0x${string}`;
  spendToken: `0x${string}`;
  conditionId: `0x${string}`;
  marketId: `0x${string}`;
  stakeAmount: bigint;
  marketEndTime: bigint;
  passPrice: bigint;
  failPrice: bigint;
  resolved: boolean;
  passed: boolean;
  executed: boolean;
  canceled: boolean;
}

export interface MarketInfo {
  conditionId: `0x${string}`;
  collateralToken: `0x${string}`;
  funding: bigint;
  yesTokens: bigint;
  noTokens: bigint;
  endTime: bigint;
  fee: bigint;
  resolved: boolean;
  winningOutcome: bigint;
}

// =============================================================================
// READ HOOKS
// =============================================================================

/**
 * Get the total count of futarchy proposals
 */
export function useFutarchyProposalCount() {
  return useReadContract({
    address: contracts.futarchyTreasury,
    abi: FUTARCHY_TREASURY_ABI,
    functionName: 'proposalCount',
    chainId: REQUIRED_CHAIN_ID,
  });
}

/**
 * Get a specific futarchy proposal by ID
 */
export function useFutarchyProposal(proposalId: bigint | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: contracts.futarchyTreasury,
    abi: FUTARCHY_TREASURY_ABI,
    functionName: 'getProposal',
    args: proposalId !== undefined ? [proposalId] : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: proposalId !== undefined,
    },
  });

  // Parse the tuple response into a typed object
  const proposal: FutarchyProposal | undefined = data ? {
    id: (data as any)[0],
    proposer: (data as any)[1],
    title: (data as any)[2],
    description: (data as any)[3],
    amount: (data as any)[4],
    recipient: (data as any)[5],
    spendToken: (data as any)[6],
    conditionId: (data as any)[7],
    marketId: (data as any)[8],
    stakeAmount: (data as any)[9],
    marketEndTime: (data as any)[10],
    passPrice: (data as any)[11],
    failPrice: (data as any)[12],
    resolved: (data as any)[13],
    passed: (data as any)[14],
    executed: (data as any)[15],
    canceled: (data as any)[16],
  } : undefined;

  return { proposal, isLoading, error, refetch };
}

/**
 * Get treasury balance for a specific token
 */
export function useTreasuryBalance(tokenAddress: `0x${string}` | undefined) {
  return useReadContract({
    address: contracts.futarchyTreasury,
    abi: FUTARCHY_TREASURY_ABI,
    functionName: 'getTreasuryBalance',
    args: tokenAddress ? [tokenAddress] : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: !!tokenAddress,
    },
  });
}

/**
 * Get the required stake amount for creating a proposal
 */
export function useFutarchyProposalStake() {
  return useReadContract({
    address: contracts.futarchyTreasury,
    abi: FUTARCHY_TREASURY_ABI,
    functionName: 'proposalStake',
    chainId: REQUIRED_CHAIN_ID,
  });
}

/**
 * Get the market duration for futarchy proposals
 */
export function useFutarchyMarketDuration() {
  return useReadContract({
    address: contracts.futarchyTreasury,
    abi: FUTARCHY_TREASURY_ABI,
    functionName: 'marketDuration',
    chainId: REQUIRED_CHAIN_ID,
  });
}

/**
 * Get current price for a market outcome
 */
export function useMarketPrice(marketId: `0x${string}` | undefined, outcomeIndex: number) {
  return useReadContract({
    address: contracts.futarchyAMM,
    abi: FUTARCHY_AMM_ABI,
    functionName: 'getPrice',
    args: marketId ? [marketId, BigInt(outcomeIndex)] : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: !!marketId,
    },
  });
}

/**
 * Get market info from the AMM
 */
export function useMarketInfo(marketId: `0x${string}` | undefined) {
  const { data, isLoading, error } = useReadContract({
    address: contracts.futarchyAMM,
    abi: FUTARCHY_AMM_ABI,
    functionName: 'getMarketInfo',
    args: marketId ? [marketId] : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: !!marketId,
    },
  });

  const marketInfo: MarketInfo | undefined = data ? {
    conditionId: (data as any)[0],
    collateralToken: (data as any)[1],
    funding: (data as any)[2],
    yesTokens: (data as any)[3],
    noTokens: (data as any)[4],
    endTime: (data as any)[5],
    fee: (data as any)[6],
    resolved: (data as any)[7],
    winningOutcome: (data as any)[8],
  } : undefined;

  return { marketInfo, isLoading, error };
}

/**
 * Calculate buy amount for a trade
 */
export function useCalcBuyAmount(
  marketId: `0x${string}` | undefined,
  outcomeIndex: number,
  investmentAmount: bigint | undefined
) {
  return useReadContract({
    address: contracts.futarchyAMM,
    abi: FUTARCHY_AMM_ABI,
    functionName: 'calcBuyAmount',
    args: marketId && investmentAmount !== undefined
      ? [marketId, BigInt(outcomeIndex), investmentAmount]
      : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: !!marketId && investmentAmount !== undefined,
    },
  });
}

/**
 * Calculate sell return for a trade
 */
export function useCalcSellReturn(
  marketId: `0x${string}` | undefined,
  outcomeIndex: number,
  outcomeTokenAmount: bigint | undefined
) {
  return useReadContract({
    address: contracts.futarchyAMM,
    abi: FUTARCHY_AMM_ABI,
    functionName: 'calcSellReturn',
    args: marketId && outcomeTokenAmount !== undefined
      ? [marketId, BigInt(outcomeIndex), outcomeTokenAmount]
      : undefined,
    chainId: REQUIRED_CHAIN_ID,
    query: {
      enabled: !!marketId && outcomeTokenAmount !== undefined,
    },
  });
}

// =============================================================================
// AGGREGATED HOOKS
// =============================================================================

/**
 * Fetch all futarchy proposals
 */
export function useAllFutarchyProposals() {
  const { data: count, isLoading: isCountLoading } = useFutarchyProposalCount();

  // Create array of proposal IDs to fetch
  const proposalIds = count ? Array.from({ length: Number(count) }, (_, i) => BigInt(i + 1)) : [];

  // Fetch up to 10 proposals individually (wagmi v2 doesn't have useContractReads in the same way)
  const proposal1 = useFutarchyProposal(proposalIds[0]);
  const proposal2 = useFutarchyProposal(proposalIds[1]);
  const proposal3 = useFutarchyProposal(proposalIds[2]);
  const proposal4 = useFutarchyProposal(proposalIds[3]);
  const proposal5 = useFutarchyProposal(proposalIds[4]);
  const proposal6 = useFutarchyProposal(proposalIds[5]);
  const proposal7 = useFutarchyProposal(proposalIds[6]);
  const proposal8 = useFutarchyProposal(proposalIds[7]);
  const proposal9 = useFutarchyProposal(proposalIds[8]);
  const proposal10 = useFutarchyProposal(proposalIds[9]);

  const allProposals = [
    proposal1, proposal2, proposal3, proposal4, proposal5,
    proposal6, proposal7, proposal8, proposal9, proposal10,
  ];

  const proposals = allProposals
    .slice(0, proposalIds.length)
    .map(p => p.proposal)
    .filter((p): p is FutarchyProposal => p !== undefined);

  const isLoading = isCountLoading || allProposals.slice(0, proposalIds.length).some(p => p.isLoading);

  // Add computed status to each proposal
  const proposalsWithStatus = proposals.map(proposal => {
    let status: 'active' | 'passed' | 'failed' | 'executed' | 'canceled' = 'active';
    const now = BigInt(Math.floor(Date.now() / 1000));

    if (proposal.canceled) {
      status = 'canceled';
    } else if (proposal.executed) {
      status = 'executed';
    } else if (proposal.resolved) {
      status = proposal.passed ? 'passed' : 'failed';
    } else if (proposal.marketEndTime > 0n && now > proposal.marketEndTime) {
      // Market ended but not yet resolved
      status = 'active';
    }

    return {
      ...proposal,
      status,
      formattedAmount: formatEther(proposal.amount),
      formattedStake: formatEther(proposal.stakeAmount),
      timeRemaining: proposal.marketEndTime > now
        ? Number(proposal.marketEndTime - now)
        : 0,
    };
  });

  return {
    proposals: proposalsWithStatus,
    count: count ? Number(count) : 0,
    isLoading,
  };
}

// =============================================================================
// WRITE HOOKS
// =============================================================================

/**
 * Approve KLED tokens for FutarchyTreasury contract
 */
export function useApproveFutarchyStake() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const approve = (amount: bigint) => {
    writeContract({
      address: contracts.kledToken,
      abi: KLED_TOKEN_ABI,
      functionName: 'approve',
      args: [contracts.futarchyTreasury, amount],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    approve,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Create a new futarchy treasury proposal
 */
export function useCreateFutarchyProposal() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const createProposal = (
    title: string,
    description: string,
    amount: bigint,
    recipient: `0x${string}`,
    spendToken: `0x${string}`
  ) => {
    writeContract({
      address: contracts.futarchyTreasury,
      abi: FUTARCHY_TREASURY_ABI,
      functionName: 'createProposal',
      args: [title, description, amount, recipient, spendToken],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    createProposal,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Resolve a futarchy proposal (after market ends)
 */
export function useResolveFutarchyProposal() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const resolveProposal = (proposalId: bigint) => {
    writeContract({
      address: contracts.futarchyTreasury,
      abi: FUTARCHY_TREASURY_ABI,
      functionName: 'resolveProposal',
      args: [proposalId],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    resolveProposal,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Execute a passed futarchy proposal
 */
export function useExecuteFutarchyProposal() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const executeProposal = (proposalId: bigint) => {
    writeContract({
      address: contracts.futarchyTreasury,
      abi: FUTARCHY_TREASURY_ABI,
      functionName: 'executeProposal',
      args: [proposalId],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    executeProposal,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Cancel a futarchy proposal (proposer only)
 */
export function useCancelFutarchyProposal() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const cancelProposal = (proposalId: bigint) => {
    writeContract({
      address: contracts.futarchyTreasury,
      abi: FUTARCHY_TREASURY_ABI,
      functionName: 'cancelProposal',
      args: [proposalId],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    cancelProposal,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Deposit tokens to treasury
 */
export function useDepositToTreasury() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const deposit = (tokenAddress: `0x${string}`, amount: bigint) => {
    writeContract({
      address: contracts.futarchyTreasury,
      abi: FUTARCHY_TREASURY_ABI,
      functionName: 'deposit',
      args: [tokenAddress, amount],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    deposit,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Buy outcome tokens in a market
 */
export function useBuyOutcome() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const buy = (
    marketId: `0x${string}`,
    outcomeIndex: number,
    investmentAmount: bigint,
    minOutcomeTokens: bigint
  ) => {
    writeContract({
      address: contracts.futarchyAMM,
      abi: FUTARCHY_AMM_ABI,
      functionName: 'buy',
      args: [marketId, BigInt(outcomeIndex), investmentAmount, minOutcomeTokens],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    buy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

/**
 * Sell outcome tokens in a market
 */
export function useSellOutcome() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const sell = (
    marketId: `0x${string}`,
    outcomeIndex: number,
    outcomeTokenAmount: bigint,
    minReturnAmount: bigint
  ) => {
    writeContract({
      address: contracts.futarchyAMM,
      abi: FUTARCHY_AMM_ABI,
      functionName: 'sell',
      args: [marketId, BigInt(outcomeIndex), outcomeTokenAmount, minReturnAmount],
      chainId: REQUIRED_CHAIN_ID,
    });
  };

  return {
    sell,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  };
}

// =============================================================================
// UTILITY HOOKS
// =============================================================================

/**
 * Combined user governance data for futarchy
 */
export function useUserFutarchyData() {
  const { address, isConnected } = useAccount();
  const { data: proposalStake } = useFutarchyProposalStake();
  const { data: marketDuration } = useFutarchyMarketDuration();
  const { data: kledTreasuryBalance } = useTreasuryBalance(contracts.kledToken);

  return {
    isConnected,
    address,
    proposalStake: proposalStake ? formatEther(proposalStake as bigint) : '0',
    marketDuration: marketDuration ? Number(marketDuration) : 0,
    kledTreasuryBalance: kledTreasuryBalance ? formatEther(kledTreasuryBalance as bigint) : '0',
  };
}

/**
 * Helper to format time remaining
 */
export function formatTimeRemaining(seconds: number): string {
  if (seconds <= 0) return 'Ended';

  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

/**
 * Format price as percentage
 */
export function formatPriceAsPercent(price: bigint): string {
  // Assuming price is in 18 decimals representing 0-1 range
  const percent = Number(price) / 1e16; // Convert to percentage
  return `${percent.toFixed(1)}%`;
}
