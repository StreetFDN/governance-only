'use client';

import { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import {
  ArrowLeft,
  ArrowRight,
  TrendingUp,
  TrendingDown,
  Clock,
  DollarSign,
  BarChart3,
  Twitter,
  Globe,
  Loader2,
  AlertTriangle,
} from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { useAccount, useSwitchChain } from 'wagmi';
import {
  useUserGovernance,
  useChainCheck,
  REQUIRED_CHAIN_ID,
  formatKled,
} from '@/app/hooks/useGovernance';
import {
  useAllFutarchyProposals,
  useTreasuryBalance,
  useFutarchyProposalStake,
  formatTimeRemaining,
  formatPriceAsPercent,
} from '@/app/hooks/useFutarchyTreasury';
import { getContracts } from '@/app/config/contracts';

const contracts = getContracts();

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

// Sparkline component for price charts
const Sparkline = ({ data, colorClass }: { data: number[], colorClass: string }) => {
  if (!data || data.length === 0) return null;

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


export default function TreasuryPage() {
  const { isConnected, address } = useAccount();
  const { switchChain } = useSwitchChain();
  const currentTheme = useThemeObserver();
  const [mounted, setMounted] = useState(false);

  // Governance data
  const { formattedVotingPower, isLoading: isGovernanceLoading } = useUserGovernance();
  const { isCorrectNetwork, requiredChainName } = useChainCheck();

  // Futarchy proposals - from FutarchyTreasury contract
  const { proposals: futarchyProposals, count: futarchyCount, isLoading: isProposalsLoading } = useAllFutarchyProposals();

  // Treasury balance
  const { data: treasuryBalance } = useTreasuryBalance(contracts.kledToken);

  // Proposal stake requirement
  const { data: proposalStake } = useFutarchyProposalStake();

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) return null;

  return (
    <main className="min-h-screen flex flex-col font-sans bg-street-background text-[var(--text-main)] selection:bg-[#FD7DEC] selection:text-black transition-colors duration-300">

      {/* --- NAVIGATION --- */}
      <nav className="w-full border-b street-border bg-street-background/90 backdrop-blur-md sticky top-0 z-40">
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
            <Link href="/projects/kled">
              <button className="px-4 py-2 rounded-lg border street-border text-street-muted text-xs hover:bg-[var(--surface-highlight)] transition flex items-center gap-2">
                <ArrowLeft size={14} /> Back to Dashboard
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

      {/* --- HEADER --- */}
      <section className="py-12 text-center border-b street-border">
        <h1 className="text-5xl font-serif text-[var(--text-main)] mb-4">Futarchy Treasury</h1>
        <p className="text-street-muted text-sm max-w-xl mx-auto">
          Market-driven treasury decisions. Trade on proposal outcomes to signal your prediction.
          The market decides which proposals are beneficial for the protocol.
        </p>
      </section>

      {/* --- MAIN CONTENT --- */}
      <div className="max-w-[1100px] mx-auto w-full px-8 py-12 flex-1">

        {/* Network Warning */}
        {isConnected && !isCorrectNetwork && (
          <div className="mb-8 p-4 bg-street-red/10 border border-street-red/30 rounded-xl flex items-center justify-between">
            <div className="flex items-center gap-3">
              <AlertTriangle className="text-street-red" size={20} />
              <p className="text-sm text-street-red">Wrong network. Please switch to {requiredChainName}</p>
            </div>
            <button
              onClick={() => switchChain?.({ chainId: REQUIRED_CHAIN_ID })}
              className="px-4 py-2 bg-street-red/20 text-street-red rounded-lg text-xs font-bold hover:bg-street-red/30 transition"
            >
              Switch Network
            </button>
          </div>
        )}

        {/* Stats Row */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
          <div className="bg-street-surface border street-border rounded-xl p-6">
            <div className="flex items-center gap-2 text-street-muted mb-2">
              <DollarSign size={16} />
              <span className="text-xs uppercase tracking-wider font-bold">Treasury Balance</span>
            </div>
            <p className="text-2xl font-serif text-[var(--text-main)]">
              {treasuryBalance ? `${Number(formatKled(treasuryBalance as bigint)).toLocaleString()} KLED` : '0 KLED'}
            </p>
          </div>
          <div className="bg-street-surface border street-border rounded-xl p-6">
            <div className="flex items-center gap-2 text-street-muted mb-2">
              <BarChart3 size={16} />
              <span className="text-xs uppercase tracking-wider font-bold">Active Markets</span>
            </div>
            <p className="text-2xl font-serif text-[var(--text-main)]">
              {futarchyProposals.filter(p => p.status === 'active').length}
            </p>
          </div>
          <div className="bg-street-surface border street-border rounded-xl p-6">
            <div className="flex items-center gap-2 text-street-muted mb-2">
              <TrendingUp size={16} />
              <span className="text-xs uppercase tracking-wider font-bold">Total Proposals</span>
            </div>
            <p className="text-2xl font-serif text-[var(--text-main)]">{futarchyCount}</p>
          </div>
          <div className="bg-street-surface border street-border rounded-xl p-6">
            <div className="flex items-center gap-2 text-street-muted mb-2">
              <Clock size={16} />
              <span className="text-xs uppercase tracking-wider font-bold">Your Power</span>
            </div>
            <p className="text-2xl font-serif text-[var(--text-main)]">
              {isGovernanceLoading ? '...' : `${Number(formattedVotingPower).toLocaleString()} KLED`}
            </p>
          </div>
        </div>

        {/* Proposals List */}
        <div className="space-y-6">
          <div className="flex justify-between items-center">
            <h2 className="text-2xl font-serif text-[var(--text-main)]">Treasury Proposals</h2>
            <button className="border street-border rounded-lg px-4 py-2 text-xs text-[var(--text-main)] font-bold hover:bg-[var(--surface-highlight)] transition flex items-center gap-2">
              Create Proposal <ArrowRight size={12} className="-rotate-45" />
            </button>
          </div>

          {isProposalsLoading ? (
            <div className="flex items-center justify-center py-16">
              <Loader2 className="animate-spin text-street-muted" size={32} />
            </div>
          ) : futarchyProposals.length === 0 ? (
            <div className="border-2 border-dashed street-border rounded-2xl p-12 text-center">
              <div className="w-16 h-16 rounded-full bg-street-surface border street-border mx-auto mb-6 flex items-center justify-center">
                <BarChart3 className="text-street-muted" size={24} />
              </div>
              <h3 className="text-xl font-serif text-[var(--text-main)] mb-2">No Active Markets</h3>
              <p className="text-sm text-street-muted max-w-md mx-auto mb-6">
                Futarchy treasury proposals will appear here once created.
                Each proposal creates prediction markets for YES and NO outcomes.
              </p>
              <p className="text-xs text-street-muted font-mono">
                Stake: {proposalStake ? `${formatKled(proposalStake as bigint)} KLED` : '...'} required to create a proposal
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {futarchyProposals.map((proposal) => (
                <div key={proposal.id.toString()} className="bg-street-surface border street-border rounded-2xl p-6">
                  <div className="flex justify-between items-start mb-4">
                    <span className={`text-[10px] font-bold tracking-widest uppercase flex items-center gap-2 ${
                      proposal.status === 'active' ? 'text-street-green' :
                      proposal.status === 'passed' || proposal.status === 'executed' ? 'text-street-green' :
                      'text-street-red'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${
                        proposal.status === 'active' ? 'bg-street-green animate-pulse' :
                        proposal.status === 'passed' || proposal.status === 'executed' ? 'bg-street-green' :
                        'bg-street-red'
                      }`}></span>
                      {proposal.status}
                    </span>
                    <span className="text-[10px] font-mono text-street-muted">
                      #{proposal.id.toString()} • {proposal.formattedAmount} KLED
                    </span>
                  </div>
                  <h3 className="text-lg font-serif text-[var(--text-main)] mb-2">{proposal.title}</h3>
                  <p className="text-xs text-street-muted mb-4 line-clamp-2">{proposal.description}</p>

                  {/* Market Prices */}
                  <div className="grid grid-cols-2 gap-4 mb-4">
                    <div className="bg-street-background rounded-lg p-3">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-[10px] text-street-green font-bold">PASS Market</span>
                        <span className="text-[10px] text-street-green font-mono">{formatPriceAsPercent(proposal.passPrice)}</span>
                      </div>
                      <div className="h-2 w-full bg-[var(--border)] rounded-full overflow-hidden">
                        <div className="h-full bg-street-green rounded-full" style={{ width: `${Number(proposal.passPrice) / 1e16}%` }}></div>
                      </div>
                    </div>
                    <div className="bg-street-background rounded-lg p-3">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-[10px] text-street-red font-bold">FAIL Market</span>
                        <span className="text-[10px] text-street-red font-mono">{formatPriceAsPercent(proposal.failPrice)}</span>
                      </div>
                      <div className="h-2 w-full bg-[var(--border)] rounded-full overflow-hidden">
                        <div className="h-full bg-street-red rounded-full" style={{ width: `${Number(proposal.failPrice) / 1e16}%` }}></div>
                      </div>
                    </div>
                  </div>

                  {/* Time remaining */}
                  <div className="text-[10px] text-street-muted font-mono mb-4 text-center">
                    {proposal.timeRemaining > 0 ? `Market ends in ${formatTimeRemaining(proposal.timeRemaining)}` : 'Market ended'}
                  </div>

                  {proposal.status === 'active' && proposal.timeRemaining > 0 ? (
                    <div className="flex gap-2">
                      <button className="flex-1 py-2 rounded-lg border border-street-green text-street-green text-xs font-bold hover:bg-street-green/10 transition">
                        Trade PASS
                      </button>
                      <button className="flex-1 py-2 rounded-lg border border-street-red text-street-red text-xs font-bold hover:bg-street-red/10 transition">
                        Trade FAIL
                      </button>
                    </div>
                  ) : proposal.resolved ? (
                    <div className={`text-center py-2 rounded-lg text-xs font-bold ${
                      proposal.passed ? 'bg-street-green/10 text-street-green' : 'bg-street-red/10 text-street-red'
                    }`}>
                      {proposal.passed ? 'Proposal Passed' : 'Proposal Failed'}
                      {proposal.executed && ' (Executed)'}
                    </div>
                  ) : (
                    <button className="w-full py-2 rounded-lg border street-border text-[var(--text-main)] text-xs font-bold hover:bg-[var(--surface-highlight)] transition">
                      Resolve Market
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* --- FOOTER --- */}
      <footer className="w-full border-t street-border bg-street-surface mt-auto relative z-10">
        <PhysicsFooter />
        <div className="max-w-[1100px] mx-auto px-8 py-12">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
            <div className="col-span-1 md:col-span-2 space-y-4">
              <div className="flex items-center gap-2">
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
                <li><Link href="/projects/kled" className="hover:text-[var(--text-main)] transition">Governance</Link></li>
                <li><Link href="/treasury" className="hover:text-[var(--text-main)] transition">Treasury</Link></li>
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
