'use client';

import { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi'; 
import Link from 'next/link';
import { ArrowLeft, Check, ExternalLink, Clock, Info, Twitter, Globe } from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';

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

const PROPOSAL = {
  id: 42,
  title: "Blame Wintermute",
  status: "LIVE",
  author: "0x1234...5678",
  created: "Nov 20, 2025",
  ends: "Nov 23, 2025",
  summary: "The Chart is down, we should find a reason to blame it on. This proposal discusses blaming Wintermute as the reason for it. Market makers must be held accountable for price action that does not align with community expectations.",
  rationale: "Despite consistent updates, the token price has shown volatility. Wintermute, as the designated market maker, has not provided sufficient buy-side liquidity during the recent dip. This proposal seeks to formally register community dissatisfaction and request a detailed report on MM activities.",
  votes: {
    yes: 60,
    no: 20,
    abstain: 20
  }
};

export default function ProposalPage() {
  const [selectedVote, setSelectedVote] = useState<string | null>(null);
  const { isConnected } = useAccount();
  const currentTheme = useThemeObserver();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

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

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
            
            {/* LEFT COLUMN: Proposal Content */}
            <div className="lg:col-span-2 space-y-8">
                
                <div className="space-y-4">
                    <div className="flex items-center gap-3">
                        <span className="w-2 h-2 rounded-full bg-street-green animate-pulse"></span>
                        <span className="text-street-green font-bold text-xs tracking-widest uppercase">Live Proposal</span>
                    </div>
                    <h1 className="text-5xl font-serif text-[var(--text-main)] leading-tight">{PROPOSAL.title}</h1>
                    
                    <div className="flex items-center gap-6 text-xs text-street-muted font-mono border-b street-border pb-8">
                        <div className="flex items-center gap-2">
                            <div className="w-5 h-5 rounded-full bg-gradient-to-br from-blue-400 to-purple-500"></div>
                            <span>by {PROPOSAL.author}</span>
                        </div>
                        <span>•</span>
                        <span className="flex items-center gap-1"><Clock size={12}/> Posted {PROPOSAL.created}</span>
                        <span>•</span>
                        <a href="#" className="flex items-center gap-1 hover:text-[var(--text-main)] transition">
                            Discussion <ExternalLink size={10}/>
                        </a>
                    </div>
                </div>

                <div className="space-y-8 text-sm text-[var(--text-main)] leading-relaxed font-light">
                    <section>
                        <h3 className="text-xl font-serif text-[var(--text-main)] mb-3">Summary</h3>
                        <p className="text-street-muted">{PROPOSAL.summary}</p>
                    </section>
                    
                    <section>
                        <h3 className="text-xl font-serif text-[var(--text-main)] mb-3">Rationale</h3>
                        <p className="text-street-muted">{PROPOSAL.rationale}</p>
                        <p className="text-street-muted mt-4">
                            Market stability is paramount for the confidence of $STARTUP holders. We demand transparency regarding the algorithmic strategies employed during high-volatility periods.
                        </p>
                    </section>

                    <div className="p-4 border street-border rounded-xl bg-street-surface/50 flex gap-3 items-start">
                        <Info className="text-street-muted w-5 h-5 flex-shrink-0 mt-0.5"/>
                        <p className="text-xs text-street-muted">
                            Note: This proposal is a signaling vote. If passed, it moves to the Board Review stage before on-chain execution.
                        </p>
                    </div>
                </div>

            </div>

            {/* RIGHT COLUMN: Sticky Sidebar */}
            <div className="lg:col-span-1 space-y-6 relative">
                <div className="sticky top-24 space-y-6">
                    
                    {/* CAST VOTE CARD */}
                    <div className="bg-street-surface border street-border rounded-2xl p-6 shadow-sm">
                        <h3 className="text-xl font-serif text-[var(--text-main)] mb-6">Cast your vote</h3>
                        
                        <div className="space-y-3 mb-8">
                            {['Yes', 'No', 'Abstain'].map((option) => (
                                <button 
                                    key={option}
                                    onClick={() => setSelectedVote(option)}
                                    className={`w-full flex justify-between items-center p-3 rounded-lg border transition-all duration-200 text-sm
                                        ${selectedVote === option 
                                            ? 'border-street-green bg-street-green/10 text-[var(--text-main)]' 
                                            : 'border-[var(--border)] hover:border-street-muted text-street-muted hover:text-[var(--text-main)]'}`}
                                >
                                    {option}
                                    {selectedVote === option && <Check size={16} className="text-street-green"/>}
                                </button>
                            ))}
                        </div>

                        <button 
                            disabled={!selectedVote}
                            className={`w-full rounded-lg py-3 text-xs font-bold uppercase tracking-wider transition-all
                                ${selectedVote 
                                    ? 'street-gradient-bg text-black hover:opacity-90 shadow-md' 
                                    : 'bg-[var(--surface-highlight)] text-street-muted cursor-not-allowed'}`}
                        >
                            Vote
                        </button>

                        {/* VOTING POWER SECTION - DYNAMIC */}
                        <div className="mt-4 text-center">
                             <ConnectButton.Custom>
                                {({ account, openConnectModal }) => (
                                    <span className="text-[10px] text-street-muted font-mono">
                                    {account && account.isConnected ? (
                                        <span>Your voting power: <span className="text-street-green">15,420 $KLED</span></span>
                                    ) : (
                                        <>
                                            Please <button onClick={openConnectModal} className="underline hover:text-[var(--text-main)] cursor-pointer">Log In</button> to view governance power
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
                                    <span>{PROPOSAL.votes.yes}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full bg-street-green w-[60%] rounded-full"></div>
                                </div>
                            </div>

                            <div className="space-y-1">
                                <div className="flex justify-between text-xs text-[var(--text-main)]">
                                    <span>No</span>
                                    <span>{PROPOSAL.votes.no}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full street-red w-[20%] rounded-full"></div>
                                </div>
                            </div>

                            <div className="space-y-1">
                                <div className="flex justify-between text-xs text-[var(--text-main)]">
                                    <span>Abstain</span>
                                    <span>{PROPOSAL.votes.abstain}%</span>
                                </div>
                                <div className="h-1.5 w-full bg-[var(--surface-highlight)] rounded-full overflow-hidden">
                                    <div className="h-full bg-street-muted/30 w-[20%] rounded-full"></div>
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
                                    <p className="text-[10px] text-street-muted">{PROPOSAL.created}</p>
                                </div>
                            </div>
                            <div className="flex gap-4 relative">
                                <div className="w-2.5 h-2.5 rounded-full bg-street-green mt-1.5 relative z-10 shadow-[0_0_8px_#00C957]"></div>
                                <div>
                                    <p className="text-xs text-[var(--text-main)] font-medium">Active</p>
                                    <p className="text-[10px] text-street-muted">Voting Period</p>
                                </div>
                            </div>
                            <div className="flex gap-4 relative">
                                <div className="w-2.5 h-2.5 rounded-full bg-[var(--surface-highlight)] mt-1.5 relative z-10 border border-[var(--border)]"></div>
                                <div>
                                    <p className="text-xs text-street-muted font-medium">Ends</p>
                                    <p className="text-[10px] text-street-muted">{PROPOSAL.ends}</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

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