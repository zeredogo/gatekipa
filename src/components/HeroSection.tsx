"use client";

import React, { useEffect, useRef, useState } from "react";
import { getWaitlistStats } from "@/app/actions/waitlist";

const HeroSection = () => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [mousePos, setMousePos] = useState({ x: 50, y: 50 });
  const [totalCount, setTotalCount] = useState(1204);
  const [timeLeft, setTimeLeft] = useState({ days: 30, hours: 0, minutes: 0, seconds: 0 });

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const stats = await getWaitlistStats();
        if (stats && stats.count > 0) {
          setTotalCount(stats.count);
        } else {
          setTotalCount(2500); // Marketing fallback
        }
      } catch {
        setTotalCount(2500); // Fallback on error
      }
    };
    fetchStats();

    // Countdown Logic
    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + 30); // 30 days from now

    const interval = setInterval(() => {
      const now = new Date().getTime();
      const difference = targetDate.getTime() - now;

      if (difference > 0) {
        setTimeLeft({
          days: Math.floor(difference / (1000 * 60 * 60 * 24)),
          hours: Math.floor((difference % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)),
          minutes: Math.floor((difference % (1000 * 60 * 60)) / (1000 * 60)),
          seconds: Math.floor((difference % (1000 * 60)) / 1000),
        });
      }
    }, 1000);

    return () => clearInterval(interval);
  }, []);

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
             <div className="flex flex-col items-center justify-center bg-primary/10 border border-primary/20 rounded-2xl py-3 px-5 min-w-[80px]">
                <span className="text-3xl font-extrabold text-primary font-mono">{timeLeft.days}</span>
                <span className="text-xs text-foreground/60 uppercase font-bold tracking-widest mt-1">Days</span>
             </div>
             <div className="flex flex-col items-center justify-center bg-primary/10 border border-primary/20 rounded-2xl py-3 px-5 min-w-[80px]">
                <span className="text-3xl font-extrabold text-primary font-mono">{timeLeft.hours}</span>
                <span className="text-xs text-foreground/60 uppercase font-bold tracking-widest mt-1">Hours</span>
             </div>
             <div className="flex flex-col items-center justify-center bg-primary/10 border border-primary/20 rounded-2xl py-3 px-5 min-w-[80px]">
                <span className="text-3xl font-extrabold text-primary font-mono">{timeLeft.minutes}</span>
                <span className="text-xs text-foreground/60 uppercase font-bold tracking-widest mt-1">Mins</span>
             </div>
             <div className="flex flex-col items-center justify-center bg-primary/10 border border-primary/20 rounded-2xl py-3 px-5 min-w-[80px]">
                <span className="text-3xl font-extrabold text-primary font-mono">{timeLeft.seconds}</span>
                <span className="text-xs text-foreground/60 uppercase font-bold tracking-widest mt-1">Secs</span>
             </div>
          </div>

          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 border border-primary/20 text-primary text-xs font-bold tracking-wider uppercase animate-fade-in -mt-4">
            <span className="relative flex size-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75"></span>
              <span className="relative inline-flex rounded-full size-2 bg-primary"></span>
            </span>
            Join {totalCount.toLocaleString()}+ others
          </div>

          <h1 className="text-5xl sm:text-7xl lg:text-8xl font-extrabold text-foreground leading-[0.95] tracking-tighter">
            Bad memory? <br />
            <span className="text-gradient-green">Keep your money</span> anyway.
          </h1>

          <p className="text-xl sm:text-2xl text-foreground/70 max-w-xl leading-relaxed font-medium">
            Gatekipa blocks forgotten and unwanted subscription charges automatically, for you and your business.
          </p>

          <p className="text-base text-foreground/60 font-semibold tracking-wide uppercase">
            Control every subscription across personal use, teams, and clients before the next charge hits.
          </p>

          <div className="flex flex-wrap gap-4 w-full sm:w-auto">
            <button
              onClick={() => {
                const el = document.getElementById("waitlist");
                el?.scrollIntoView({ behavior: "smooth" });
              }}
              className="btn-primary text-xl px-10 py-5 group"
            >
              Join the Waitlist
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

          <p className="text-sm text-foreground/50 font-bold tracking-wide uppercase mt-4 flex items-center gap-2">
            <span className="size-1.5 bg-primary rounded-full animate-pulse" />
            Move up the waitlist when you invite friends.
          </p>
        </div>

        {/* Right Visual */}
          <div className="relative group perspective-1000 hidden lg:block mt-8 lg:mt-0">
          <div className="anime-card p-1 aspect-[4/3] bg-gradient-to-br from-primary/20 to-transparent flex items-center justify-center overflow-visible">
             {/* Virtual Card Mockup */}
             <div className="w-[85%] aspect-[1.6/1] bg-secondary border border-primary/30 rounded-2xl p-8 flex flex-col justify-between shadow-2xl relative z-10 overflow-hidden transform-gpu group-hover:rotate-y-12 transition-transform duration-700">
                <div className="absolute top-0 right-0 p-8">
                  <div className="size-16 bg-primary/20 rounded-full blur-2xl animate-pulse" />
                </div>
                
                <div className="flex justify-between items-start">
                  <div className="size-12 bg-primary/10 rounded-lg flex items-center justify-center border border-primary/20 overflow-hidden p-1">
                    <img src="/logo.jpg" alt="Gatekipa Logo" className="w-full h-full object-contain rounded-sm mix-blend-multiply" />
                  </div>
                  <div className="text-foreground/40 font-mono text-sm tracking-widest uppercase">Virtual Active</div>
                </div>

                <div>
                  <div className="text-2xl font-mono text-foreground tracking-[0.3em] font-medium mb-1">
                    4567 •••• •••• 8892
                  </div>
                  <div className="flex gap-8">
                    <div>
                      <div className="text-[10px] text-foreground/40 uppercase mb-1">Holder</div>
                      <div className="text-sm font-semibold uppercase tracking-wider">Waitlist Priority</div>
                    </div>
                    <div>
                      <div className="text-[10px] text-foreground/40 uppercase mb-1">Expires</div>
                      <div className="text-sm font-semibold">12 / 28</div>
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
