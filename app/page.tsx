'use client';

import { useState, useEffect } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Search, ArrowRight, TrendingUp, Users, Twitter, Globe, Loader2 } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import PhysicsFooter from '@/components/PhysicsFooter';
import ThemeToggle from '@/components/ThemeToggle';

// Mock Data for Projects (SPVs)
const PROJECTS = [
  {
    id: "kled",
    name: "Kled AI, Inc.",
    ticker: "KLED",
    logo: "/kled-logo.png",
    description: "The first consumer data marketplace. Sourcing the largest licensable multimodal datasets on the planet.",
    status: "LIVE",
    treasury: "$2.4M",
    members: 1240,
    proposals: 12,
    tags: ["AI", "Data", "Infrastructure"],
    link: null // Handled via click handler for transition
  },
  {
    id: "opendroids",
    name: "OpenDroids, Inc",
    ticker: "DROID",
    logo: "/opendroids-logo.png",
    description: "Building the superabundance machine through multiple phases of first principled robotics development and deployment.",
    status: "DRAFTING",
    treasury: "$0",
    members: 15,
    proposals: 0,
    tags: ["Robotics", "AI", "Hardware"],
    link: "#" 
  }
];

export default function AllProjects() {
  const router = useRouter();
  const [searchQuery, setSearchQuery] = useState("");
  const [activeTab, setActiveTab] = useState("All");
  
  // Transition State
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [transitionMessage, setTransitionMessage] = useState("Connecting to SPV");
  const [dotCount, setDotCount] = useState(0);

  // Handle clicking the project card
  const handleProjectClick = (projectId: string) => {
    if (projectId === 'kled') {
      setIsTransitioning(true);
      
      setTransitionMessage("Connecting to SPV");

      setTimeout(() => {
        setTransitionMessage("Directing to Kled AI Governance");
      }, 3500);

      setTimeout(() => {
        router.push('/projects/kled');
      }, 7000);
    }
  };

  // Dot Animation
  useEffect(() => {
    if (isTransitioning) {
      const interval = setInterval(() => {
        setDotCount((prev) => (prev + 1) % 4);
      }, 500); 
      return () => clearInterval(interval);
    } else {
        setDotCount(0);
    }
  }, [isTransitioning]);

  const renderDots = () => ".".repeat(dotCount);

  const filteredProjects = PROJECTS.filter(p => {
    const matchesSearch = p.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                          p.ticker.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTab = activeTab === "All" || 
                       (activeTab === "Live" && p.status === "LIVE") ||
                       (activeTab === "Upcoming" && p.status !== "LIVE");
    return matchesSearch && matchesTab;
  });

  return (
    // FORCED LIGHT THEME: Hardcoded bg-white and text-gray-900 to ignore global dark mode variables
    <main className="min-h-screen flex flex-col font-sans bg-white text-gray-900 selection:bg-blue-100 selection:text-blue-900 relative">
      
      {/* --- APPLE STYLE GLASS POPUP --- */}
      {isTransitioning && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/20 backdrop-blur-sm animate-in fade-in duration-300">
            <div className="bg-white/80 backdrop-blur-2xl border border-white/40 shadow-2xl rounded-3xl p-10 flex flex-col items-center gap-6 max-w-sm w-full mx-4 transform transition-all scale-100">
                <div className="relative">
                    <div className="absolute inset-0 bg-blue-400/30 blur-xl rounded-full"></div>
                    <Loader2 className="w-10 h-10 text-blue-600 animate-spin relative z-10" />
                </div>
                <div className="text-center space-y-1">
                    <h3 className="text-lg font-semibold text-gray-900">
                        Just a moment
                    </h3>
                    <p className="text-sm font-medium text-gray-500 font-mono h-6">
                        {transitionMessage}{renderDots()}
                    </p>
                </div>
            </div>
        </div>
      )}

      {/* --- ATMOSPHERIC BACKGROUND GRADIENT (Permanent) --- */}
      <div className="absolute inset-0 z-0 pointer-events-none">
          <div className="absolute top-0 left-0 right-0 h-[60vh] bg-gradient-to-b from-blue-200/40 via-blue-50/40 to-white"></div>
          <div className="absolute bottom-0 left-0 right-0 h-[40vh] bg-gradient-to-t from-orange-100/30 via-white to-transparent"></div>
      </div>

      {/* --- Navigation --- */}
      <nav className="w-full relative z-20 border-b border-transparent">
        <div className="max-w-[1100px] mx-auto px-8 py-6 flex justify-between items-center">
            <div className="flex items-center gap-3">
               {/* LOGO: Hardcoded to BLACK LOGO (street-logo2.png) */}
               <div className="relative h-8 w-32 flex items-center">
                 <img src="/street-logo2.png" alt="Street" className="h-8 w-auto object-contain" />
               </div>
            </div>
            
            <div className="flex items-center gap-4">
            <button className="px-4 py-2 rounded-full border border-gray-200 bg-white/50 backdrop-blur-sm text-gray-600 text-xs font-medium hover:bg-white hover:shadow-sm transition">
                All Projects
            </button>
            
            {/* Hidden Theme Toggle (Since this page is forced Light) */}
            <div className="hidden">
                <ThemeToggle />
            </div>

            <ConnectButton.Custom>
                {({ account, chain, openAccountModal, openConnectModal, mounted }) => {
                const ready = mounted;
                const connected = ready && account && chain;
                return (
                    <div {...(!ready && { 'aria-hidden': true, 'style': { opacity: 0, pointerEvents: 'none', userSelect: 'none' } })}>
                    {(() => {
                        if (!connected) {
                        return (
                            // UPDATED LOG IN BUTTON: Clean White/Blue Theme
                            <button onClick={openConnectModal} type="button" 
                            className="bg-white text-gray-900 border border-blue-100 font-bold px-6 py-2.5 rounded-full text-xs hover:bg-blue-50 hover:border-blue-200 transition shadow-sm hover:shadow-md text-blue-600">
                            Log In
                            </button>
                        );
                        }
                        return (
                        <button onClick={openAccountModal} type="button" className="bg-white border border-gray-200 text-gray-800 px-4 py-2 rounded-full text-xs font-mono font-bold shadow-sm">
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

      {/* --- Header / Hero --- */}
      <section className="pt-24 pb-16 md:pt-32 md:pb-24 flex flex-col items-center text-center space-y-8 px-6 relative z-10">
        <h1 className="text-6xl md:text-8xl font-serif font-medium tracking-tight text-gray-900 drop-shadow-sm">
          ERC-S by Street Labs
        </h1>
        <p className="text-xl md:text-2xl font-serif text-gray-500 max-w-3xl leading-relaxed">
          The first way to tokenise equity grade ownership with compliance without it being a security.
        </p>
      </section>

      {/* --- Filter & Search Bar --- */}
      <div className="w-full max-w-[1100px] mx-auto px-8 pb-8 sticky top-4 z-30">
        <div className="bg-white/70 backdrop-blur-xl border border-white/50 shadow-xl shadow-blue-900/5 rounded-2xl p-4 flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="flex p-1 bg-gray-100/50 rounded-xl">
                {["All", "Live", "Upcoming"].map((tab) => (
                    <button
                        key={tab}
                        onClick={() => setActiveTab(tab)}
                        className={`px-5 py-2 rounded-lg text-xs font-bold uppercase tracking-wider transition-all
                        ${activeTab === tab 
                            ? 'bg-white text-gray-900 shadow-sm' 
                            : 'text-gray-400 hover:text-gray-600'}`}
                    >
                        {tab}
                    </button>
                ))}
            </div>
            <div className="relative w-full md:w-auto min-w-[320px]">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={16} />
                <input 
                    type="text" 
                    placeholder="Search projects..." 
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="w-full bg-gray-50 border-transparent focus:bg-white border focus:border-blue-200 rounded-xl pl-11 pr-4 py-2.5 text-sm text-gray-800 placeholder-gray-400 focus:outline-none transition-all"
                />
            </div>
        </div>
      </div>

      {/* --- Projects Grid --- */}
      <div className="w-full max-w-[1100px] mx-auto px-8 pb-32 flex-1 relative z-10">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            
            {filteredProjects.map((project) => {
                // Render Card Content
                const CardContent = (
                    <div className="h-full bg-white border border-gray-100 rounded-3xl p-8 flex flex-col gap-6 transition-all duration-300 hover:border-blue-200 hover:shadow-2xl hover:shadow-blue-900/10 hover:-translate-y-1 cursor-pointer group">
                        <div className="flex justify-between items-start">
                            <div className="w-14 h-14 rounded-2xl bg-gray-50 border border-gray-100 flex items-center justify-center text-xs font-bold text-gray-900 shadow-inner">
                                {project.ticker}
                            </div>
                            <span className={`px-3 py-1.5 rounded-full text-[10px] font-bold uppercase tracking-wider flex items-center gap-1.5 border
                                ${project.status === 'LIVE' 
                                    ? 'bg-green-50 text-green-700 border-green-100' 
                                    : 'bg-gray-50 text-gray-500 border-gray-100'}`}>
                                <span className={`w-1.5 h-1.5 rounded-full ${project.status === 'LIVE' ? 'bg-green-500 animate-pulse' : 'bg-gray-400'}`}></span>
                                {project.status}
                            </span>
                        </div>
                        <div className="space-y-4 flex-1">
                            <h3 className="text-2xl font-serif text-gray-900 group-hover:text-blue-600 transition-colors">
                                {project.name}
                            </h3>
                            <p className="text-sm text-gray-500 leading-relaxed line-clamp-3">
                                {project.description}
                            </p>
                            <div className="flex flex-wrap gap-2">
                                {project.tags.map(tag => (
                                    <span key={tag} className="text-[10px] font-medium text-gray-500 bg-gray-50 px-2.5 py-1 rounded-md">
                                        {tag}
                                    </span>
                                ))}
                            </div>
                        </div>
                        <div className="pt-6 border-t border-gray-50 grid grid-cols-2 gap-4">
                            <div>
                                <p className="text-[10px] uppercase tracking-widest text-gray-400 font-bold">Treasury</p>
                                <p className="text-sm font-bold text-gray-900 mt-1">{project.treasury}</p>
                            </div>
                            <div>
                                <p className="text-[10px] uppercase tracking-widest text-gray-400 font-bold">Members</p>
                                <p className="text-sm font-bold text-gray-900 mt-1 flex items-center gap-1">
                                    <Users size={14} className="text-gray-400"/> {project.members}
                                </p>
                            </div>
                        </div>
                        <div className="mt-auto pt-4">
                            <div className="w-full py-3 rounded-xl bg-gray-50 text-xs font-bold text-gray-900 uppercase tracking-wider flex items-center justify-center gap-2 group-hover:bg-blue-600 group-hover:text-white transition-all duration-300">
                                View Dashboard <ArrowRight size={14} className="-rotate-45 transition-transform group-hover:translate-x-1 group-hover:-translate-y-1"/>
                            </div>
                        </div>
                    </div>
                );

                if (project.link) {
                    return (
                        <Link key={project.id} href={project.link}>
                            {CardContent}
                        </Link>
                    );
                } else {
                    return (
                        <div key={project.id} onClick={() => handleProjectClick(project.id)}>
                            {CardContent}
                        </div>
                    )
                }
            })}

            <a 
                href="https://accelerate.street.app" 
                target="_blank" 
                rel="noreferrer" 
                className="h-full min-h-[400px] border-2 border-dashed border-blue-200 bg-blue-50/50 rounded-3xl p-8 flex flex-col items-center justify-center text-center gap-6 hover:bg-blue-50 hover:border-blue-300 transition-all cursor-pointer group relative overflow-hidden"
            >
                <div className="absolute inset-0 bg-gradient-to-br from-transparent via-transparent to-blue-100/50 opacity-0 group-hover:opacity-100 transition-opacity"></div>
                <div className="w-20 h-20 rounded-full bg-white border border-blue-100 flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform duration-500 relative z-10">
                    <TrendingUp className="text-blue-500" size={32} />
                </div>
                <div className="relative z-10">
                    <h3 className="text-2xl font-serif text-gray-900 mb-3">Apply for ERC-S</h3>
                    <p className="text-sm text-gray-500 max-w-[260px] mx-auto leading-relaxed">
                        Apply for ERC-S now and ensure you create a valuable and compliant vehicle that benefits both you and your token holders.
                    </p>
                </div>
                <button className="relative z-10 mt-2 px-8 py-3 rounded-full bg-gray-900 text-white text-xs font-bold uppercase tracking-widest hover:bg-black transition shadow-xl hover:shadow-2xl hover:-translate-y-0.5 transform duration-200">
                    Start Now
                </button>
            </a>

        </div>
      </div>

      {/* --- Footer --- */}
      <footer className="w-full border-t border-gray-100 bg-white/80 backdrop-blur-md relative z-10">
          <div className="max-w-[1100px] mx-auto px-8 py-12">
              <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
                  <div className="col-span-1 md:col-span-2 space-y-4">
                     <div className="flex items-center gap-2">
                         <div className="relative h-6 w-24">
                            <img src="/street-logo2.png" alt="Street" className="h-6 w-auto object-contain opacity-60 hover:opacity-100 transition-opacity" />
                         </div>
                     </div>
                     <p className="text-xs text-gray-500 leading-relaxed max-w-xs">
                        Street turns private equity into liquid, programmable digital assets through the ERC-S standard.
                     </p>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-gray-900 uppercase tracking-wider">Platform</h4>
                     <ul className="space-y-2 text-xs text-gray-500">
                        <li><a href="#" className="hover:text-blue-600 transition">Governance</a></li>
                        <li><a href="#" className="hover:text-blue-600 transition">Treasury</a></li>
                        <li><a href="#" className="hover:text-blue-600 transition">Documentation</a></li>
                     </ul>
                  </div>
                  <div className="space-y-4">
                     <h4 className="text-xs font-bold text-gray-900 uppercase tracking-wider">Legal</h4>
                     <ul className="space-y-2 text-xs text-gray-500">
                        <li><a href="#" className="hover:text-blue-600 transition">Terms of Service</a></li>
                        <li><a href="#" className="hover:text-blue-600 transition">Privacy Policy</a></li>
                        <li><a href="#" className="hover:text-blue-600 transition">Cookie Policy</a></li>
                     </ul>
                  </div>
              </div>
              <div className="pt-8 border-t border-gray-100 flex flex-col md:flex-row justify-between items-center gap-4">
                  <p className="text-[10px] text-gray-400">© 2025 Street Protocol. All rights reserved.</p>
                  <div className="flex gap-6 text-gray-400">
                      <a href="https://x.com/StreetFDN" target="_blank" rel="noreferrer" className="hover:text-blue-600 transition">
                          <Twitter size={16} />
                      </a>
                      <a href="#" className="hover:text-blue-600 transition">
                          <Globe size={16} />
                      </a>
                  </div>
              </div>
          </div>
      </footer>
    </main>
  );
}