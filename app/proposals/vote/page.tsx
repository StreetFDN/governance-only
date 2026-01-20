'use client';

import { useState, useEffect, Suspense } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useSwitchChain } from 'wagmi';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { ArrowLeft, Check, ExternalLink, Clock, Info, Twitter, Globe, Loader2, AlertTriangle } from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { formatEther } from 'viem';
import {
  useProposal,
  useProposalCount,
  useCastVote,
  useHasVoted,
  useUserGovernance,
  useChainCheck,
  VoteType,
  REQUIRED_CHAIN_ID,
  formatKled,
} from '@/app/hooks/useGovernance';

// --- THEME OBSERVER HOOK ---
function useThemeObserver() {
  const [theme, setTheme] = useState('light');

  useEffect(() => {
    const getTheme = () => document.documentElement.getAttribute('data-theme') || 'light';
    setTheme(getTheme());

    const observer = new MutationObserver(() => {
      setTheme(getTheme());
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });

    return () => observer.disconnect();
  }, []);

  return theme;
}

function ProposalPageContent() {
  const searchParams = useSearchParams();
  const proposalIdParam = searchParams.get('id');

  const [selectedVote, setSelectedVote] = useState<string | null>(null);
  const { isConnected, address } = useAccount();
  const { switchChain } = useSwitchChain();
  const currentTheme = useThemeObserver();
  const [mounted, setMounted] = useState(false);

  // Get proposal count to default to latest
  const { data: proposalCount } = useProposalCount();

  // Determine proposal ID (from URL or default to latest)
  const proposalId = proposalIdParam
    ? BigInt(proposalIdParam)
    : (proposalCount && proposalCount > 0n ? proposalCount : 1n);

  // Fetch proposal data from contract
  const { data: proposalTuple, isLoading: isProposalLoading, refetch: refetchProposal } = useProposal(proposalId);

  // Transform tuple to object for easier access
  // Tuple format: [proposer, title, description, forVotes, againstVotes, abstainVotes, startTime, endTime, currentState]
  const proposal = proposalTuple ? {
    id: proposalId,
    proposer: proposalTuple[0],
    title: proposalTuple[1],
    description: proposalTuple[2],
    forVotes: proposalTuple[3],
    againstVotes: proposalTuple[4],
    abstainVotes: proposalTuple[5],
    startTime: proposalTuple[6],
    endTime: proposalTuple[7],
    currentState: proposalTuple[8],
    executed: proposalTuple[8] === 7, // ProposalState.Executed
    canceled: proposalTuple[8] === 2, // ProposalState.Canceled
    stakeAmount: 50000n * 10n ** 18n, // 50K KLED
    snapshotTime: proposalTuple[6], // Use startTime as snapshot
  } : null;

  // Check if user has already voted
  const { data: hasVoted, isLoading: isVoteCheckLoading, refetch: refetchHasVoted } = useHasVoted(proposalId, address);

  // User governance data
  const { formattedVotingPower, votingPower, isLoading: isGovernanceLoading } = useUserGovernance();
  const { isCorrectNetwork, requiredChainName } = useChainCheck();

  // Vote hook
  const { vote: castVote, isPending: isVoting, isConfirming, isSuccess: voteSuccess, error: voteError } = useCastVote();

  useEffect(() => {
    setMounted(true);
  }, []);

  // Refetch data after successful vote
  useEffect(() => {
    if (voteSuccess) {
      refetchProposal();
      refetchHasVoted();
      setSelectedVote(null);
    }
  }, [voteSuccess, refetchProposal, refetchHasVoted]);

  // Handle vote submission
  const handleVote = () => {
    if (!selectedVote || !proposalId) return;

    const voteType = selectedVote === 'Yes' ? VoteType.For
      : selectedVote === 'No' ? VoteType.Against
      : VoteType.Abstain;

    castVote(proposalId, voteType);
  };

  // Calculate vote percentages
  const calculateVotes = () => {
    if (!proposal) return { yes: 0, no: 0, abstain: 0, total: 0n };
    const total = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
    if (total === 0n) return { yes: 0, no: 0, abstain: 0, total: 0n };
    return {
      yes: Number((proposal.forVotes * 100n) / total),
      no: Number((proposal.againstVotes * 100n) / total),
      abstain: Number((proposal.abstainVotes * 100n) / total),
      total,
    };
  };

  const votes = calculateVotes();

  // Format dates
  const formatDate = (timestamp: bigint) => {
    return new Date(Number(timestamp) * 1000).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  };

  // Check if voting is still open
  const isVotingOpen = proposal && Number(proposal.endTime) * 1000 > Date.now() && !proposal.executed && !proposal.canceled;

  return (
    <main className="min-h-screen flex flex-col font-sans bg-street-background text-[var(--text-main)] selection:bg-[#FD7DEC] selection:text-black transition-colors duration-300">
      
      {/* --- NAVIGATION --- */}
      <nav className="w-full border-b street-border bg-street-background/90 backdrop-blur-md sticky top-0 z-40">
        <div className="max-w-[1100px] mx-auto px-8 py-4 flex justify-between items-center">
            <div className="flex items-center gap-3">
               {/* DYNAMIC LOGO SWITCHING */}
               <div className="relative h-8 w-32 flex items-center">
                 {currentTheme === 'light' ? (
                    <img 
                        src="/street-logo2.png" 
                        alt="Street" 
                        className="h-8 w-auto object-contain" 
                    />
                 ) : (
                    <img 
                        src="/street-logo.png" 
                        alt="Street" 
                        className="h-8 w-auto object-contain" 
                    />
                 )}
               </div>
            </div>
            
            <div className="flex items-center gap-4">
            <Link href="/">
                <button className="px-4 py-2 rounded-lg border street-border text-street-muted text-xs hover:bg-[var(--surface-highlight)] transition">
                    All Projects
                </button>
            </Link>
            
            <ThemeToggle />

            <ConnectButton.Custom>
                {({ account, chain, openAccountModal, openConnectModal, mounted }) => {
                const ready = mounted;
                const connected = ready && account && chain;
                return (
                    <div {...(!ready && { 'aria-hidden': true, 'style': { opacity: 0, pointerEvents: 'none', userSelect: 'none' } })}>
                    {(() => {
                        if (!connected) {
                        return (
                            <button onClick={openConnectModal} type="button" 
                            className="street-gradient-bg text-black font-medium px-5 py-2 rounded-lg text-xs hover:opacity-90 transition">
                            Log In
                            </button>
                        );
                        }
                        return (
                        <button onClick={openAccountModal} type="button" className="bg-street-surface text-[var(--text-main)] border street-border px-4 py-2 rounded-lg text-xs font-mono">
                            {account.displayName}
                        </button>
                        );
                    })()}
                    </div>
                );
                }}
            </ConnectButton.Custom>
            </div>
        </div>
      </nav>

      {/* --- MAIN CONTENT --- */}
      <div className="max-w-[1100px] mx-auto w-full px-8 py-12 flex-1">
        
        <Link href="/projects/kled" className="inline-flex items-center gap-2 text-street-muted hover:text-[var(--text-main)] transition mb-8 group">
            <ArrowLeft size={16} className="group-hover:-translate-x-1 transition-transform"/>
            <span className="text-xs font-mono uppercase tracking-wider">Back to Dashboard</span>
        </Link>

        {/* Loading State */}
        {isProposalLoading ? (
            <div className="flex items-center justify-center min-h-[400px]">
                <Loader2 className="animate-spin text-street-muted" size={32} />
            </div>
        ) : !proposal ? (
            <div className="flex flex-col items-center justify-center min-h-[400px] text-center">
                <AlertTriangle className="text-street-red mb-4" size={48} />
                <h2 className="text-2xl font-serif text-[var(--text-main)] mb-2">Proposal Not Found</h2>
                <p className="text-street-muted">The proposal you're looking for doesn't exist.</p>
                <Link href="/projects/kled" className="mt-4 text-street-green underline">
                    Back to Dashboard
                </Link>
            </div>
        ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">

            {/* LEFT COLUMN: Proposal Content */}
            <div className="lg:col-span-2 space-y-8">

                <div className="space-y-4">
                    <div className="flex items-center gap-3">
                        {isVotingOpen ? (
                            <>
                                <span className="w-2 h-2 rounded-full bg-street-green animate-pulse"></span>
                                <span className="text-street-green font-bold text-xs tracking-widest uppercase">Live Proposal</span>
                            </>
                        ) : (
                            <>
                                <span className="w-2 h-2 rounded-full bg-street-muted"></span>
                                <span className="text-street-muted font-bold text-xs tracking-widest uppercase">
                                    {proposal.executed ? 'Executed' : proposal.canceled ? 'Canceled' : 'Voting Ended'}
                                </span>
                            </>
                        )}
                        <span className="text-[10px] font-mono text-street-muted ml-auto">#{proposal.id.toString()}</span>
                    </div>
                    <h1 className="text-5xl font-serif text-[var(--text-main)] leading-tight">{proposal.title}</h1>

                    <div className="flex items-center gap-6 text-xs text-street-muted font-mono border-b street-border pb-8 flex-wrap">
                        <div className="flex items-center gap-2">
                            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-blue-400 to-purple-500"></div>
                            <span>by {proposal.proposer.slice(0, 6)}...{proposal.proposer.slice(-4)}</span>
                        </div>
                        <span>•</span>
                        <span className="flex items-center gap-1"><Clock size={12}/> Started {formatDate(proposal.startTime)}</span>
                        <span>•</span>
                        <span className="flex items-center gap-1">Ends {formatDate(proposal.endTime)}</span>
                    </div>
                </div>

                <div className="space-y-8 text-sm text-[var(--text-main)] leading-relaxed font-light">
                    <section>
                        <h3 className="text-xl font-serif text-[var(--text-main)] mb-3">Description</h3>
                        <p className="text-street-muted whitespace-pre-wrap">{proposal.description}</p>
                    </section>

                    <div className="p-4 border street-border rounded-xl bg-street-surface/50 flex gap-3 items-start">
                        <Info className="text-street-muted w-5 h-5 flex-shrink-0 mt-0.5"/>
                        <div className="text-xs text-street-muted space-y-1">
                            <p>Stake Amount: <span className="text-[var(--text-main)]">{formatKled(proposal.stakeAmount)} KLED</span></p>
                            <p>Total Votes: <span className="text-[var(--text-main)]">{formatKled(votes.total)} KLED</span></p>
                        </div>
                    </div>
                </div>

            </div>

            {/* RIGHT COLUMN: Sticky Sidebar */}
            <div className="lg:col-span-1 space-y-6 relative">
                <div className="sticky top-24 space-y-6">

                    {/* CAST VOTE CARD */}
                    <div className="bg-street-surface border street-border rounded-2xl p-6 shadow-sm">
                        <h3 className="text-xl font-serif text-[var(--text-main)] mb-6">Cast your vote</h3>

                        {/* Network Warning */}
                        {isConnected && !isCorrectNetwork && (
                            <div className="mb-4 p-3 bg-street-red/10 border border-street-red/30 rounded-lg">
                                <p className="text-xs text-street-red mb-2">Wrong network detected</p>
                                <button
                                    onClick={() => switchChain?.({ chainId: REQUIRED_CHAIN_ID })}
                                    className="text-xs text-street-red underline"
                                >
                                    Switch to {requiredChainName}
                                </button>
                            </div>
                        )}

                        {/* Already Voted */}
                        {hasVoted && (
                            <div className="mb-4 p-3 bg-street-green/10 border border-street-green/30 rounded-lg flex items-center gap-2">
                                <Check size={16} className="text-street-green" />
                                <p className="text-xs text-street-green">You have already voted on this proposal</p>
                            </div>
                        )}

                        {/* Vote Success Message */}
                        {voteSuccess && (
                            <div className="mb-4 p-3 bg-street-green/10 border border-street-green/30 rounded-lg flex items-center gap-2">
                                <Check size={16} className="text-street-green" />
                                <p className="text-xs text-street-green">Vote submitted successfully!</p>
                            </div>
                        )}

                        {/* Vote Error */}
                        {voteError && (
                            <div className="mb-4 p-3 bg-street-red/10 border border-street-red/30 rounded-lg">
                                <p className="text-xs text-street-red">Vote failed: {voteError.message}</p>
                            </div>
                        )}

                        <div className="space-y-3 mb-8">
                            {['Yes', 'No', 'Abstain'].map((option) => (
                                <button
                                    key={option}
                                    onClick={() => setSelectedVote(option)}
                                    disabled={!isVotingOpen || hasVoted || !isConnected || !isCorrectNetwork}
                                    className={`w-full flex justify-between items-center p-3 rounded-lg border transition-all duration-200 text-sm
                                        ${selectedVote === option
                                            ? 'border-street-green bg-street-green/10 text-[var(--text-main)]'
                                            : 'border-[var(--border)] hover:border-street-muted text-street-muted hover:text-[var(--text-main)]'}
                                        ${(!isVotingOpen || hasVoted || !isConnected || !isCorrectNetwork) ? 'opacity-50 cursor-not-allowed' : ''}`}
                                >
                                    {option}
                                    {selectedVote === option && <Check size={16} className="text-street-green"/>}
                                </button>
                            ))}
                        </div>

                        <button
                            onClick={handleVote}
                            disabled={!selectedVote || !isVotingOpen || hasVoted || !isConnected || !isCorrectNetwork || isVoting || isConfirming}
                            className={`w-full rounded-lg py-3 text-xs font-bold uppercase tracking-wider transition-all flex items-center justify-center gap-2
                                ${selectedVote && isVotingOpen && !hasVoted && isConnected && isCorrectNetwork && !isVoting && !isConfirming
                                    ? 'street-gradient-bg text-black hover:opacity-90 shadow-md'
                                    : 'bg-[var(--surface-highlight)] text-street-muted cursor-not-allowed'}`}
                        >
                            {isVoting || isConfirming ? (
                                <>
                                    <Loader2 className="animate-spin" size={14} />
                                    {isConfirming ? 'Confirming...' : 'Submitting...'}
                                </>
                            ) : hasVoted ? (
                                'Already Voted'
                            ) : !isVotingOpen ? (
                                'Voting Closed'
                            ) : (
                                'Vote'
                            )}
                        </button>

                        {/* VOTING POWER SECTION - Real Data */}
                        <div className="mt-4 text-center">
                            <ConnectButton.Custom>
                                {({ account, openConnectModal }) => (
                                    <span className="text-[10px] text-street-muted font-mono">
                                    {account ? (
                                        isGovernanceLoading ? (
                                            <span className="flex items-center justify-center gap-2">
                                                <Loader2 className="animate-spin" size={10} /> Loading...
                                            </span>
                                        ) : (
                                            <span>Your voting power: <span className="text-street-green">{Number(formattedVotingPower).toLocaleString()} KLED</span></span>
                                        )
                                    ) : (
                                        <>
                                            Please <button onClick={openConnectModal} className="underline hover:text-[var(--text-main)] cursor-pointer">Log In</button> to vote
                                        </>
                                    )}
                                    </span>
                                )}
                            </ConnectButton.Custom>
                        </div>
                    </div>

                    {/* CURRENT RESULTS */}
                    <div className="bg-street-surface border street-border rounded-2xl p-6 shadow-sm">
                        <h3 className="text-sm font-bold text-street-muted uppercase tracking-widest mb-6">Current Results</h3>
                        <div className="space-y-5">
                            <div className="space-y-1">
                                <div className="flex justify-between text-xs text-[var(--text-main)]">
                                    <span>Yes</span>
                                    <span>{votes.yes}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full bg-street-green rounded-full" style={{ width: `${votes.yes}%` }}></div>
                                </div>
                            </div>

                            <div className="space-y-1">
                                <div className="flex justify-between text-xs text-[var(--text-main)]">
                                    <span>No</span>
                                    <span>{votes.no}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full street-red rounded-full" style={{ width: `${votes.no}%` }}></div>
                                </div>
                            </div>

                            <div className="space-y-1">
                                <div className="flex justify-between text-xs text-[var(--text-main)]">
                                    <span>Abstain</span>
                                    <span>{votes.abstain}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full bg-street-muted/30 rounded-full" style={{ width: `${votes.abstain}%` }}></div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* TIMELINE */}
                    <div className="bg-street-surface border street-border rounded-2xl p-6 shadow-sm">
                        <h3 className="text-sm font-bold text-street-muted uppercase tracking-widest mb-6">Timeline</h3>
                        <div className="space-y-6 relative pl-2">
                            <div className="absolute left-[5px] top-2 bottom-2 w-[1px] bg-[var(--border)]"></div>
                            <div className="flex gap-4 relative">
                                <div className="w-2.5 h-2.5 rounded-full bg-street-muted mt-1.5 relative z-10"></div>
                                <div>
                                    <p className="text-xs text-[var(--text-main)] font-medium">Created</p>
                                    <p className="text-[10px] text-street-muted">{formatDate(proposal.snapshotTime)}</p>
                                </div>
                            </div>
                            <div className="flex gap-4 relative">
                                <div className={`w-2.5 h-2.5 rounded-full mt-1.5 relative z-10 ${isVotingOpen ? 'bg-street-green shadow-[0_0_8px_#00C957]' : 'bg-street-muted'}`}></div>
                                <div>
                                    <p className="text-xs text-[var(--text-main)] font-medium">{isVotingOpen ? 'Active' : 'Voting Period'}</p>
                                    <p className="text-[10px] text-street-muted">{formatDate(proposal.startTime)}</p>
                                </div>
                            </div>
                            <div className="flex gap-4 relative">
                                <div className={`w-2.5 h-2.5 rounded-full mt-1.5 relative z-10 border border-[var(--border)] ${!isVotingOpen ? 'bg-street-muted' : 'bg-[var(--surface-highlight)]'}`}></div>
                                <div>
                                    <p className="text-xs text-street-muted font-medium">{!isVotingOpen ? 'Ended' : 'Ends'}</p>
                                    <p className="text-[10px] text-street-muted">{formatDate(proposal.endTime)}</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        )}

      </div>

      {/* --- FOOTER --- */}
      <footer className="w-full border-t street-border bg-street-surface mt-auto relative z-10">
          <PhysicsFooter />
          <div className="max-w-[1100px] mx-auto px-8 py-12">
              <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
                  <div className="col-span-1 md:col-span-2 space-y-4">
                     <div className="flex items-center gap-2">
                        {/* Footer Logo Switching */}
                        {currentTheme === 'light' ? (
                            <img src="/street-logo2.png" alt="Street" className="h-6 w-auto object-contain" />
                        ) : (
                            <img src="/street-logo.png" alt="Street" className="h-6 w-auto object-contain" />
                        )}
                     </div>
                     <p className="text-xs text-street-muted leading-relaxed max-w-xs">
                        The operating system for on-chain organizations. Govern, manage treasury, and grow your protocol with Street.
                     </p>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-[var(--text-main)] uppercase tracking-wider">Platform</h4>
                     <ul className="space-y-2 text-xs text-street-muted">
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Governance</a></li>
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Treasury</a></li>
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Documentation</a></li>
                     </ul>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-[var(--text-main)] uppercase tracking-wider">Legal</h4>
                     <ul className="space-y-2 text-xs text-street-muted">
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Terms of Service</a></li>
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Privacy Policy</a></li>
                        <li><a href="#" className="hover:text-[var(--text-main)] transition">Cookie Policy</a></li>
                     </ul>
                  </div>
              </div>
              <div className="pt-8 border-t street-border flex flex-col md:flex-row justify-between items-center gap-4">
                  <p className="text-[10px] text-street-muted">© 2025 Street Protocol. All rights reserved.</p>
                  <div className="flex gap-6 text-street-muted">
                      <a href="https://x.com/StreetFDN" target="_blank" rel="noreferrer" className="hover:text-[var(--text-main)] transition">
                          <Twitter size={16} />
                      </a>
                      <a href="#" className="hover:text-[var(--text-main)] transition">
                          <Globe size={16} />
                      </a>
                  </div>
              </div>
          </div>
      </footer>
    </main>
  );
}

// --- MAIN EXPORT WITH SUSPENSE BOUNDARY ---
export default function ProposalPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-street-background">
        <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-street-muted"></div>
      </div>
    }>
      <ProposalPageContent />
    </Suspense>
  );
}