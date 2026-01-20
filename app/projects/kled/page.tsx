'use client';

import { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Globe, Twitter, ShieldCheck, ArrowRight, FileText, Wallet, ExternalLink, Copy, CheckCircle2, AlertTriangle, ShieldAlert, Loader2, RefreshCw } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { useAccount, useSwitchChain } from 'wagmi';
import {
  useUserGovernance,
  useProposalCount,
  useProposal,
  useAllProposals,
  formatKled,
  useChainCheck,
  REQUIRED_CHAIN_ID,
  ProposalState,
  getProposalStateLabel,
  getProposalStatus,
  formatTimestamp,
  getTimeRemaining,
} from '@/app/hooks/useGovernance';
import {
  useAllFutarchyProposals,
  formatTimeRemaining,
  formatPriceAsPercent,
} from '@/app/hooks/useFutarchyTreasury';

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


// --- COMPONENTS ---

const Sparkline = ({ data, colorClass }: { data: number[], colorClass: string }) => {
    const min = Math.min(...data);
    const max = Math.max(...data);
    const range = max - min || 1;
    
    const points = data.map((val, i) => {
        const x = (i / (data.length - 1)) * 100;
        const y = 100 - ((val - min) / range) * 100;
        return `${x},${y}`;
    }).join(' ');

    return (
        <div className="w-full h-10 relative mt-1">
            <svg viewBox="0 0 100 100" className="w-full h-full overflow-visible" preserveAspectRatio="none">
                <polyline 
                    points={points} 
                    fill="none" 
                    stroke="currentColor" 
                    strokeWidth="2" 
                    vectorEffect="non-scaling-stroke"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    className={colorClass}
                />
            </svg>
        </div>
    );
};

const ExpandableText = ({ text }: { text: string }) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const toggle = () => setIsExpanded(!isExpanded);
  const shortText = text.length > 90 ? text.slice(0, 90) + "..." : text;

  return (
    <div className="space-y-2 mb-4">
      <p className="text-xs text-street-muted leading-relaxed">
        {isExpanded ? text : shortText}
      </p>
      {text.length > 90 && (
        <button 
          onClick={toggle}
          className="text-[10px] text-[var(--text-main)] font-bold uppercase tracking-wider hover:underline"
        >
          {isExpanded ? "READ LESS" : "READ MORE"}
        </button>
      )}
    </div>
  );
};

const REQUIRED_STAKE = 50000;

export default function KledDashboard() {
  const router = useRouter();
  const { isConnected, address } = useAccount();
  const { switchChain } = useSwitchChain();
  const [price, setPrice] = useState<string | null>(null);
  const [isReadMore, setIsReadMore] = useState(false);
  // UPDATED: State to handle "Show All" logic
  const [showAllPast, setShowAllPast] = useState(false);
  const [mounted, setMounted] = useState(false);
  const currentTheme = useThemeObserver();

  // --- GOVERNANCE HOOKS (Real Contract Data) ---
  const {
    formattedVotingPower,
    votingPower,
    isLoading: isGovernanceLoading,
    isCorrectNetwork,
    canCreateProposal
  } = useUserGovernance();
  const { isCorrectNetwork: networkOk, requiredChainName } = useChainCheck();

  // Fetch ALL proposals from chain
  const { proposals: allProposals, count: proposalCount, isLoading: isProposalsLoading } = useAllProposals();

  // Fetch ALL futarchy treasury proposals from chain
  const { proposals: futarchyProposals, count: futarchyCount, isLoading: isFutarchyLoading } = useAllFutarchyProposals();

  // Separate proposals by status
  const activeProposals = allProposals.filter(p => p.status === 'active');
  const pendingProposals = allProposals.filter(p => p.status === 'pending');
  const pastProposals = allProposals.filter(p => ['passed', 'failed', 'executed', 'canceled'].includes(p.status));

  // Get latest active or pending proposal for main display
  const latestProposal = activeProposals[0] || pendingProposals[0] || allProposals[0];

  // --- WIZARD STATE ---
  const [wizardStep, setWizardStep] = useState<number | null>(null);
  const [isStaking, setIsStaking] = useState(false);

  const CONTRACT_ADDRESS = "1zJX5gRnjLgmTpq5sVwkq69mNDQkCemqoasyjaPW6jm";

  useEffect(() => {
    setMounted(true);
    const fetchPrice = async () => {
      try {
        const response = await fetch(
          `https://api.dexscreener.com/latest/dex/tokens/${CONTRACT_ADDRESS}`
        );
        const data = await response.json();
        if (data.pairs && data.pairs.length > 0) {
            setPrice(parseFloat(data.pairs[0].priceUsd).toFixed(3));
        } else {
            setPrice("6.408"); 
        }
      } catch (error) {
        console.error("Failed to fetch price", error);
        setPrice("6.408");
      }
    };
    fetchPrice();
    const interval = setInterval(fetchPrice, 30000);
    return () => clearInterval(interval);
  }, []);

  // --- WIZARD HANDLERS ---
  const openWizard = () => setWizardStep(0);
  const closeWizard = () => setWizardStep(null);
  const nextStep = () => setWizardStep((prev) => (prev !== null ? prev + 1 : null));
  const prevStep = () => setWizardStep((prev) => (prev !== null ? prev - 1 : null));

  const handleStake = () => {
    setIsStaking(true);
    setTimeout(() => {
        setIsStaking(false);
        closeWizard();
        router.push('/proposals/write');
    }, 2000);
  };

  const fullDescription = "The first consumer data marketplace. Sourcing the largest licensable multimodal datasets on the planet.";
  const shortDescription = "The first consumer data marketplace. Sourcing the largest licensable...";

  return (
    <main className="min-h-screen flex flex-col font-sans bg-street-background text-[var(--text-main)] selection:bg-[#FD7DEC] selection:text-black relative transition-colors duration-300">
      
      {/* --- WIZARD MODALS (Keep existing wizard code) --- */}
      {wizardStep !== null && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/20 backdrop-blur-sm p-4 animate-in fade-in duration-300">
            <div className="w-full max-w-[400px] rounded-[1.5rem] overflow-hidden relative transition-all duration-300
                bg-white/60 backdrop-blur-3xl backdrop-saturate-150
                border border-white/40 
                shadow-[0_20px_40px_rgba(0,0,0,0.1),inset_0_0_0_1px_rgba(255,255,255,0.5)]
                
                data-[theme=dark]:bg-black/60 
                data-[theme=dark]:backdrop-blur-3xl 
                data-[theme=dark]:backdrop-saturate-150
                data-[theme=dark]:border-white/10 
                data-[theme=dark]:shadow-[0_20px_40px_rgba(0,0,0,0.4),inset_0_0_0_1px_rgba(255,255,255,0.1)]"
            >
                {/* Step 0 */}
                {wizardStep === 0 && (
                    <div className="p-6 space-y-6">
                        <div className="flex items-center gap-3 mb-1">
                            <div className="p-2.5 rounded-full bg-white/40 data-[theme=dark]:bg-white/10 shadow-sm ring-1 ring-black/5 data-[theme=dark]:ring-white/5">
                                <FileText className="text-gray-700 data-[theme=dark]:text-white" size={20} />
                            </div>
                            <h2 className="text-xl font-serif text-gray-900 data-[theme=dark]:text-white">Proposal Guidelines</h2>
                        </div>
                        <p className="text-xs text-gray-600 data-[theme=dark]:text-white/70 leading-relaxed">
                            The Board demands clarity. Before you draft, acknowledge the following standards.
                        </p>
                        <ul className="space-y-3 border-y border-black/5 data-[theme=dark]:border-white/10 py-4">
                            <li className="flex gap-3 items-start text-xs text-gray-700 data-[theme=dark]:text-[#EAEAEA]">
                                <CheckCircle2 className="text-street-green shrink-0 mt-0.5 drop-shadow-sm" size={14}/>
                                <span className="leading-relaxed"><strong>Clear Goal:</strong> Define exactly what this proposal aims to achieve.</span>
                            </li>
                            <li className="flex gap-3 items-start text-xs text-gray-700 data-[theme=dark]:text-[#EAEAEA]">
                                <CheckCircle2 className="text-street-green shrink-0 mt-0.5 drop-shadow-sm" size={14}/>
                                <span className="leading-relaxed"><strong>Reasoning:</strong> Provide data-backed rationale. "I think" is not valid.</span>
                            </li>
                            <li className="flex gap-3 items-start text-xs text-gray-700 data-[theme=dark]:text-[#EAEAEA]">
                                <CheckCircle2 className="text-street-green shrink-0 mt-0.5 drop-shadow-sm" size={14}/>
                                <span className="leading-relaxed"><strong>Precedents:</strong> Cite examples or previous discussions.</span>
                            </li>
                        </ul>
                        <div className="flex gap-3">
                            <button onClick={closeWizard} className="px-5 py-3 rounded-lg text-[10px] font-bold text-gray-500 data-[theme=dark]:text-white/60 hover:text-gray-900 data-[theme=dark]:hover:text-white transition uppercase tracking-widest hover:bg-black/5 data-[theme=dark]:hover:bg-white/10">
                                Cancel
                            </button>
                            <button onClick={nextStep} className="flex-1 py-3 bg-black/90 data-[theme=dark]:bg-white text-white data-[theme=dark]:text-black text-[10px] font-bold uppercase tracking-widest rounded-lg hover:scale-[1.02] active:scale-[0.98] transition shadow-lg">
                                I Understand & Accept
                            </button>
                        </div>
                    </div>
                )}
                {/* Step 1 */}
                {wizardStep === 1 && (
                    <div className="p-6 space-y-6">
                        <div className="flex items-center gap-3 mb-1">
                            <div className="p-2.5 rounded-full bg-yellow-500/10 border border-yellow-500/20 shadow-sm">
                                <AlertTriangle className="text-yellow-600 data-[theme=dark]:text-yellow-500" size={20} />
                            </div>
                            <h2 className="text-xl font-serif text-gray-900 data-[theme=dark]:text-white">Quality Assurance</h2>
                        </div>
                        <p className="text-xs text-gray-600 data-[theme=dark]:text-white/70 leading-relaxed">
                            Street is not a playground. Board proposals must be high-quality, executable, and beneficial to the SPV.
                        </p>
                        <div className="bg-white/40 data-[theme=dark]:bg-white/5 border border-white/50 data-[theme=dark]:border-white/10 p-4 rounded-xl space-y-2 shadow-sm">
                            <h4 className="text-[10px] font-bold text-gray-900 data-[theme=dark]:text-white uppercase tracking-wider">The Filter</h4>
                            <p className="text-[10px] text-gray-500 data-[theme=dark]:text-white/50 leading-relaxed">
                                If your proposal is deemed "Spam" or "Low Quality" by the initial filter, it will be summarily dismissed.
                            </p>
                        </div>
                        <div className="flex gap-3 pt-2">
                            <button onClick={prevStep} className="flex-1 py-3 border border-black/5 data-[theme=dark]:border-white/10 bg-white/20 data-[theme=dark]:bg-white/5 text-gray-600 data-[theme=dark]:text-white/70 text-[10px] font-bold uppercase tracking-widest rounded-lg hover:bg-white/40 data-[theme=dark]:hover:bg-white/10 transition">
                                Back
                            </button>
                            <button onClick={nextStep} className="flex-1 py-3 bg-black/90 data-[theme=dark]:bg-white text-white data-[theme=dark]:text-black text-[10px] font-bold uppercase tracking-widest rounded-lg hover:scale-[1.02] active:scale-[0.98] transition shadow-lg">
                                Proceed
                            </button>
                        </div>
                    </div>
                )}
                {/* Step 2 */}
                {wizardStep === 2 && (
                    <div className="relative">
                        <div className="absolute top-0 left-0 right-0 h-[3px] bg-gradient-to-r from-blue-200/40 via-white/80 to-blue-200/40 opacity-90 blur-[1px]"></div>
                        <div className="p-6 space-y-5">
                            <div className="text-center space-y-1 pb-2 pt-2">
                                <h2 className="text-2xl font-serif text-gray-900 data-[theme=dark]:text-white">Skin in the Game.</h2>
                                <p className="text-[10px] text-gray-400 data-[theme=dark]:text-white/40 uppercase tracking-widest font-bold">Or shut the f*** up.</p>
                            </div>
                            <div className="space-y-3">
                                <div className="flex justify-between items-center p-4 bg-white/40 data-[theme=dark]:bg-white/5 border border-white/50 data-[theme=dark]:border-white/10 rounded-xl shadow-sm">
                                    <span className="text-[10px] text-gray-500 data-[theme=dark]:text-white/60 font-bold uppercase tracking-wider">Required Stake (0.5%)</span>
                                    <span className="font-mono text-gray-900 data-[theme=dark]:text-white text-xs font-bold">{REQUIRED_STAKE.toLocaleString()} KLED</span>
                                </div>
                                <div className="p-4 bg-street-red/5 border border-street-red/10 rounded-xl space-y-2 shadow-inner">
                                    <div className="flex items-center gap-2 text-street-red font-bold text-[10px] uppercase tracking-wider">
                                        <AlertTriangle size={12} /> Slashing Risk
                                    </div>
                                    <p className="text-[10px] text-street-red/80 leading-relaxed font-medium">
                                        If this proposal fails the vote, <span className="font-bold text-street-red">10%</span> of your stake ({REQUIRED_STAKE * 0.1} KLED) will be burned.
                                    </p>
                                </div>
                            </div>
                            <div className="pt-1 space-y-2">
                                {!isConnected ? (
                                    <ConnectButton.Custom>
                                        {({ openConnectModal }) => (
                                            <button onClick={openConnectModal} className="w-full py-3 bg-black/5 data-[theme=dark]:bg-white/10 hover:bg-black/10 data-[theme=dark]:hover:bg-white/20 border border-black/5 data-[theme=dark]:border-white/10 text-gray-900 data-[theme=dark]:text-white text-xs font-bold rounded-lg transition uppercase tracking-widest">
                                                Connect Wallet to Stake
                                            </button>
                                        )}
                                    </ConnectButton.Custom>
                                ) : (
                                    <button 
                                        onClick={handleStake} 
                                        disabled={isStaking}
                                        className="w-full py-3 bg-gradient-to-r from-blue-50 to-blue-100 hover:from-blue-100 hover:to-blue-200 text-blue-950 text-[10px] font-bold uppercase tracking-widest rounded-lg transition shadow-[0_4px_15px_rgba(59,130,246,0.15)] flex items-center justify-center gap-2 transform hover:scale-[1.02] active:scale-[0.98] border border-blue-200/50"
                                    >
                                        {isStaking ? (
                                            <>Processing Transaction <Loader2 className="animate-spin ml-2" size={14}/></>
                                        ) : (
                                            <>Confirm Stake & Write <Wallet size={14}/></>
                                        )}
                                    </button>
                                )}
                                <button onClick={prevStep} className="w-full text-center text-[10px] text-gray-400 hover:text-gray-600 data-[theme=dark]:text-white/40 data-[theme=dark]:hover:text-white transition pt-1">
                                    Go Back
                                </button>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
      )}

      {/* --- Navigation --- */}
      <nav className="w-full border-b street-border">
        <div className="max-w-[1100px] mx-auto px-8 py-4 flex justify-between items-center">
            <div className="flex items-center gap-3">
               <div className="relative h-8 w-32 flex items-center">
                 {currentTheme === 'light' ? (
                    <img src="/street-logo2.png" alt="Street" className="h-8 w-auto object-contain" />
                 ) : (
                    <img src="/street-logo.png" alt="Street" className="h-8 w-auto object-contain" />
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

      {/* --- Hero Section --- */}
      <section className="py-20 flex flex-col items-center text-center space-y-1">
        <h1 className="text-7xl font-serif font-medium tracking-tight text-[var(--text-main)]">
          Kled AI, Inc.
        </h1>
        <p className="text-3xl font-serif text-[var(--text-main)]">
          Govern this SPV
        </p>
        <div className="pt-4 flex flex-col items-center gap-4">
          <span className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-street-surface border street-border text-xs text-street-muted font-medium">
            <span className="w-2 h-2 rounded-full bg-street-green shadow-[0_0_8px_#00C957]"></span>
            Live
          </span>
          <ConnectButton.Custom>
            {({ account, openConnectModal }) => (
                <span className="text-street-muted text-sm font-mono">
                {account ? (
                    !networkOk ? (
                        <span className="flex items-center gap-2">
                            Wrong network.
                            <button
                                onClick={() => switchChain?.({ chainId: REQUIRED_CHAIN_ID })}
                                className="text-[var(--text-main)] underline hover:text-[#FD7DEC] transition cursor-pointer"
                            >
                                Switch to {requiredChainName}
                            </button>
                        </span>
                    ) : isGovernanceLoading ? (
                        <span className="flex items-center gap-2">
                            <Loader2 className="animate-spin" size={14} />
                            Loading governance power...
                        </span>
                    ) : (
                        <span>Your Governance Power is <span className="text-street-green">{Number(formattedVotingPower).toLocaleString()} KLED</span></span>
                    )
                ) : (
                    <>
                        Please <button onClick={openConnectModal} type="button" className="text-[var(--text-main)] underline hover:text-[#FD7DEC] transition cursor-pointer">Log In</button> to view your governance power
                    </>
                )}
                </span>
            )}
          </ConnectButton.Custom>
        </div>
      </section>

      {/* --- Info Banner --- */}
      <div className="border-y street-border bg-[var(--surface-highlight)]/50 py-5 text-center">
        <p className="max-w-3xl mx-auto px-6 text-street-muted text-xs leading-relaxed">
          The $STARTUP token governs the proposals that can be directed to the board and the monetary flow of the SPV. 
          Every proceed that comes into the treasury of the SPV is governed by the STARTUP token. 
          Every proposal has to be voted on by the $STREET token. The $STREET token doesn't control either the flow nor proposals.
        </p>
      </div>

      {/* --- Main Grid Dashboard --- */}
      <div className="w-full max-w-[1100px] mx-auto border-l street-border">
        <div className="grid grid-cols-1 lg:grid-cols-3">
            
            {/* Column 1: Sidebar Info */}
            <div className="flex flex-col gap-8 p-8 border-r street-border">
                <div className="flex items-center gap-4">
                    <div className="w-16 h-16 rounded-full overflow-hidden border street-border flex-shrink-0 bg-white relative">
                         <img 
                            src="/kled-logo.png" 
                            alt="Kled AI" 
                            className="w-full h-full object-cover"
                            onError={(e) => {
                                e.currentTarget.style.display = 'none';
                                e.currentTarget.parentElement!.style.background = '#FF4D4D';
                            }} 
                         />
                    </div>
                    <h2 className="text-3xl font-serif text-[var(--text-main)] tracking-tight leading-none">Kled AI, Inc.</h2>
                </div>
                <div className="flex gap-3">
                    <div className="bg-street-surface border street-border rounded px-3 py-1 text-xs text-[var(--text-main)] font-mono flex items-center gap-2 min-w-[80px] justify-center">
                        {price ? `$${price}` : <span className="animate-pulse text-street-muted">...</span>} 
                        <ArrowRight size={10} className="-rotate-45 text-street-muted" />
                    </div>
                    <a href="https://dexscreener.com/solana/1zJX5gRnjLgmTpq5sVwkq69mNDQkCemqoasyjaPW6jm" target="_blank" rel="noreferrer" className="bg-street-surface border street-border rounded px-3 py-1 text-xs text-[var(--text-main)] font-mono hover:bg-[var(--surface-highlight)] transition flex items-center gap-2 hover:text-[var(--text-main)]">
                        BUY <ArrowRight size={10} className="-rotate-45" />
                    </a>
                </div>
                <div className="space-y-2">
                    <p className="text-xs text-street-muted leading-relaxed">
                        {isReadMore ? fullDescription : shortDescription}
                    </p>
                    <button 
                        onClick={() => setIsReadMore(!isReadMore)}
                        className="text-xs text-[var(--text-main)] font-mono hover:underline uppercase tracking-tight"
                    >
                        {isReadMore ? "Read less" : "Read more"}
                    </button>
                </div>
                <div className="flex flex-wrap gap-2">
                    {['X', 'GITHUB', 'DISCORD', 'WEBSITE', 'YOUTUBE'].map((label) => (
                        <a key={label} href="#" className="bg-street-surface border street-border rounded px-3 py-1.5 text-[10px] text-[var(--text-main)] font-medium flex items-center gap-1 hover:bg-[var(--surface-highlight)] hover:text-[var(--text-main)] transition">
                            {label} <ArrowRight size={8} className="-rotate-45 text-street-muted" />
                        </a>
                    ))}
                </div>
                <div className="space-y-3 border-t street-border pt-6">
                    <h3 className="text-xs font-bold text-[var(--text-main)] uppercase tracking-wide underline decoration-[var(--border)] underline-offset-4">
                        Startup x Street SPV
                    </h3>
                    <p className="text-xs text-street-muted leading-relaxed">
                        The Startup x Street SPV holds 20% equity inside Kled AI, Inc.
                    </p>
                    <a href="#" className="flex items-center gap-2 text-xs text-street-muted hover:text-[var(--text-main)] transition group">
                        <ShieldCheck size={14} className="text-street-muted group-hover:text-[var(--text-main)] transition"/>
                        <span className="underline decoration-[var(--border)] group-hover:decoration-[var(--text-main)] underline-offset-4 transition">External Audit</span>
                    </a>
                </div>
                <div className="mt-auto space-y-4 pt-4">
                    <div className="flex items-center justify-between group cursor-pointer">
                        <div className="flex items-center gap-3 text-[var(--text-main)]">
                            <div className="text-street-muted"><FileText size={14}/></div>
                            <span className="text-xs font-bold">Contract</span>
                        </div>
                        <div className="flex items-center gap-4">
                             <span className="text-xs text-street-muted font-mono group-hover:text-[var(--text-main)] transition" title={CONTRACT_ADDRESS}>
                                {CONTRACT_ADDRESS.slice(0,4)}...{CONTRACT_ADDRESS.slice(-4)}
                             </span>
                             <div className="flex gap-3 text-street-muted">
                                <Copy size={12} className="hover:text-[var(--text-main)] transition"/>
                                <ExternalLink size={12} className="hover:text-[var(--text-main)] transition"/>
                             </div>
                        </div>
                    </div>
                    <div className="flex items-center justify-between group cursor-pointer">
                         <div className="flex items-center gap-3 text-[var(--text-main)]">
                            <div className="text-street-muted"><Wallet size={14}/></div>
                            <span className="text-xs font-bold">Treasury</span>
                        </div>
                        <div className="flex items-center gap-4">
                             <span className="text-xs text-street-muted font-mono group-hover:text-[var(--text-main)] transition">Bxgk...9eBT</span>
                             <div className="flex gap-3 text-street-muted">
                                <Copy size={12} className="hover:text-[var(--text-main)] transition"/>
                                <ExternalLink size={12} className="hover:text-[var(--text-main)] transition"/>
                             </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* Column 2: Board Proposals */}
            <div className="flex flex-col relative border-r street-border bg-street-background">
                <div className="py-8 flex flex-col items-center">
                    <h2 className="text-4xl font-serif mb-4 tracking-tight text-[var(--text-main)]">Board Proposals</h2>
                </div>
                <div className="flex flex-col w-full px-6 gap-6 pb-8">
                    {/* 1. UPCOMING/PENDING PROPOSAL CARD - From Chain */}
                    {pendingProposals.length > 0 ? (
                        <div className="w-full border street-border rounded-2xl p-6 bg-street-surface">
                            <div className="flex items-center justify-between mb-6">
                                <span className="text-[10px] font-bold text-street-muted tracking-widest uppercase flex items-center gap-2">
                                    <span className="w-2 h-2 rounded-full bg-street-muted"></span> Upcoming
                                </span>
                                <span className="text-[10px] font-mono text-street-muted">
                                    #{pendingProposals[0].id.toString()}
                                </span>
                            </div>
                            <h3 className="text-2xl font-serif text-[var(--text-main)] mb-4 leading-tight">
                                {pendingProposals[0].title}
                            </h3>
                            <ExpandableText text={pendingProposals[0].description} />
                            <div className="mt-4 pt-4 border-t street-border flex justify-between items-center">
                                <span className="text-[10px] text-street-muted font-mono uppercase tracking-wider">
                                    Voting opens {formatTimestamp(pendingProposals[0].startTime)}
                                </span>
                                <Link href={`/proposals/edit?id=${pendingProposals[0].id}`}>
                                    <button className="border street-border rounded-lg px-4 py-2 text-[10px] text-[var(--text-main)] font-bold flex items-center gap-2 hover:bg-[var(--surface-highlight)] hover:text-[var(--text-main)] transition uppercase tracking-wider cursor-pointer">
                                        Edit <ArrowRight size={10} className="-rotate-45" />
                                    </button>
                                </Link>
                            </div>
                        </div>
                    ) : (
                        <div className="w-full border street-border border-dashed rounded-2xl p-6 bg-street-surface/50 text-center">
                            <p className="text-street-muted text-sm">No upcoming proposals</p>
                            <p className="text-street-muted text-xs mt-1">Create a new proposal to get started</p>
                        </div>
                    )}
                    {/* 2. LIVE PROPOSAL CARD - Real Contract Data */}
                    {isProposalsLoading ? (
                        <div className="w-full border street-border rounded-2xl p-6 bg-street-surface flex items-center justify-center min-h-[200px]">
                            <Loader2 className="animate-spin text-street-muted" size={24} />
                        </div>
                    ) : latestProposal ? (
                        <div className="w-full border street-border rounded-2xl p-6 bg-street-surface">
                            <div className="flex items-center justify-between mb-6">
                                <span className="text-[10px] font-bold text-street-green tracking-widest uppercase flex items-center gap-2">
                                    <span className="w-1.5 h-1.5 rounded-full bg-street-green animate-pulse"></span>
                                    {Number(latestProposal.endTime) * 1000 > Date.now() ? 'Live' : 'Ended'}
                                </span>
                                <span className="text-[10px] font-mono text-street-muted">
                                    #{latestProposal.id.toString()}
                                </span>
                            </div>
                            <h3 className="text-2xl font-serif text-[var(--text-main)] mb-4 leading-tight">
                                {latestProposal.title}
                            </h3>
                            <ExpandableText text={latestProposal.description} />
                            {(() => {
                                const totalVotes = latestProposal.forVotes + latestProposal.againstVotes + latestProposal.abstainVotes;
                                const forPercent = totalVotes > 0n ? Number((latestProposal.forVotes * 100n) / totalVotes) : 0;
                                const againstPercent = totalVotes > 0n ? Number((latestProposal.againstVotes * 100n) / totalVotes) : 0;
                                return (
                                    <div className="grid grid-cols-2 gap-4 mb-6">
                                        <div>
                                            <div className="flex justify-between mb-1">
                                                <span className="text-[10px] text-[var(--text-main)] font-bold">Yes</span>
                                                <span className="text-[10px] text-[#00C957] font-mono">{forPercent}%</span>
                                            </div>
                                            <div className="h-1 w-full bg-[var(--border)] rounded-full overflow-hidden">
                                                <div className="h-full street-green rounded-full" style={{ width: `${forPercent}%` }}></div>
                                            </div>
                                        </div>
                                        <div>
                                            <div className="flex justify-between mb-1 items-end">
                                                <span className="text-[10px] text-[var(--text-main)] font-bold">No</span>
                                                <span className="text-[10px] text-[#FF4D4D] font-mono">{againstPercent}%</span>
                                            </div>
                                            <div className="h-1 w-full bg-[var(--border)] rounded-full overflow-hidden">
                                                <div className="h-full street-red rounded-full" style={{ width: `${againstPercent}%` }}></div>
                                            </div>
                                        </div>
                                    </div>
                                );
                            })()}
                            <div className="pt-4 border-t street-border flex justify-between items-center gap-4">
                                <p className="text-[10px] text-street-muted font-mono uppercase tracking-wider leading-tight max-w-[60%]">
                                    {latestProposal.executed ? 'Executed' : latestProposal.canceled ? 'Canceled' : 'If passed forwarded to board'}
                                </p>
                                <Link href={`/proposals/vote?id=${latestProposal.id}`}>
                                    <button className="border street-border rounded-lg px-6 py-2 text-[10px] text-[var(--text-main)] font-bold flex items-center gap-2 hover:bg-[var(--surface-highlight)] hover:text-[var(--text-main)] transition uppercase tracking-wider whitespace-nowrap cursor-pointer">
                                        Vote Now <ArrowRight size={10} className="-rotate-45" />
                                    </button>
                                </Link>
                            </div>
                        </div>
                    ) : (
                        <div className="w-full border street-border rounded-2xl p-6 bg-street-surface text-center">
                            <p className="text-street-muted text-sm">No active proposals yet</p>
                            <p className="text-street-muted text-xs mt-2">Be the first to create one!</p>
                        </div>
                    )}
                    {/* 3. MAKE YOUR VOICE HEARD */}
                    <button 
                        onClick={openWizard} 
                        className="group relative w-full rounded-2xl p-[2px] street-animated-border-wrapper text-left active:scale-[0.98] transition-transform duration-200 cursor-pointer"
                    >
                        <div className="relative bg-street-surface rounded-2xl p-5 flex items-center justify-between h-full z-10">
                            <div className="space-y-1">
                                <h3 className="text-xl font-serif text-[var(--text-main)] italic leading-tight">
                                    Make your voice <span className="italic">heard</span>
                                </h3>
                                <p className="text-[10px] text-street-muted font-light tracking-wide leading-relaxed text-left">
                                    Write your own proposal and send it to the board
                                </p>
                            </div>
                            <ArrowRight className="text-[var(--text-main)] w-5 h-5 flex-shrink-0 transition-transform duration-300 group-hover:translate-x-1"/>
                        </div>
                    </button>
                    
                    {/* 4. PAST PROPOSALS - FROM CHAIN */}
                    <div className="space-y-3 mt-2">
                        <h4 className="text-sm font-serif text-street-muted text-center mb-2">
                            Past Proposals {pastProposals.length > 0 && <span className="text-[10px] text-street-muted">({pastProposals.length})</span>}
                        </h4>

                        {isProposalsLoading ? (
                            <div className="flex items-center justify-center py-8">
                                <Loader2 className="animate-spin text-street-muted" size={20} />
                            </div>
                        ) : pastProposals.length === 0 ? (
                            <div className="text-center py-6 text-street-muted text-xs">
                                No past proposals yet
                            </div>
                        ) : (
                            pastProposals.map((proposal, index) => {
                                // LOGIC: Only show the first one. Blur the second one. Hide the rest until expanded.
                                if (!showAllPast && index > 1) return null;
                                const isBlurred = !showAllPast && index === 1;
                                const statusLabel = proposal.status.toUpperCase();
                                const isPassed = proposal.status === 'passed' || proposal.status === 'executed';

                                return (
                                    <div key={proposal.id.toString()} className="relative">
                                        <div
                                            className={`bg-street-surface border street-border rounded-xl p-5 flex flex-col gap-4 transition-all duration-200 hover:border-street-muted/40
                                            ${isBlurred ? 'blur-sm opacity-50 select-none pointer-events-none' : ''}`}
                                        >
                                            <div className="flex justify-between items-start">
                                                <div className="flex items-center gap-2">
                                                    <img src="/kled-logo.png" alt="Kled AI" className="h-3 w-3 rounded-full" />
                                                    <span className="text-[10px] text-street-muted uppercase tracking-wider">
                                                        #{proposal.id.toString()} • {formatTimestamp(proposal.endTime)}
                                                    </span>
                                                </div>
                                                <span className={`text-[10px] font-bold px-2 py-0.5 rounded uppercase tracking-wider
                                                    ${isPassed ? 'text-street-green bg-[#00C957]/10' : 'text-street-red bg-[#FF4D4D]/10'}`}>
                                                    {statusLabel}
                                                </span>
                                            </div>
                                            <h4 className="text-lg font-serif text-[var(--text-main)] leading-tight">
                                                {proposal.title}
                                            </h4>
                                            <div className="flex justify-between items-center">
                                                <span className="text-[9px] text-street-muted font-mono">
                                                    {formatKled(proposal.forVotes)} For / {formatKled(proposal.againstVotes)} Against
                                                </span>
                                                <Link href={`/proposals/vote?id=${proposal.id}`}>
                                                    <button className="bg-street-surface border street-border rounded px-4 py-1.5 text-[10px] text-[var(--text-main)] font-medium hover:bg-[var(--surface-highlight)] hover:text-[var(--text-main)] transition flex items-center gap-2">
                                                        View <ArrowRight size={10} className="-rotate-45 text-street-muted" />
                                                    </button>
                                                </Link>
                                            </div>
                                        </div>

                                        {/* "SEE ALL" BUTTON OVERLAY */}
                                        {isBlurred && (
                                            <div className="absolute inset-0 z-20 flex items-center justify-center">
                                                <button
                                                    onClick={() => setShowAllPast(true)}
                                                    className="bg-street-background border street-border text-[var(--text-main)] px-6 py-2 rounded-full text-xs font-bold uppercase tracking-wider hover:bg-[var(--surface-highlight)] hover:scale-105 transition-all shadow-2xl cursor-pointer z-30"
                                                >
                                                    See All
                                                </button>
                                            </div>
                                        )}
                                    </div>
                                );
                            })
                        )}

                        {/* OPTIONAL: Collapse Button if expanded */}
                        {showAllPast && pastProposals.length > 2 && (
                            <div className="text-center pt-2">
                                <button
                                    onClick={() => setShowAllPast(false)}
                                    className="text-[10px] text-street-muted hover:text-[var(--text-main)] uppercase tracking-wider underline"
                                >
                                    Collapse
                                </button>
                            </div>
                        )}
                    </div>
                </div>
            </div>

            {/* Column 3: Treasury & Distribution - FUTARCHY INTEGRATION */}
            <div className="flex flex-col border-r street-border">
                {/* TREASURY PROPOSALS SECTION - Real Contract Data */}
                <div className="p-8 border-b street-border flex flex-col items-center text-center">
                    <h2 className="text-4xl font-serif mb-6 text-[var(--text-main)]">Futarchy Treasury</h2>
                    <div className="w-full space-y-4">
                        {isFutarchyLoading ? (
                            <div className="flex items-center justify-center py-8">
                                <Loader2 className="animate-spin text-street-muted" size={24} />
                            </div>
                        ) : futarchyProposals.length === 0 ? (
                            <div className="bg-street-surface border street-border border-dashed rounded-xl p-6 text-center">
                                <p className="text-street-muted text-sm mb-2">No treasury proposals yet</p>
                                <Link href="/treasury">
                                    <button className="text-[10px] font-bold text-[var(--text-main)] uppercase tracking-wider flex items-center gap-1 hover:opacity-70 transition mx-auto">
                                        Create Proposal <ArrowRight size={10} className="-rotate-45" />
                                    </button>
                                </Link>
                            </div>
                        ) : (
                            futarchyProposals.map((prop) => (
                                <div key={prop.id.toString()} className="bg-street-surface border street-border rounded-xl p-4 text-left hover:border-street-muted/40 transition-all">
                                    <div className="flex justify-between items-start mb-3">
                                        <div className="space-y-1">
                                            <h3 className="text-sm font-serif text-[var(--text-main)] leading-tight">{prop.title}</h3>
                                            <div className="flex items-center gap-2 text-[10px] text-street-muted">
                                                <span className={`uppercase font-bold tracking-wider ${
                                                    prop.status === 'active' ? 'text-street-green' :
                                                    prop.status === 'passed' || prop.status === 'executed' ? 'text-street-green' :
                                                    'text-street-red'
                                                }`}>{prop.status}</span>
                                                <span>•</span>
                                                <span>Amt: {prop.formattedAmount} KLED</span>
                                            </div>
                                        </div>
                                    </div>
                                    <div className="space-y-3">
                                        <div className="space-y-1">
                                            <div className="flex justify-between text-[9px] font-bold uppercase tracking-wider text-street-green">
                                                <span>Pass Price</span>
                                                <span>{formatPriceAsPercent(prop.passPrice)}</span>
                                            </div>
                                            <div className="h-2 w-full bg-[var(--border)] rounded-full overflow-hidden">
                                                <div className="h-full bg-street-green rounded-full" style={{ width: `${Number(prop.passPrice) / 1e16}%` }}></div>
                                            </div>
                                        </div>
                                        <div className="space-y-1 pt-1">
                                            <div className="flex justify-between text-[9px] font-bold uppercase tracking-wider text-street-red">
                                                <span>Fail Price</span>
                                                <span>{formatPriceAsPercent(prop.failPrice)}</span>
                                            </div>
                                            <div className="h-2 w-full bg-[var(--border)] rounded-full overflow-hidden">
                                                <div className="h-full bg-street-red rounded-full" style={{ width: `${Number(prop.failPrice) / 1e16}%` }}></div>
                                            </div>
                                        </div>
                                    </div>
                                    <div className="mt-4 pt-3 border-t street-border flex justify-between items-center">
                                        <span className="text-[9px] text-street-muted font-mono">
                                            {prop.timeRemaining > 0 ? `${formatTimeRemaining(prop.timeRemaining)} left` : 'Market ended'}
                                        </span>
                                        <Link href={`/treasury?id=${prop.id}`}>
                                            <button className="text-[10px] font-bold text-[var(--text-main)] uppercase tracking-wider flex items-center gap-1 hover:opacity-70 transition">
                                                View Market <ArrowRight size={10} className="-rotate-45" />
                                            </button>
                                        </Link>
                                    </div>
                                </div>
                            ))
                        )}
                    </div>
                </div>
                {/* Distribution Proposals */}
                <div className="p-8 border-b street-border flex flex-col items-center text-center">
                    <h2 className="text-3xl font-serif mb-6 text-[var(--text-main)]">Distribution Proposals</h2>
                    <div className="text-left w-full space-y-4">
                         <p className="text-xs text-street-muted leading-relaxed">
                            No Distribution to be made at this point. For more information visit the <span className="underline cursor-pointer hover:text-black data-[theme=dark]:hover:text-white">Distribution Policy</span> and the ERC-S whitepaper.
                        </p>
                        <p className="text-xs text-street-muted leading-relaxed">
                            Auto-Pause Function: The Auto Pause Function occurs at any dispute between two parties (OpCo, Street Labs, Tokenholders or a regulatory inquiry.
                        </p>
                    </div>
                </div>
                <div className="p-8 flex flex-col items-center text-center">
                    <h2 className="text-3xl font-serif mb-6 text-[var(--text-main)]">Capital Reallocation Proposal</h2>
                    <div className="text-left w-full">
                        <p className="text-xs text-street-muted leading-relaxed">
                            No Capital Reallocation to be made at this point. For more information visit the Distribution Policy.
                        </p>
                    </div>
                </div>
            </div>

        </div>
      </div>

      {/* --- FOOTER (FIXED) --- */}
      <footer className="w-full border-t street-border bg-street-surface mt-auto relative z-10 transition-colors">
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
                        Street turns private equity into liquid, programmable digital assets through the ERC-S standard.
                     </p>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-[var(--text-main)] uppercase tracking-wider">Platform</h4>
                     <ul className="space-y-2 text-xs text-street-muted">
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Governance</a></li>
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Treasury</a></li>
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Documentation</a></li>
                     </ul>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-[var(--text-main)] uppercase tracking-wider">Legal</h4>
                     <ul className="space-y-2 text-xs text-street-muted">
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Terms of Service</a></li>
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Privacy Policy</a></li>
                        <li><a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">Cookie Policy</a></li>
                     </ul>
                  </div>
              </div>
              <div className="pt-8 border-t street-border flex flex-col md:flex-row justify-between items-center gap-4">
                  <p className="text-[10px] text-street-muted">© 2025 Street Protocol. All rights reserved.</p>
                  <div className="flex gap-6 text-street-muted">
                      <a href="https://x.com/StreetFDN" target="_blank" rel="noreferrer" className="hover:text-black data-[theme=dark]:hover:text-white transition">
                          <Twitter size={16} />
                      </a>
                      <a href="#" className="hover:text-black data-[theme=dark]:hover:text-white transition">
                          <Globe size={16} />
                      </a>
                  </div>
              </div>
          </div>
      </footer>
    </main>
  );
}