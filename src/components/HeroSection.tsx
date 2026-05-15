"use client";

import React, { useEffect, useRef, useState } from "react";
const HeroSection = () => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [mousePos, setMousePos] = useState({ x: 50, y: 50 });

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!containerRef.current) return;
    const { left, top, width, height } = containerRef.current.getBoundingClientRect();
    const x = ((e.clientX - left) / width) * 100;
    const y = ((e.clientY - top) / height) * 100;
    setMousePos({ x, y });
  };

  return (
    <section
      id="home"
      ref={containerRef}
      onMouseMove={handleMouseMove}
      className="relative min-h-screen flex flex-col items-center justify-center pt-32 pb-20 px-4 overflow-hidden bg-anime-pattern"
    >
      {/* Background Orbs */}
      <div
        className="absolute inset-0 pointer-events-none transition-opacity duration-1000"
        style={{
          background: `radial-gradient(circle at ${mousePos.x}% ${mousePos.y}%, rgba(74, 222, 128, 0.1) 0%, transparent 40%)`,
        }}
      />
      
      {/* Animated Elements */}
      <div className="absolute top-1/4 left-1/4 size-64 bg-primary/20 blur-[120px] animate-pulse rounded-full" />
      <div className="absolute bottom-1/4 right-1/4 size-96 bg-primary/10 blur-[150px] animate-pulse-glow rounded-full" />

      <div className="max-w-[1600px] mx-auto w-full grid lg:grid-cols-2 gap-16 items-center relative z-10 px-4 sm:px-12">
        {/* Left Content */}
        <div className="flex flex-col items-start gap-8">
          <div className="flex flex-wrap gap-4 mb-2">
            <a 
              href="https://play.google.com/store/apps/details?id=com.gatekipa.gatekeeper" 
              target="_blank" 
              rel="noopener noreferrer"
              className="inline-block hover:opacity-90 transition-opacity"
            >
              <img 
                src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" 
                alt="Get it on Google Play" 
                className="h-14 w-auto" 
              />
            </a>
          </div>



          <h1 className="text-4xl sm:text-6xl lg:text-7xl font-extrabold text-foreground leading-[1.05] tracking-tighter">
            Stop Paying for Things You Didn&rsquo;t Approve.
          </h1>

          <div className="text-xl sm:text-2xl text-foreground/70 max-w-xl leading-relaxed font-medium mt-4 space-y-6">
            <p>One programmable card layer for every subscription, team, and client you manage.</p>
            <p className="text-primary/90 font-bold">Gatekipa is the control layer your card was always missing.</p>
          </div>

          <div className="flex flex-wrap gap-4 w-full sm:w-auto">
            <button
              onClick={() => {
                const el = document.getElementById("contact");
                el?.scrollIntoView({ behavior: "smooth" });
              }}
              className="btn-primary text-xl px-10 py-5 group"
            >
              Contact Us
              <svg
                className="inline-block ml-2 size-6 group-hover:translate-x-1 transition-transform"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2.5}
                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                />
              </svg>
            </button>
            <button
              onClick={() => {
                const el = document.getElementById("how-it-works");
                el?.scrollIntoView({ behavior: "smooth" });
              }}
              className="btn-secondary text-xl px-10 py-5"
            >
              See How It Works
            </button>
          </div>

          <div className="mt-4"></div>
        </div>

        {/* Right Visual */}
          <div className="relative group perspective-1000 hidden lg:block mt-8 lg:mt-0">
          <div className="anime-card p-1 aspect-[4/3] bg-gradient-to-br from-primary/20 to-transparent flex items-center justify-center overflow-visible">
             {/* Hyper-Realistic Virtual Card Mockup */}
             <div className="w-[90%] aspect-[1.586/1] bg-gradient-to-tr from-[#064e3b] via-[#15803d] to-[#4ade80] border border-white/20 rounded-xl p-6 sm:p-8 flex flex-col justify-between shadow-[0_25px_50px_-12px_rgba(22,163,74,0.4)] relative z-10 overflow-hidden transform-gpu group-hover:rotate-y-12 group-hover:rotate-x-6 transition-transform duration-700 text-white backdrop-blur-xl">
                {/* Metallic shine effect */}
                <div className="absolute inset-0 bg-gradient-to-br from-white/20 to-transparent opacity-50" />
                <div className="absolute -top-32 -right-32 w-64 h-64 bg-white/20 rounded-full blur-3xl animate-pulse" />
                
                <div className="flex justify-between items-start relative z-10">
                  <div className="w-32 sm:w-40 bg-white/90 backdrop-blur-md rounded-lg p-3 sm:p-4 shadow-inner ring-1 ring-white">
                    <img src="/logo2.png" alt="Gatekipa Logo" className="w-full h-auto object-contain" />
                  </div>
                  <div className="text-white/80 font-mono text-xs tracking-widest uppercase font-bold">Virtual</div>
                </div>

                <div className="relative z-10 flex items-center justify-between my-2 sm:my-0">
                  {/* EMV Chip */}
                  <svg width="45" height="35" viewBox="0 0 40 30" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <rect width="40" height="30" rx="4" fill="url(#chip-grad)" />
                    <path d="M0 10H12 M0 20H12 M28 10H40 M28 20H40 M12 0V30 M28 0V30 M12 15H28" stroke="#AA7B18" strokeWidth="1" opacity="0.5"/>
                    <defs>
                      <linearGradient id="chip-grad" x1="0" y1="0" x2="40" y2="30" gradientUnits="userSpaceOnUse">
                        <stop stopColor="#FDE08B" />
                        <stop offset="0.5" stopColor="#D4AF37" />
                        <stop offset="1" stopColor="#AA7B18" />
                      </linearGradient>
                    </defs>
                  </svg>

                  {/* NFC Contactless Icon */}
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-white/80 rotate-90 ml-4 hidden sm:block">
                    <path d="M5 12.55a11 11 0 0 1 14.08 0"></path>
                    <path d="M1.42 9a16 16 0 0 1 21.16 0"></path>
                    <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
                  </svg>
                </div>

                <div className="relative z-10 mt-auto">
                  <div className="text-xl sm:text-2xl lg:text-3xl font-mono tracking-[0.2em] font-medium mb-4 drop-shadow-md text-white/90">
                    4567 8901 2345 8892
                  </div>
                  <div className="flex gap-6 sm:gap-10">
                    <div>
                      <div className="text-[9px] sm:text-[10px] text-white/60 uppercase mb-1 font-bold tracking-wider">Cardholder</div>
                      <div className="text-xs sm:text-sm font-semibold uppercase tracking-widest text-white drop-shadow-sm">Gatekipa Member</div>
                    </div>
                    <div>
                      <div className="text-[9px] sm:text-[10px] text-white/60 uppercase mb-1 font-bold tracking-wider">Valid Thru</div>
                      <div className="text-xs sm:text-sm font-semibold text-white drop-shadow-sm">12/28</div>
                    </div>
                  </div>
                </div>
             </div>

             {/* Floating Badges (Static) */}
             <div className="absolute -top-6 -right-6 z-20 hover:-translate-y-2 transition-transform duration-300">
               <div className="bg-secondary/80 backdrop-blur-md border border-border/50 p-4 rounded-2xl shadow-xl">
                 <div className="flex items-center gap-3">
                   <div className="size-10 bg-red-500/20 rounded-full flex items-center justify-center border border-red-500/30">
                     <svg className="size-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
                   </div>
                   <div>
                     <div className="text-xs font-bold text-foreground/60">Auto-Blocked</div>
                     <div className="text-sm font-bold text-foreground">Netflix trial</div>
                   </div>
                 </div>
               </div>
             </div>

             <div className="absolute -bottom-10 -left-10 z-20 hover:-translate-y-2 transition-transform duration-300">
               <div className="bg-secondary/80 backdrop-blur-md border border-border/50 p-4 rounded-2xl shadow-xl">
                 <div className="flex items-center gap-3">
                   <div className="size-10 bg-primary/20 rounded-full flex items-center justify-center border border-primary/30">
                     <svg className="size-5 text-primary" fill="currentColor" viewBox="0 0 20 20"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" /></svg>
                   </div>
                   <div>
                     <div className="text-xs font-bold text-foreground/60">Saved</div>
                     <div className="text-sm font-bold text-foreground">₦25,400 monthly</div>
                   </div>
                 </div>
               </div>
             </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default HeroSection;
