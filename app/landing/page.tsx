'use client';

import { useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowUpRight, Check, Users, Zap, Eye, Sparkles, Wallet, Twitter, Globe } from 'lucide-react';
import PhysicsFooter from '@/components/PhysicsFooter';

// --- STYLES & CONSTANTS ---

// Premium 3D Button (Matches Landing Page) - KEPT FOR REFERENCE IF NEEDED LATER, BUT UNUSED IN HERO NOW
const HERO_BUTTON_STYLE = {
    background: 'linear-gradient(180deg, #2346d0ff 0%, #222b92ff 100%)', 
    boxShadow: `
        0px 10px 20px -5px rgba(0, 85, 212, 0.5),       
        0px 5px 10px rgba(0, 0, 0, 0.1),                
        inset 0px 1px 0px rgba(255, 255, 255, 0.4),     
        inset 0px -2px 5px rgba(0, 0, 0, 0.1)           
    `,
    border: '1px solid rgba(255, 255, 255, 0.1)', 
};

// --- LIQUID GLASS TEXT COMPONENT (White/Milky Glass - LARGER) ---
const LiquidGlassText = () => (
    <div className="relative z-20 w-full max-w-[98vw] mx-auto">
        {/* Wide viewBox for single line text */}
        <svg viewBox="0 0 1600 200" className="w-full h-auto overflow-visible select-none pointer-events-none">
            <defs>
                <filter id="liquidGlassFilter" x="-50%" y="-50%" width="200%" height="200%">
                    {/* Shadow Layer */}
                    <feGaussianBlur in="SourceAlpha" stdDeviation="6" result="shadowBlur" />
                    <feOffset in="shadowBlur" dx="0" dy="8" result="shadowOffset" />
                    <feFlood floodColor="#000000" floodOpacity="0.4" result="shadowColor" />
                    <feComposite in="shadowColor" in2="shadowOffset" operator="in" result="droppedShadow" />

                    {/* Glass Effect */}
                    <feGaussianBlur in="SourceAlpha" stdDeviation="4" result="blur" />
                    <feSpecularLighting in="blur" surfaceScale="10" specularConstant="1.4" specularExponent="30" lightingColor="#ffffff" result="staticSpec">
                        <fePointLight x="-500" y="-1000" z="600" />
                    </feSpecularLighting>
                    <feSpecularLighting in="blur" surfaceScale="10" specularConstant="2.8" specularExponent="20" lightingColor="#ffffff" result="shimmerSpec">
                         <fePointLight z="800">
                            <animate attributeName="x" values="-800; 2500; 2500" keyTimes="0; 0.25; 1" dur="6s" repeatCount="indefinite" />
                            <animate attributeName="y" values="-800; 1200; 1200" keyTimes="0; 0.25; 1" dur="6s" repeatCount="indefinite" />
                         </fePointLight>
                    </feSpecularLighting>
                    <feComposite in="shimmerSpec" in2="staticSpec" operator="arithmetic" k1="0" k2="1" k3="1" k4="0" result="combinedSpec" />
                    <feComposite in="combinedSpec" in2="SourceAlpha" operator="in" result="specComposite" />
                    <feGaussianBlur in="SourceAlpha" stdDeviation="2" result="innerBlur" />
                    <feComposite in="SourceGraphic" in2="innerBlur" operator="arithmetic" k1="0" k2="0.5" k3="0.5" k4="0" result="innerGlow" />

                    <feMerge>
                        <feMergeNode in="droppedShadow" />
                        <feMergeNode in="SourceGraphic" /> 
                        <feMergeNode in="specComposite" />
                    </feMerge>
                </filter>
                
                {/* White / Milky Glass Material Gradient */}
                <linearGradient id="glassMaterial" x1="0%" y1="0%" x2="0%" y2="100%">
                    <stop offset="0%" stopColor="rgba(255, 255, 255, 0.4)" />
                    <stop offset="50%" stopColor="rgba(220, 240, 255, 0.2)" />
                    <stop offset="100%" stopColor="rgba(255, 255, 255, 0.1)" />
                </linearGradient>
            </defs>

            {/* Single Line Text - White Glass - INCREASED FONT SIZE to 160px */}
            <text x="50%" y="65%" textAnchor="middle" className="font-serif tracking-tight font-medium" style={{ fontSize: '160px' }} fill="url(#glassMaterial)" stroke="rgba(255,255,255,0.3)" strokeWidth="1.5">
                Game Recognize <tspan fontStyle="italic">Game.</tspan>
            </text>
            <text x="50%" y="65%" textAnchor="middle" className="font-serif tracking-tight font-medium" style={{ fontSize: '160px', filter: 'url(#liquidGlassFilter)' }} fill="transparent">
                Game Recognize <tspan fontStyle="italic">Game.</tspan>
            </text>
        </svg>
    </div>
);

// --- PHILOSOPHY SECTION (Compact, No Header) ---
const ParadigmPhilosophySection = () => {
    return (
        <section className="relative w-full pb-20 pt-0 bg-white overflow-hidden z-20 -mt-24">
            
            <div className="max-w-[1200px] mx-auto relative min-h-[500px] flex items-center justify-center">
                
                {/* CENTRAL VISUAL (ROTATING LOGO) */}
                <div className="relative z-20 w-64 h-64 flex items-center justify-center">
                    <motion.div 
                        className="w-full h-full"
                        animate={{ rotate: 360 }}
                        transition={{ repeat: Infinity, duration: 20, ease: "linear" }}
                    >
                        <img src="/streetmono.png" alt="Street Mono" className="w-full h-full object-contain opacity-90" />
                    </motion.div>
                    <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-2 h-2 bg-black rounded-sm z-30"></div>
                </div>

                {/* CONNECTING LINES */}
                <svg className="absolute inset-0 w-full h-full pointer-events-none z-10 hidden md:block">
                    <line x1="32%" y1="40%" x2="50%" y2="50%" stroke="#E2E8F0" strokeWidth="1" />
                    <rect x="31.5%" y="39.5%" width="6" height="6" fill="black" /> 
                    <line x1="68%" y1="20%" x2="50%" y2="50%" stroke="#E2E8F0" strokeWidth="1" />
                    <rect x="67.5%" y="19.5%" width="6" height="6" fill="black" /> 
                    <line x1="68%" y1="80%" x2="50%" y2="50%" stroke="#E2E8F0" strokeWidth="1" />
                    <rect x="67.5%" y="79.5%" width="6" height="6" fill="black" /> 
                </svg>

                {/* TEXT BLOCKS */}
                <div className="absolute left-8 md:left-[5%] top-[40%] -translate-y-1/2 max-w-xs z-20">
                    <div className="flex flex-col gap-2 text-right"> 
                        <h3 className="text-lg font-bold text-slate-900">Bold Ideas.</h3>
                        <p className="text-sm text-slate-600 font-sans leading-relaxed">
                            SpaceX, AirBNB, Anduril all were contrarian ideas, the more you feel like normal people can't understand your vision, the better.
                        </p>
                    </div>
                </div>

                <div className="absolute right-8 md:right-[5%] top-[20%] -translate-y-1/2 max-w-xs z-20">
                    <div className="flex flex-col gap-2 text-left">
                        <h3 className="text-lg font-bold text-slate-900">Accelerationism, not laggyism.</h3>
                        <p className="text-sm text-slate-600 font-sans leading-relaxed">
                            No visions that are unaligned with the direction our society is progressing. No heavy ideological reasons will find you PMF.
                        </p>
                    </div>
                </div>

                <div className="absolute right-8 md:right-[5%] top-[80%] -translate-y-1/2 max-w-xs z-20">
                    <div className="flex flex-col gap-2 text-left">
                        <h3 className="text-lg font-bold text-slate-900">No incremental improvements.</h3>
                        <p className="text-sm text-slate-600 font-sans leading-relaxed">
                            Nobody needs a Google clone with a simple added feature or Ethereum but slightly faster. Either you have moat or you die.
                        </p>
                    </div>
                </div>

            </div>
        </section>
    );
};

// --- REWARDS SIMULATOR ---
const RewardsSimulator = () => {
    const [launches, setLaunches] = useState(1);
    const cash = launches * 5000;
    const tokens = (launches * 0.1).toFixed(1);

    return (
        <div className="w-full max-w-3xl mx-auto bg-[#0B1121] text-white rounded-[2rem] p-8 md:p-12 relative overflow-hidden shadow-2xl border border-slate-800">
            <div className="absolute top-0 right-0 w-[400px] h-[400px] bg-blue-600/10 blur-[100px] rounded-full pointer-events-none"></div>
            <div className="relative z-10 flex flex-col md:flex-row gap-12 items-center">
                <div className="flex-1 space-y-8 w-full">
                    <div className="space-y-2">
                        <h3 className="text-2xl font-serif text-white">Your Upside</h3>
                        <p className="text-slate-400 text-xs font-sans leading-relaxed">
                            We don't do "exposure". You get hard cash and equity-grade token allocations for every startup that launches through you.
                        </p>
                    </div>
                    <div className="space-y-4">
                        <div className="flex justify-between text-xs font-bold uppercase tracking-widest text-slate-500">
                            <span>Successful Referrals</span>
                            <span className="text-white">{launches}</span>
                        </div>
                        <input type="range" min="1" max="10" step="1" value={launches} onChange={(e) => setLaunches(parseInt(e.target.value))} className="w-full h-2 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-blue-500"/>
                        <div className="flex justify-between text-[10px] text-slate-600 font-sans">
                            <span>1 Startup</span>
                            <span>10 Startups</span>
                        </div>
                    </div>
                </div>
                <div className="flex-1 flex gap-4 w-full">
                    <div className="flex-1 bg-slate-800/50 backdrop-blur-sm rounded-xl p-6 border border-slate-700/50 flex flex-col items-center justify-center gap-2 text-center group hover:bg-slate-800 transition-colors">
                        <span className="text-slate-400 text-[10px] uppercase tracking-widest font-bold">Cash Grant</span>
                        <div className="text-2xl md:text-3xl font-serif text-white group-hover:scale-110 transition-transform">${cash.toLocaleString()}</div>
                    </div>
                    <div className="flex-1 bg-gradient-to-br from-blue-900/40 to-slate-800/40 backdrop-blur-sm rounded-xl p-6 border border-blue-500/20 flex flex-col items-center justify-center gap-2 text-center group hover:border-blue-500/40 transition-colors shadow-[0_0_30px_-10px_rgba(59,130,246,0.2)]">
                        <span className="text-blue-300 text-[10px] uppercase tracking-widest font-bold">Token Alloc</span>
                        <div className="text-2xl md:text-3xl font-serif text-white group-hover:scale-110 transition-transform">{tokens}%</div>
                        <span className="text-[10px] text-slate-500">of supply</span>
                    </div>
                </div>
            </div>
            <div className="mt-8 pt-6 border-t border-white/5 text-center"><p className="text-[10px] text-slate-500 font-sans">*Estimates based on standard Tier-1 launch packages. Allocations vest over standard periods.</p></div>
        </div>
    );
};

// --- MAIN PAGE ---

export default function ScoutingPage() {
    return (
        <div className="min-h-screen font-sans bg-transparent text-slate-900 selection:bg-blue-100 selection:text-blue-900 overflow-x-hidden relative flex flex-col">
            
            {/* Navbar Placeholder */}
            <nav className="fixed top-0 left-0 right-0 z-50 py-6 transition-all bg-transparent">
                <div className="max-w-[1100px] mx-auto px-6 flex justify-between items-center">
                    <a href="/" className="flex items-center gap-3 opacity-80 hover:opacity-100 transition-opacity">
                        <img src="/street-logo.png" alt="Street" className="h-6 w-auto object-contain" />
                        <span className="text-xs font-bold text-white/70 uppercase tracking-widest border-l border-white/30 pl-3 ml-1">Scouts</span>
                    </a>
                    <a href="https://forms.gle/YOUR_FORM_LINK" target="_blank" rel="noreferrer">
                        {/* CHANGED: Plain Text Button "Apply Now" */}
                        <button className="text-white px-6 py-2.5 text-xs font-bold hover:text-blue-200 transition-all font-sans">
                            Apply Now
                        </button>
                    </a>
                </div>
            </nav>

            {/* --- HERO SECTION --- */}
            <section className="relative pt-32 pb-16 px-6 min-h-[55vh] flex flex-col items-center justify-center overflow-hidden">
                
                {/* Background Image Layer */}
                <div className="absolute inset-0 z-0">
                    <img src="/35.jpg" alt="Background" className="w-full h-full object-cover" />
                    {/* Dark Overlay to ensure text readability */}
                    <div className="absolute inset-0 bg-black/20 mix-blend-multiply"></div>
                    {/* Gradient Fade to White at the bottom */}
                    <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-white to-transparent"></div>
                </div>

                <div className="relative z-10 max-w-[98vw] lg:max-w-[1600px] mx-auto text-center space-y-8">
                    
                    {/* LARGE SINGLE PARAGRAPH TEXT */}
                    <motion.div
                         initial={{ opacity: 0, y: 30, scale: 0.95 }}
                         animate={{ opacity: 1, y: 0, scale: 1 }}
                         transition={{ duration: 1.2, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
                    >
                        <LiquidGlassText />
                    </motion.div>

                    {/* HERO BUTTON REMOVED */}
                </div>
            </section>

            {/* --- PHILOSOPHY SECTION --- */}
            <ParadigmPhilosophySection />

            {/* --- INCENTIVES SECTION --- */}
            <section className="py-32 px-6 bg-white relative z-10">
                <div className="max-w-[1100px] mx-auto">
                    <div className="mb-16 md:text-center max-w-2xl mx-auto space-y-4">
                        <h2 className="text-3xl md:text-5xl font-serif text-slate-900 tracking-tight">Skin in the Game.</h2>
                        <p className="text-slate-500 font-sans leading-relaxed">Scouting shouldn't be thankless. When you bring a breakout company to Street, you participate in their upside alongside us.</p>
                    </div>
                    <RewardsSimulator />
                    <div className="mt-24 grid grid-cols-1 md:grid-cols-2 gap-12 items-center">
                        <div className="space-y-6">
                             <h3 className="text-2xl font-serif text-slate-900">How it works</h3>
                             <ul className="space-y-6">
                                {[{ title: "Identify", desc: "Spot a founder with high velocity and a unique insight." }, { title: "Intro", desc: "Connect them with the Street core team via your dedicated channel." }, { title: "Launch", desc: "If they launch on Street, you get paid immediately." }, { title: "Vest", desc: "Receive your token allocation as their community grows." }].map((step, i) => (
                                    <li key={i} className="flex gap-4">
                                        <div className="flex-shrink-0 w-6 h-6 rounded-full bg-slate-100 text-slate-500 text-xs font-bold flex items-center justify-center border border-slate-200 mt-0.5 font-sans">{i + 1}</div>
                                        <div>
                                            <h4 className="text-sm font-bold text-slate-900 font-sans">{step.title}</h4>
                                            <p className="text-sm text-slate-500 leading-relaxed font-sans">{step.desc}</p>
                                        </div>
                                    </li>
                                ))}
                             </ul>
                        </div>
                        <div className="relative h-[400px] bg-slate-100 rounded-3xl overflow-hidden border border-slate-200">
                             <div className="absolute inset-0 flex items-center justify-center opacity-30">
                                 <div className="w-64 h-64 border border-slate-300 rounded-full animate-[spin_10s_linear_infinite]"></div>
                                 <div className="absolute w-48 h-48 border border-slate-300 rounded-full animate-[spin_15s_linear_infinite_reverse]"></div>
                                 <div className="absolute w-32 h-32 border border-slate-300 rounded-full animate-[spin_20s_linear_infinite]"></div>
                             </div>
                             <div className="absolute inset-0 flex flex-col items-center justify-center gap-4">
                                <div className="bg-white p-4 rounded-xl shadow-lg border border-slate-100 flex items-center gap-3 w-64 transform translate-x-8">
                                    <div className="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center text-orange-600"><Zap size={14}/></div>
                                    <div className="text-xs font-sans"><div className="font-bold text-slate-900">New Scout Deal</div><div className="text-slate-400">Sent just now</div></div>
                                </div>
                                <div className="bg-white p-4 rounded-xl shadow-lg border border-slate-100 flex items-center gap-3 w-64 transform -translate-x-8">
                                    <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-600"><Check size={14}/></div>
                                    <div className="text-xs font-sans"><div className="font-bold text-slate-900">Approved for Launch</div><div className="text-slate-400">Due Diligence Passed</div></div>
                                </div>
                                <div className="bg-[#0B1121] p-4 rounded-xl shadow-xl border border-slate-800 flex items-center gap-3 w-64 transform translate-x-4">
                                    <div className="w-8 h-8 rounded-full bg-blue-600 flex items-center justify-center text-white"><Wallet size={14}/></div>
                                    <div className="text-xs font-sans"><div className="font-bold text-white">Grant Disbursed</div><div className="text-slate-400">Tokens Vested</div></div>
                                </div>
                             </div>
                        </div>
                    </div>
                </div>
            </section>

            <footer className="w-full border-t border-gray-100 bg-white relative z-10">
                <PhysicsFooter />
                <div className="max-w-[1100px] mx-auto px-8 pb-12 pt-4">
                    <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
                        <div className="col-span-1 md:col-span-2 space-y-4">
                            <div className="flex items-center gap-2"><div className="relative h-6 w-24"><img src="/street-logo2.png" alt="Street" className="h-6 w-auto object-contain opacity-60 hover:opacity-100 transition-opacity" /></div></div>
                            <p className="text-xs text-gray-500 leading-relaxed max-w-xs font-sans">Street turns private equity into liquid, programmable digital assets through the ERC-S standard.</p>
                        </div>
                        <div className="space-y-4"><h4 className="text-xs font-bold text-gray-900 uppercase tracking-wider font-sans">Platform</h4><ul className="space-y-2 text-xs text-gray-500 font-sans"><li><a href="#" className="hover:text-blue-600 transition">Governance</a></li><li><a href="#" className="hover:text-blue-600 transition">Treasury</a></li><li><a href="https://ERC-S.com" target="_blank" className="hover:text-blue-600 transition">Documentation</a></li></ul></div>
                        <div className="space-y-4"><h4 className="text-xs font-bold text-gray-900 uppercase tracking-wider font-sans">Legal</h4><ul className="space-y-2 text-xs text-gray-500 font-sans"><li><a href="#" className="hover:text-blue-600 transition">Terms of Service</a></li><li><a href="#" className="hover:text-blue-600 transition">Privacy Policy</a></li><li><a href="#" className="hover:text-blue-600 transition">Cookie Policy</a></li></ul></div>
                    </div>
                    <div className="pt-8 border-t border-gray-100 flex flex-col md:flex-row justify-between items-center gap-4">
                        <p className="text-[10px] text-gray-400 font-sans">© 2025 Street Labs. All rights reserved.</p>
                        <div className="flex gap-6 text-gray-400"><a href="https://x.com/StreetFDN" target="_blank" rel="noreferrer" className="hover:text-blue-600 transition"><Twitter size={16} /></a><a href="#" className="hover:text-blue-600 transition"><Globe size={16} /></a></div>
                    </div>
                </div>
            </footer>
        </div>
    );
}