'use client';

import { useState, useEffect, useRef, Suspense } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import {
  ArrowLeft,
  Lock,
  MessageSquarePlus,
  User,
  X,
  ThumbsUp,
  ThumbsDown,
  Wallet,
  Clock,
  Twitter,
  Globe,
  Loader2,
  AlertTriangle,
} from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { useAccount, useSwitchChain } from 'wagmi';
import {
  useProposal,
  useProposalCount,
  useSuggestionCount,
  useSuggestion,
  useUserGovernance,
  useProposeEdit,
  useVoteOnSuggestion,
  useChainCheck,
  useEditStake,
  GOVERNANCE_CONFIG,
  REQUIRED_CHAIN_ID,
  formatKled,
  formatTimestamp,
} from '@/app/hooks/useGovernance';
import { keccak256, toBytes } from 'viem';

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

// --- TIME GOVERNANCE SETTINGS ---
const EDITING_WINDOW_HOURS = 48;
const VOTING_WINDOW_HOURS = 72;

function ProposalEditorContent() {
  const searchParams = useSearchParams();
  const proposalIdParam = searchParams.get('id');

  const { isConnected, address } = useAccount();
  const { switchChain } = useSwitchChain();
  const [isClient, setIsClient] = useState(false);
  const currentTheme = useThemeObserver();

  // Governance hooks
  const { balance, formattedBalance, formattedVotingPower, canSuggestEdit, isLoading: isGovernanceLoading } = useUserGovernance();
  const { isCorrectNetwork, requiredChainName } = useChainCheck();
  const { data: editStake } = useEditStake();

  // Get proposal count to default to latest
  const { data: proposalCount } = useProposalCount();
  const proposalId = proposalIdParam
    ? BigInt(proposalIdParam)
    : (proposalCount && proposalCount > BigInt(0) ? proposalCount : BigInt(1));

  // Fetch proposal data
  const { data: proposal, isLoading: isProposalLoading, refetch: refetchProposal } = useProposal(proposalId);

  // Fetch suggestions for this proposal
  const { data: suggestionCount } = useSuggestionCount();
  const { data: suggestion1 } = useSuggestion(BigInt(1));
  const { data: suggestion2 } = useSuggestion(BigInt(2));
  const { data: suggestion3 } = useSuggestion(BigInt(3));

  // Build suggestions array from fetched data
  // Tuple format: [proposalId, suggester, originalHash, proposedText, forVotes, againstVotes, finalized, accepted]
  const suggestionData = [
    { id: BigInt(1), data: suggestion1 },
    { id: BigInt(2), data: suggestion2 },
    { id: BigInt(3), data: suggestion3 },
  ];
  const allSuggestions = suggestionData
    .filter(s => s.data && s.data[0] === proposalId) // data[0] is proposalId
    .map(s => ({
      id: s.id.toString(),
      original: '', // Would need to store original text hash mapping
      proposed: s.data![3], // data[3] is proposedText
      author: `${s.data![1].slice(0, 6)}...${s.data![1].slice(-4)}`, // data[1] is suggester
      stake: Number(s.data![4]) / 1e18, // Using forVotes index as approximate stake
      votes: { yes: Number(s.data![4]) / 1e18, no: Number(s.data![5]) / 1e18 }, // data[4]=forVotes, data[5]=againstVotes
      status: s.data![6] ? 'RESOLVED' : 'ACTIVE', // data[6] is finalized
    }));

  // Propose edit hook
  const { proposeEdit, isPending: isProposePending, isConfirming: isProposeConfirming, isSuccess: proposeSuccess } = useProposeEdit();

  // Vote on suggestion hook
  const { vote: voteOnSuggestion, isPending: isVotePending, isConfirming: isVoteConfirming, isSuccess: voteSuccess } = useVoteOnSuggestion();

  // --- EDITOR STATE ---
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [activeSuggestionId, setActiveSuggestionId] = useState<string | null>(null);

  const [selectionRange, setSelectionRange] = useState<Range | null>(null);
  const [selectionText, setSelectionText] = useState("");
  const [draftText, setDraftText] = useState("");

  // Modals
  const [showProposeModal, setShowProposeModal] = useState(false);
  const [showAuthModal, setShowAuthModal] = useState(false);

  const contentRef = useRef<HTMLDivElement>(null);

  // Sync suggestions from chain
  useEffect(() => {
    if (allSuggestions.length > 0) {
      setSuggestions(allSuggestions);
      if (!activeSuggestionId && allSuggestions.length > 0) {
        setActiveSuggestionId(allSuggestions[0].id);
      }
    }
  }, [allSuggestions.length]);

  // User balance from chain
  const userBalance = balance ? Number(balance) / 1e18 : 0;
  const MIN_HOLDING_AMOUNT = Number(GOVERNANCE_CONFIG.MIN_VOTING_POWER) / 1e18;
  const STAKE_REQUIRED = editStake ? Number(editStake) / 1e18 : 500;

  useEffect(() => {
    setIsClient(true);
  }, []);

  // Derived Logic - based on proposal timestamps from chain
  // Tuple format: [proposer, title, description, forVotes, againstVotes, abstainVotes, startTime, endTime, currentState]
  const now = Math.floor(Date.now() / 1000);
  const proposalStartTime = proposal ? Number(proposal[6]) : now; // proposal[6] = startTime
  const proposalEndTime = proposal ? Number(proposal[7]) : now; // proposal[7] = endTime

  // Edit window is before voting starts
  const isNewProposalsAllowed = proposal ? now < proposalStartTime : false;

  // Calculate hours remaining in edit window (time until voting starts)
  const hoursUntilVoting = proposal ? Math.max(0, (proposalStartTime - now) / 3600) : 0;
  const hoursSincePublish = EDITING_WINDOW_HOURS - hoursUntilVoting;

  // Voting is open during the voting period
  const isVotingOpen = proposal ? (now >= proposalStartTime && now <= proposalEndTime) : false;

  const isEligible = isConnected && isCorrectNetwork && userBalance >= MIN_HOLDING_AMOUNT;

  // Get proposal content
  const DOC_TITLE = proposal ? proposal[1] : 'Loading...'; // proposal[1] = title
  const PARAGRAPHS = proposal
    ? [{ id: 'p1', text: proposal[2] }] // proposal[2] = description
    : [{ id: 'p1', text: 'Loading proposal content...' }];

  // 1. Handle Text Selection
  const handleMouseUp = () => {
    const selection = window.getSelection();
    if (selection && selection.toString().trim().length > 0 && contentRef.current?.contains(selection.anchorNode)) {
      if (selection.rangeCount > 0) {
        const range = selection.getRangeAt(0);
        const text = selection.toString();
        setSelectionRange(range);
        setSelectionText(text);
        setDraftText(text); 
      }
    }
  };

  // 2. Click "Suggest" Button
  const handleSuggestClick = () => {
    if (!isConnected) {
        setShowAuthModal(true);
        setSelectionRange(null);
        return;
    }

    if (!isCorrectNetwork) {
        alert(`Please switch to ${requiredChainName}`);
        return;
    }

    if (!isNewProposalsAllowed) {
        alert("The editing window for suggestions has closed. Voting has started.");
        setSelectionRange(null);
        return;
    }

    if (userBalance < MIN_HOLDING_AMOUNT) {
        alert(`Insufficient Balance. You need ${MIN_HOLDING_AMOUNT.toLocaleString()} KLED to edit.`);
        return;
    }

    if (!canSuggestEdit) {
        alert(`Insufficient Balance. You need ${STAKE_REQUIRED.toLocaleString()} KLED to stake for an edit.`);
        return;
    }

    setShowProposeModal(true);
    setSelectionRange(null);
  };

  // 3. Submit Proposal Logic - calls real contract
  const submitProposal = () => {
      if (!proposalId || !selectionText || !draftText) return;

      // Hash the original text for on-chain verification
      const originalHash = keccak256(toBytes(selectionText));

      // Call the contract
      proposeEdit(proposalId, originalHash, draftText);

      // Optimistically add to UI while waiting for confirmation
      const newId = Date.now().toString();
      const newSuggestion = {
          id: newId,
          original: selectionText,
          proposed: draftText,
          author: "You",
          stake: STAKE_REQUIRED,
          date: new Date().toLocaleDateString(),
          votes: { yes: 0, no: 0 },
          status: "PENDING"
      };

      setSuggestions([newSuggestion, ...suggestions]);
      setShowProposeModal(false);
      setActiveSuggestionId(newId);
  };

  // 4. Voting Logic - calls real contract
  const handleVote = (id: string, type: 'yes' | 'no') => {
      // Call contract to vote
      voteOnSuggestion(BigInt(id), type === 'yes');

      // Optimistic UI update
      setSuggestions(suggestions.map(s => {
          if (s.id === id) {
              return {
                  ...s,
                  votes: {
                      ...s.votes,
                      [type]: s.votes[type] + userBalance
                  }
              };
          }
          return s;
      }));
  };

  // 5. Render text with highlights
  const renderTextWithHighlights = (text: string) => {
    if (suggestions.length === 0) return text;

    let parts = [{ text, isHighlight: false }];

    suggestions.forEach(sugg => {
        const newParts: any[] = [];
        parts.forEach(part => {
            if (part.isHighlight) {
                newParts.push(part);
            } else {
                const split = part.text.split(sugg.original);
                for (let i = 0; i < split.length; i++) {
                    if (split[i]) newParts.push({ text: split[i], isHighlight: false });
                    if (i < split.length - 1) {
                        newParts.push({ text: sugg.original, isHighlight: true });
                    }
                }
            }
        });
        parts = newParts;
    });

    return parts.map((part, i) => 
        part.isHighlight ? (
            <span key={i} className="bg-gradient-to-r from-[#BDB9FF]/20 via-[#FD7DEC]/20 to-[#FFC3F6]/20 border-b-2 border-[#FD7DEC] text-[var(--text-main)] animate-pulse decoration-clone">
                {part.text}
            </span>
        ) : (
            <span key={i}>{part.text}</span>
        )
    );
  };

  if (!isClient) return null;

  return (
    <main className="min-h-screen flex flex-col font-sans bg-street-background text-[var(--text-main)] selection:bg-[#FD7DEC] selection:text-black transition-colors duration-300">
      
      {/* --- NAVBAR --- */}
      <nav className="w-full border-b street-border">
        <div className="max-w-[1100px] mx-auto px-8 py-4 flex justify-between items-center">
            <div className="flex items-center gap-3">
               {/* DYNAMIC LOGO SWITCHING */}
               <div className="relative h-8 w-32 flex items-center">
                 {/* Light Mode: Black Logo */}
                 <img 
                   src="/street-logo2.png" 
                   alt="Street" 
                   className={`h-8 w-auto absolute left-0 top-0 transition-opacity duration-300 object-contain ${currentTheme === 'light' ? 'opacity-100' : 'opacity-0'}`} 
                 />
                 {/* Dark Mode: White Logo */}
                 <img 
                   src="/street-logo.png" 
                   alt="Street" 
                   className={`h-8 w-auto absolute left-0 top-0 transition-opacity duration-300 object-contain ${currentTheme === 'dark' ? 'opacity-100' : 'opacity-0'}`}
                 />
               </div>
            </div>
            
            <div className="flex items-center gap-4">
                <Link href="/">
                    <button className="px-4 py-2 rounded-lg border street-border text-street-muted text-xs hover:bg-[var(--surface-highlight)] transition flex items-center gap-2">
                        <ArrowLeft size={14}/> Back to Dashboard
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

      {/* --- MAIN EDITOR LAYOUT --- */}
      <div className="max-w-[1100px] mx-auto w-full px-8 py-16 flex flex-col lg:flex-row gap-16 flex-1 relative">
        
        {/* LEFT COLUMN: DOCUMENT */}
        <div className="flex-1 max-w-[580px] relative">
            
            {/* Document Header / Metadata */}
            <div className="mb-12 cursor-default select-none">
                <div className="flex items-center flex-wrap gap-3 mb-4">
                     <span className="text-[10px] font-bold text-street-muted tracking-widest uppercase flex items-center gap-2 border street-border px-2 py-1 rounded">
                        <span className="w-1.5 h-1.5 rounded-full bg-street-muted"></span> Draft-001
                     </span>
                     
                     {/* Eligibility Badge */}
                     <span className={`text-[10px] font-bold tracking-widest uppercase flex items-center gap-2 border street-border px-2 py-1 rounded transition-colors
                        ${isEligible ? "text-street-green border-street-green/30 bg-street-green/5" : "text-street-red border-street-red/30 bg-street-red/5"}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${isEligible ? "bg-street-green animate-pulse" : "bg-street-red"}`}></span>
                        {isEligible ? "Eligible to Suggest" : "Not Eligible"}
                     </span>

                     {/* Governance Timer */}
                     <span className="ml-auto text-[10px] font-mono text-street-muted flex items-center gap-2">
                        <Clock size={12} />
                        {isNewProposalsAllowed 
                            ? `${(EDITING_WINDOW_HOURS - hoursSincePublish).toFixed(0)}h left to suggest` 
                            : "Suggestions Closed"}
                     </span>
                </div>
                {/* Smaller Title */}
                <h1 className="text-4xl font-bold text-[var(--text-main)] tracking-tight leading-tight font-serif">{DOC_TITLE}</h1>
            </div>

            {/* Content Body (Editable Area) */}
            <div 
                className="space-y-6 text-sm leading-7 text-street-muted font-sans" 
                ref={contentRef} 
                onMouseUp={handleMouseUp}
            >
                {PARAGRAPHS.map((p) => (
                    <p key={p.id} className="selection:bg-[#FD7DEC] selection:text-black">
                        {renderTextWithHighlights(p.text)}
                    </p>
                ))}
            </div>

            {/* Floating Tooltip */}
            {selectionRange && !showProposeModal && (
                <div 
                    className="absolute z-40 flex items-center gap-2 bg-street-surface text-[var(--text-main)] px-2 py-1.5 rounded-lg shadow-2xl border street-border animate-in fade-in zoom-in-95 duration-150"
                    style={{ 
                        top: selectionRange.getBoundingClientRect().top + window.scrollY - 50, 
                        left: selectionRange.getBoundingClientRect().left 
                    }}
                >
                    <button onClick={handleSuggestClick} className="flex items-center gap-2 hover:bg-[var(--surface-highlight)] px-3 py-1.5 rounded text-xs font-bold transition-colors text-[var(--text-main)] group">
                        <MessageSquarePlus size={14} className="text-[#FD7DEC] group-hover:scale-110 transition-transform"/> 
                        Suggest Edit
                    </button>
                    <div className="w-[1px] h-4 bg-street-border"></div>
                    <span className="text-[9px] text-street-muted font-mono px-2">Stakes 500 KLED</span>
                </div>
            )}
        </div>

        {/* RIGHT COLUMN: PEER REVIEW QUEUE */}
        <div className="w-full lg:w-[340px] flex-shrink-0 relative border-l street-border pl-8 hidden lg:block">
            <div className="sticky top-12 space-y-6">
                <div className="flex justify-between items-center">
                    <h4 className="text-xs font-bold text-street-muted uppercase tracking-widest flex items-center gap-2">
                        Peer Review Queue 
                        <span className="bg-[var(--surface-highlight)] text-[var(--text-main)] text-[9px] px-1.5 rounded-full">{suggestions.length}</span>
                    </h4>
                    {/* Lock Indicator if time expired */}
                    {!isNewProposalsAllowed && (
                        <span className="text-[9px] text-street-red border border-street-red/30 px-2 py-0.5 rounded font-mono flex items-center gap-1">
                            <Lock size={8} /> LOCKED
                        </span>
                    )}
                </div>

                {/* Suggestion List */}
                {suggestions.length === 0 ? (
                    <div className="text-center py-8 text-street-muted text-sm">
                        No edit suggestions yet
                    </div>
                ) : (
                    suggestions.map((suggestion) => (
                        <SuggestionCard
                            key={suggestion.id}
                            suggestion={suggestion}
                            userBalance={userBalance}
                            isActive={activeSuggestionId === suggestion.id}
                            isVotingOpen={isVotingOpen}
                            onClick={() => setActiveSuggestionId(suggestion.id)}
                            onVote={(type) => handleVote(suggestion.id, type)}
                            isPending={isVotePending || isVoteConfirming}
                        />
                    ))
                )}
            </div>
        </div>

      </div>

      {/* --- AUTH MODAL (Access Denied) --- */}
      {showAuthModal && (
          <div className="fixed inset-0 z-[110] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4 animate-in fade-in duration-200">
              <div className="bg-street-surface border street-border rounded-xl w-full max-w-sm shadow-2xl relative overflow-hidden">
                  <div className="h-1 w-full bg-gradient-to-r from-[#BDB9FF] via-[#FD7DEC] to-[#FFC3F6]"></div>
                  <div className="p-8 flex flex-col items-center text-center">
                       <div className="w-16 h-16 rounded-full bg-street-background border street-border flex items-center justify-center mb-6">
                           <Wallet className="w-8 h-8 text-[#FD7DEC] animate-bounce" strokeWidth={1.5} />
                       </div>
                       <h3 className="text-xl font-serif text-[var(--text-main)] mb-2">Connect Wallet</h3>
                       <p className="text-xs text-street-muted leading-relaxed mb-8 max-w-[240px]">
                           You need to connect your wallet to propose edits, stake tokens, and participate in governance.
                       </p>
                       <ConnectButton.Custom>
                            {({ openConnectModal, mounted }) => (
                                <button 
                                    onClick={() => {
                                        if (mounted && openConnectModal) {
                                            openConnectModal();
                                            setShowAuthModal(false); 
                                        }
                                    }}
                                    className="street-gradient-bg text-black w-full py-3 rounded-lg font-bold text-sm hover:opacity-90 transition shadow-lg active:scale-95 duration-150"
                                >
                                    Connect Now
                                </button>
                            )}
                       </ConnectButton.Custom>
                       <button 
                            onClick={() => setShowAuthModal(false)}
                            className="mt-4 text-[10px] text-street-muted hover:text-[var(--text-main)] transition"
                        >
                            Cancel
                       </button>
                  </div>
              </div>
          </div>
      )}

      {/* --- PROPOSAL MODAL (Input) --- */}
      {showProposeModal && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
              <div className="bg-street-surface border street-border rounded-xl w-full max-w-lg shadow-2xl animate-in fade-in zoom-in-95">
                  <div className="p-5 border-b street-border flex justify-between items-center">
                      <h3 className="text-sm font-bold text-[var(--text-main)] uppercase tracking-wider">Propose Edit</h3>
                      <button onClick={() => setShowProposeModal(false)}><X size={16} className="text-street-muted hover:text-[var(--text-main)] transition"/></button>
                  </div>
                  <div className="p-6 space-y-6">
                      <div className="space-y-2">
                          <label className="text-[10px] uppercase tracking-wider text-street-muted font-bold">Selected Text</label>
                          <div className="p-4 bg-street-background rounded text-sm text-street-muted border street-border leading-relaxed italic font-serif">
                              "{selectionText}"
                          </div>
                      </div>
                      <div className="space-y-2">
                          <label className="text-[10px] uppercase tracking-wider text-street-green font-bold">Your Revision</label>
                          <textarea 
                              className="w-full bg-street-background text-[var(--text-main)] text-sm p-4 rounded border street-border focus:border-street-green/50 focus:ring-1 focus:ring-street-green/50 outline-none min-h-[120px] font-sans leading-relaxed"
                              value={draftText}
                              onChange={(e) => setDraftText(e.target.value)}
                              autoFocus
                          />
                      </div>
                      <div className="flex justify-between items-center pt-2">
                          <div className="flex items-center gap-2 text-xs text-street-muted">
                              <Lock size={12}/>
                              <span>Stake: <span className="text-[var(--text-main)] font-mono">{STAKE_REQUIRED} KLED</span></span>
                          </div>
                          <div className="flex gap-2">
                              <button 
                                onClick={() => setShowProposeModal(false)}
                                className="px-4 py-2 text-xs text-street-muted hover:text-[var(--text-main)] transition"
                              >
                                  Cancel
                              </button>
                              <button 
                                onClick={submitProposal}
                                className="street-gradient-bg text-black px-6 py-2 rounded font-bold text-xs hover:opacity-90 transition shadow-lg"
                              >
                                  Confirm & Stake
                              </button>
                          </div>
                      </div>
                  </div>
              </div>
          </div>
      )}

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
                        {/* Removed duplicate text span */}
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

// --- SUGGESTION CARD (With Web3 Voting) ---
function SuggestionCard({
    suggestion,
    isActive,
    userBalance,
    isVotingOpen,
    onClick,
    onVote,
    isPending,
}: {
    suggestion: any,
    isActive: boolean,
    userBalance: number,
    isVotingOpen: boolean,
    onClick: () => void,
    onVote: (type: 'yes' | 'no') => void,
    isPending?: boolean,
}) {
    // Calculate Vote Stats
    const totalVotes = suggestion.votes.yes + suggestion.votes.no;
    const yesPercent = totalVotes > 0 ? (suggestion.votes.yes / totalVotes) * 100 : 0;
    const noPercent = totalVotes > 0 ? (suggestion.votes.no / totalVotes) * 100 : 0;

    const handleOnChainVote = async (support: boolean) => {
        if(!isVotingOpen) return;
        // Call parent handler which now calls the real contract
        onVote(support ? 'yes' : 'no');
    };

    return (
        <div 
            onClick={onClick}
            className={`bg-street-surface border rounded-xl overflow-hidden transition-all duration-200 cursor-pointer group
                ${isActive ? 'border-[var(--text-main)] shadow-md' : 'border-street-border hover:border-street-muted'}
            `}
        >
            {/* Card Header */}
            <div className="px-4 py-3 border-b street-border flex justify-between items-center bg-[var(--surface-highlight)]">
                <div className="flex items-center gap-2">
                    <div className="w-5 h-5 rounded-full bg-street-background border street-border flex items-center justify-center text-[8px] text-[var(--text-main)] font-bold">
                        <User size={10}/>
                    </div>
                    <span className="text-[10px] font-mono text-[var(--text-main)]">{suggestion.author}</span>
                </div>
                <span className={`text-[9px] px-2 py-0.5 rounded border font-bold tracking-wider ${isVotingOpen ? 'text-[var(--text-main)] bg-white/10 border-white/20' : 'text-street-red bg-red-900/10 border-red-500/20'}`}>
                    {isVotingOpen ? 'ACTIVE' : 'CLOSED'}
                </span>
            </div>

            {/* Card Content */}
            <div className="p-4 space-y-5">
                <div className="space-y-4">
                    <div className="space-y-1">
                        <div className="text-[9px] text-street-muted uppercase font-bold tracking-wider">Original</div>
                        <p className="text-sm text-street-muted line-through font-serif italic decoration-street-red/30 decoration-2">
                            {suggestion.original}
                        </p>
                    </div>
                    <div className="space-y-1">
                        <div className="text-[9px] text-[var(--text-main)] uppercase font-bold tracking-wider">Proposed Change</div>
                        <div className="text-lg text-[var(--text-main)] font-serif leading-snug">
                            {suggestion.proposed}
                        </div>
                    </div>
                </div>

                {/* Voting Section */}
                <div className="pt-2 border-t street-border">
                    <div className="flex justify-between items-end mb-2">
                        <span className="text-[9px] text-street-muted font-bold uppercase tracking-wider">Votes</span>
                        <div className="flex gap-3 text-[10px] font-mono font-medium">
                            <span className="text-[var(--text-main)]">{(suggestion.votes.yes / 1000).toFixed(1)}k <span className="text-street-muted">YES</span></span>
                            <span className="text-street-muted">|</span>
                            <span className="text-[var(--text-main)]">{(suggestion.votes.no / 1000).toFixed(1)}k <span className="text-street-muted">NO</span></span>
                        </div>
                    </div>

                    {/* Vote Bar */}
                    <div className="h-1.5 w-full bg-street-background rounded-full overflow-hidden flex border street-border">
                        {totalVotes > 0 ? (
                            <>
                                <div style={{ width: `${yesPercent}%` }} className="h-full bg-street-green shadow-[0_0_8px_rgba(0,201,87,0.5)]"></div>
                                <div style={{ width: `${noPercent}%` }} className="h-full bg-street-red"></div> 
                            </>
                        ) : (
                            <div className="w-full h-full bg-street-background"></div>
                        )}
                    </div>
                </div>

                {/* Web3 Vote Buttons */}
                {isActive && isVotingOpen && (
                    <div className="grid grid-cols-2 gap-3 animate-in fade-in slide-in-from-top-2">
                        <button 
                            disabled={isPending}
                            onClick={(e) => { e.stopPropagation(); handleOnChainVote(false); }}
                            className="py-2.5 rounded border street-border hover:border-street-red text-street-muted hover:text-street-red transition text-[10px] font-bold uppercase tracking-widest flex items-center justify-center gap-2 disabled:opacity-50 group/no"
                        >
                            <ThumbsDown size={12} className="group-hover/no:text-street-red"/> Vote No
                        </button>
                        <button 
                            disabled={isPending}
                            onClick={(e) => { e.stopPropagation(); handleOnChainVote(true); }}
                            className="py-2.5 rounded border border-[var(--text-main)] bg-[var(--text-main)] text-[var(--background)] hover:opacity-90 transition text-[10px] font-bold uppercase tracking-widest flex items-center justify-center gap-2 shadow-sm disabled:opacity-50"
                        >
                            {isPending ? <span className="animate-spin">↻</span> : <ThumbsUp size={12}/>} 
                            Vote Yes
                        </button>
                    </div>
                )}
                
                {isActive && (
                    <div className="text-center">
                        <span className="text-[9px] text-street-muted font-mono">
                            Voting Power: {userBalance.toLocaleString()} KLED
                        </span>
                    </div>
                )}
            </div>
        </div>
    )
}

// --- MAIN EXPORT WITH SUSPENSE BOUNDARY ---
export default function ProposalEditor() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-street-background">
        <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-street-muted"></div>
      </div>
    }>
      <ProposalEditorContent />
    </Suspense>
  );
}