'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
// Added Globe to the imports
import { 
  ArrowLeft, 
  Lock as LockIcon, 
  Twitter,
  Globe 
} from 'lucide-react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';
import { useAccount } from 'wagmi';

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

const REQUIRED_STAKE = 50000;

export default function WriteProposalPage() {
  const { isConnected } = useAccount();
  const currentTheme = useThemeObserver();
  
  // Form State
  const [formData, setFormData] = useState({
    title: '',
    tldr: '',
    author: '',
    twitter: '', 
    body: ''
  });

  // Draft Saving Logic
  useEffect(() => {
    const savedDraft = localStorage.getItem('street_proposal_draft');
    if (savedDraft) {
      try {
        setFormData(JSON.parse(savedDraft));
      } catch (e) {
        console.error("Failed to load draft", e);
      }
    }
  }, []);

  useEffect(() => {
    const handler = setTimeout(() => {
      localStorage.setItem('street_proposal_draft', JSON.stringify(formData));
    }, 1000);
    return () => clearTimeout(handler);
  }, [formData]);

  const wordCount = formData.tldr.trim().split(/\s+/).filter(Boolean).length;

  return (
    <main className="min-h-screen flex flex-col font-sans bg-street-background text-[var(--text-main)] selection:bg-[#FD7DEC] selection:text-black relative transition-colors duration-300">
      
      {/* NAVBAR */}
      <nav className="w-full border-b street-border sticky top-0 z-40 bg-street-background/90 backdrop-blur-md">
          <div className="max-w-[1100px] mx-auto px-8 py-4 flex justify-between items-center">
              <div className="flex items-center gap-3">
                  {/* Dynamic Logo */}
                  <div className="relative h-8 w-32 flex items-center">
                    <img 
                        src="/street-logo2.png" 
                        alt="Street" 
                        className={`h-8 w-auto absolute left-0 top-0 transition-opacity duration-300 object-contain ${currentTheme === 'light' ? 'opacity-100' : 'opacity-0'}`} 
                    />
                    <img 
                        src="/street-logo.png" 
                        alt="Street" 
                        className={`h-8 w-auto absolute left-0 top-0 transition-opacity duration-300 object-contain ${currentTheme === 'dark' ? 'opacity-100' : 'opacity-0'}`}
                    />
                  </div>
              </div>
              <div className="flex items-center gap-4">
                  <div className="hidden md:flex items-center gap-2 px-3 py-1.5 bg-street-surface border street-border rounded-lg">
                        <LockIcon size={10} className="text-street-green" />
                        <span className="text-[10px] font-mono text-street-green">{REQUIRED_STAKE.toLocaleString()} KLED STAKED</span>
                  </div>
                  <div className="h-6 w-[1px] bg-street-border mx-2"></div>
                  <Link href="/projects/kled">
                      <button className="px-4 py-2 text-street-muted text-xs hover:text-[var(--text-main)] transition">
                          Cancel
                      </button>
                  </Link>
                  <ThemeToggle />
                  <button className="street-gradient-bg text-black px-5 py-2 rounded-lg text-xs font-bold hover:opacity-90 transition shadow-lg">
                      Publish Proposal
                  </button>
              </div>
          </div>
      </nav>

      {/* MAIN CONTENT */}
      <div className="max-w-[640px] mx-auto w-full px-6 py-12 flex-1">
          
          <div className="space-y-5">
              
              {/* 1. TITLE CARD */}
              <div className="bg-street-surface border street-border rounded-xl p-5 shadow-sm transition-all focus-within:border-street-muted">
                  <label className="block text-[9px] font-mono text-street-muted uppercase tracking-widest mb-3 flex items-center gap-2">
                      <span className="w-1 h-1 bg-street-green rounded-full"></span> Proposal Title
                  </label>
                  <input 
                      type="text" 
                      placeholder="Enter a descriptive title..." 
                      className="w-full bg-transparent text-xl font-serif text-[var(--text-main)] placeholder-street-muted focus:outline-none transition-colors"
                      value={formData.title}
                      onChange={(e) => setFormData({...formData, title: e.target.value})}
                      autoFocus
                  />
              </div>

              {/* 2. TL;DR CARD */}
              <div className="bg-street-surface border street-border rounded-xl p-5 shadow-sm transition-all focus-within:border-street-muted">
                  <div className="flex justify-between items-center mb-3">
                      <label className="block text-[9px] font-mono text-street-muted uppercase tracking-widest">TL;DR (Abstract)</label>
                      <span className={`text-[9px] font-mono ${wordCount > 100 ? 'text-street-red' : 'text-street-muted'}`}>
                          {wordCount} / 100 Words
                      </span>
                  </div>
                  <textarea 
                      rows={2}
                      placeholder="Summarize your proposal in under 100 words..." 
                      className="w-full bg-transparent text-xs text-[var(--text-main)] focus:outline-none leading-relaxed resize-none placeholder-street-muted"
                      value={formData.tldr}
                      onChange={(e) => setFormData({...formData, tldr: e.target.value})}
                  />
              </div>

              {/* 3. AUTHOR & TWITTER ROW */}
              <div className="grid grid-cols-2 gap-4">
                  {/* Author */}
                  <div className="bg-street-surface border street-border rounded-xl p-4 shadow-sm flex flex-col justify-center transition-all focus-within:border-street-muted">
                      <label className="block text-[9px] font-mono text-street-muted uppercase tracking-widest mb-2">Author / ENS</label>
                      <div className="flex items-center gap-3">
                          <div className="h-6 w-6 rounded bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-bold text-[10px]">
                              Y
                          </div>
                          <input 
                              type="text" 
                              placeholder="Name or ENS" 
                              className="bg-transparent flex-1 text-xs text-[var(--text-main)] focus:outline-none font-mono placeholder-street-muted"
                              value={formData.author}
                              onChange={(e) => setFormData({...formData, author: e.target.value})}
                          />
                      </div>
                  </div>

                  {/* Twitter Link */}
                  <div className="bg-street-surface border street-border rounded-xl p-4 shadow-sm flex flex-col justify-center transition-all focus-within:border-street-muted">
                      <label className="block text-[9px] font-mono text-street-muted uppercase tracking-widest mb-2">Twitter / X Link</label>
                      <div className="flex items-center gap-3">
                          <div className="h-6 w-6 rounded bg-street-background border street-border flex items-center justify-center text-street-muted">
                              <Twitter size={10}/>
                          </div>
                          <input 
                              type="text" 
                              placeholder="@username" 
                              className="bg-transparent flex-1 text-xs text-[var(--text-main)] focus:outline-none font-mono placeholder-street-muted"
                              value={formData.twitter}
                              onChange={(e) => setFormData({...formData, twitter: e.target.value})}
                          />
                      </div>
                  </div>
              </div>

              {/* 4. DETAILS CARD */}
              <div className="bg-street-surface border street-border rounded-xl p-6 shadow-sm h-auto transition-all focus-within:border-street-muted">
                  <label className="block text-[9px] font-mono text-street-muted uppercase tracking-widest mb-4">Proposal Details</label>
                  <textarea 
                      placeholder="Write your full proposal here. Include goals, reasoning, and precedents..." 
                      className="w-full min-h-[400px] bg-transparent text-xs text-[var(--text-main)] placeholder-street-muted focus:outline-none leading-6 font-sans resize-y"
                      value={formData.body}
                      onChange={(e) => setFormData({...formData, body: e.target.value})}
                  />
              </div>

          </div>
      </div>

      {/* FOOTER */}
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