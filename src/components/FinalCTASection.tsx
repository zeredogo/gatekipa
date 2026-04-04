"use client";

import React, { useState, useEffect } from "react";
import { getWaitlistStats } from "@/app/actions/waitlist";

const FinalCTASection = () => {
  const [totalCount, setTotalCount] = useState(1204);

  useEffect(() => {
    const fetchStats = async () => {
      const stats = await getWaitlistStats();
      setTotalCount(stats.count);
    };
    fetchStats();
  }, []);

  return (
    <section className="py-24 px-4 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="anime-card p-20 bg-secondary/10 border-dashed border-primary/40 flex flex-col items-center text-center gap-12 group transition-all duration-700">
           <div className="size-20 bg-primary/20 rounded-full flex items-center justify-center animate-pulse-glow mb-4">
              <svg className="size-12 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
           </div>
           
           <h2 className="text-5xl sm:text-7xl font-extrabold text-foreground tracking-tighter leading-none max-w-4xl">
             Stop the next <span className="text-gradient-green uppercase italic leading-tight">unexpected charge</span> before it hits.
           </h2>
           
           <p className="text-2xl text-foreground/60 max-w-2xl font-medium italic animate-fade-in">
             Over {totalCount.toLocaleString()} people are already taking back control. Don&apos;t be the last one to secure your gate.
           </p>
           
           <button
              onClick={() => {
                const el = document.getElementById("waitlist");
                el?.scrollIntoView({ behavior: "smooth" });
              }}
              className="btn-primary text-2xl px-12 py-6 shadow-2xl hover:scale-105 active:scale-95 duration-500"
            >
              Get Started for Free
           </button>
           
           <div className="flex items-center gap-6 text-foreground/40 font-bold uppercase tracking-widest text-sm">
              <div className="flex items-center gap-2">
                 <svg className="size-5 text-primary" fill="currentColor" viewBox="0 0 20 20"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" /></svg>
                 Bank Grade Security
              </div>
              <div className="flex items-center gap-2">
                 <svg className="size-5 text-primary" fill="currentColor" viewBox="0 0 20 20"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" /></svg>
                 Trusted by {(totalCount/1000).toFixed(1)}k+ users
              </div>
           </div>
        </div>
      </div>
    </section>
  );
};

export default FinalCTASection;
