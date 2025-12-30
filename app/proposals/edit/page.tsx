'use client';

import { useState, useEffect, useRef } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
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
  // Added missing imports here
  Twitter,
  Globe
} from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { useAccount, useWriteContract } from 'wagmi';

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

// --- MOCK SMART CONTRACT CONFIG ---
const GOVERNANCE_CONTRACT_ADDRESS = "0x1234567890123456789012345678901234567890";
const MOCK_ABI = [
    { name: 'voteOnSuggestion', type: 'function', inputs: [{ type: 'uint256', name: 'id' }, { type: 'bool', name: 'support' }] },
    { name: 'proposeEdit', type: 'function', inputs: [{ type: 'string', name: 'original' }, { type: 'string', name: 'proposed' }] }
];

// --- TIME GOVERNANCE SETTINGS ---
const PUBLISHED_AT = new Date(Date.now() - (20 * 60 * 60 * 1000)).getTime(); 
const EDITING_WINDOW_HOURS = 48; 
const VOTING_WINDOW_HOURS = 72;

// --- DOCUMENT CONTENT ---
const DOC_TITLE = "Fire Avi Patel as CEO";
const PARAGRAPHS = [
  { id: 'p1', text: "This proposal discusses relieving Avi Patel, the current CEO from his active duties and reinstating the CEO role with Robert Chang as his replacement. This action is considered critical for the next phase of growth." },
  { id: 'p2', text: "Despite consistent updates, the token price has shown volatility. Wintermute, as the designated market maker, has not provided sufficient buy-side liquidity during the recent dip." },
  { id: 'p3', text: "We propose an immediate governance vote to execute this transition, ensuring stability and renewed confidence in the protocol's leadership." }
];

const MIN_HOLDING_AMOUNT = 10000;
const STAKE_REQUIRED = 500;

export default function ProposalEditor() {
  const { isConnected } = useAccount();
  const [userBalance, setUserBalance] = useState(15420); 
  const [isClient, setIsClient] = useState(false);
  const currentTheme = useThemeObserver();

  // --- GOVERNANCE TIME STATE ---
  const [hoursSincePublish, setHoursSincePublish] = useState(0);

  // --- EDITOR STATE ---
  const [suggestions, setSuggestions] = useState<any[]>([
      {
          id: "1",
          original: "Robert Chang",
          proposed: "CZ",
          author: "0xB2...9A",
          stake: 500,
          votes: { yes: 322600, no: 412900 },
          status: "ACTIVE"
      }
  ]);
  const [activeSuggestionId, setActiveSuggestionId] = useState<string | null>("1");

  const [selectionRange, setSelectionRange] = useState<Range | null>(null);
  const [selectionText, setSelectionText] = useState("");
  const [draftText, setDraftText] = useState("");
  
  // Modals
  const [showProposeModal, setShowProposeModal] = useState(false);
  const [showAuthModal, setShowAuthModal] = useState(false);

  const contentRef = useRef<HTMLDivElement>(null);

  // Wagmi Hook
  const { writeContract, isPending } = useWriteContract();

  useEffect(() => {
    setIsClient(true);
    const diff = (Date.now() - PUBLISHED_AT) / (1000 * 60 * 60);
    setHoursSincePublish(diff);
  }, []);

  // Derived Logic
  const isNewProposalsAllowed = hoursSincePublish < EDITING_WINDOW_HOURS;
  const isVotingOpen = hoursSincePublish < VOTING_WINDOW_HOURS;
  const isEligible = isConnected && userBalance >= MIN_HOLDING_AMOUNT;

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

    if (!isNewProposalsAllowed) {
        alert("The 48-hour window for new suggestions has closed.");
        setSelectionRange(null);
        return;
    }

    if (userBalance < MIN_HOLDING_AMOUNT) {
        alert(`Insufficient Balance. You need ${MIN_HOLDING_AMOUNT} KLED to edit.`);
        return;
    }
    setShowProposeModal(true);
    setSelectionRange(null); 
  };

  // 3. Submit Proposal Logic
  const submitProposal = () => {
      const newId = Date.now().toString();
      const newSuggestion = {
          id: newId,
          original: selectionText,
          proposed: draftText,
          author: "You",
          stake: STAKE_REQUIRED,
          date: new Date().toLocaleDateString(),
          votes: { yes: 0, no: 0 },
          status: "ACTIVE"
      };
      
      setSuggestions([newSuggestion, ...suggestions]);
      setShowProposeModal(false);
      setActiveSuggestionId(newId);
  };

  // 4. Voting Logic
  const handleVote = (id: string, type: 'yes' | 'no') => {
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
                {suggestions.map((suggestion) => (
                    <SuggestionCard 
                        key={suggestion.id} 
                        suggestion={suggestion} 
                        userBalance={userBalance}
                        isActive={activeSuggestionId === suggestion.id}
                        isVotingOpen={isVotingOpen}
                        onClick={() => setActiveSuggestionId(suggestion.id)}
                        onVote={(type) => handleVote(suggestion.id, type)}
                    />
                ))}
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
    onVote
}: { 
    suggestion: any, 
    isActive: boolean, 
    userBalance: number,
    isVotingOpen: boolean,
    onClick: () => void,
    onVote: (type: 'yes' | 'no') => void
}) {
    // Web3 Hook for writing
    const { writeContract, isPending } = useWriteContract();
    
    // Calculate Vote Stats
    const totalVotes = suggestion.votes.yes + suggestion.votes.no;
    const yesPercent = totalVotes > 0 ? (suggestion.votes.yes / totalVotes) * 100 : 0;
    const noPercent = totalVotes > 0 ? (suggestion.votes.no / totalVotes) * 100 : 0;

    const handleOnChainVote = async (support: boolean) => {
        if(!isVotingOpen) return;
        
        try {
            console.log(`Voting ${support ? 'YES' : 'NO'} on proposal ${suggestion.id}`);
            
            // Trigger Wallet (Mocked Contract Call)
            writeContract({
                address: GOVERNANCE_CONTRACT_ADDRESS,
                abi: MOCK_ABI,
                functionName: 'voteOnSuggestion',
                args: [BigInt(suggestion.id), support]
            });

            // Update local state (optimistic)
            onVote(support ? 'yes' : 'no');

        } catch (err) {
            console.error("Voting failed", err);
        }
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