"use client";

import React from "react";

const InsightSection = () => {
  return (
    <div id="insights" className="bg-background">
      {/* Insight & Solution Combined */}
      <section className="py-24 px-4 relative overflow-hidden">
        <div className="max-w-[1600px] mx-auto px-4 sm:px-12 flex flex-col lg:flex-row items-center gap-16">
          <div className="flex-1 space-y-8">
            <div className="inline-block px-4 py-1 rounded-full bg-primary/10 border border-primary/20 text-primary text-sm font-bold uppercase tracking-widest">
              The Real Problem
            </div>
            <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground leading-[1.1] tracking-tighter">
              The problem isn&apos;t <br />
              <span className="text-secondary-foreground underline decoration-primary decoration-4 underline-offset-8">subscriptions.</span>
            </h2>
            <p className="text-xl text-foreground/60 max-w-2xl font-medium">
              The problem is <strong>losing control</strong> over who can reach into your wallet and when. Gatekipa puts the lock back on your side of the gate.
            </p>
            <div className="grid sm:grid-cols-2 gap-6 pt-4">
              <div className="anime-card p-6 border-l-4 border-l-primary">
                <h4 className="text-xl font-bold text-foreground mb-2">Rule-Based Control</h4>
                <p className="text-base text-foreground/60 font-medium">Set limits and block specific merchants automatically.</p>
              </div>
              <div className="anime-card p-6 border-l-4 border-l-primary">
                <h4 className="text-xl font-bold text-foreground mb-2">Decide Who Gets Paid</h4>
                <p className="text-base text-foreground/60 font-medium">Change permissions instantly for any subscription.</p>
              </div>
            </div>
          </div>
          <div className="flex-1 relative">
             <div className="size-80 sm:size-96 bg-primary/20 blur-[100px] absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 animate-pulse rounded-full" />
             <div className="anime-card p-1 relative z-10 aspect-square max-w-md mx-auto flex items-center justify-center bg-gradient-to-tr from-secondary to-background border-primary/30">
               <div className="text-center p-8">
                 <div className="text-sm font-bold text-primary mb-4 tracking-widest uppercase">Example Logic</div>
                 <div className="text-3xl font-bold text-foreground mb-6 font-mono">IF Merchant == &quot;Netflix&quot; <br/> && Amount == 5000 <br/> THEN BLOCK</div>
                 <div className="inline-flex items-center gap-2 text-primary font-bold text-lg animate-bounce">
                    <svg className="size-6" fill="currentColor" viewBox="0 0 20 20"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-11a1 1 0 10-2 0v2H7a1 1 0 100 2h2v2a1 1 0 102 0v-2h2a1 1 0 100-2h-2V7z" /></svg>
                    Rule Active
                 </div>
               </div>
             </div>
          </div>
        </div>
      </section>

      {/* Savings & Team Section */}
      <section className="py-24 px-4 bg-secondary/20 relative overflow-hidden">
        <div className="max-w-[1600px] mx-auto px-4 sm:px-12 flex flex-col lg:flex-row-reverse items-center gap-16">
          <div className="flex-1 space-y-8">
             <div className="inline-block px-4 py-1 rounded-full bg-primary/10 border border-primary/20 text-primary text-sm font-bold uppercase tracking-widest">
               Built for Teams
             </div>
             <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground leading-[1.1] tracking-tighter">
               Everything in <br/>
               <span className="text-gradient-green">one place.</span>
             </h2>
             <p className="text-xl text-foreground/60 font-medium">
               Create sub-accounts for personal use, different clients, or entire business operations. Manage everything under one roof.
             </p>
             <ul className="grid sm:grid-cols-2 gap-4 text-lg font-bold text-foreground/80 italic">
                <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Personal Accounts</li>
                <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Multiple Clients</li>
                <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Enterprise Teams</li>
                <li className="flex items-center gap-2"><div className="size-2 bg-primary rounded-full animate-pulse"/> Agency Controls</li>
             </ul>
             <div className="anime-card p-8 bg-background/50 border-primary/20 border-dashed">
                <div className="text-4xl font-extrabold text-primary mb-2">₦25,400+</div>
                <div className="text-lg font-bold text-foreground">Average monthly savings per business</div>
             </div>
          </div>
          <div className="flex-1 relative">
             <div className="anime-card p-1 aspect-video flex items-center justify-center bg-secondary/80 animate-float-slow">
               <div className="w-full h-full p-6 flex flex-col gap-4">
                  <div className="h-12 w-full bg-primary/10 rounded-lg flex items-center px-4 justify-between font-mono text-sm">
                    <span className="text-primary font-bold">INVITE TEAM</span>
                    <span className="text-foreground/40">admin@gatekipa.com</span>
                  </div>
                  <div className="grid grid-cols-3 gap-4 h-full">
                     <div className="bg-primary/5 rounded-lg border border-primary/10" />
                     <div className="bg-primary/5 rounded-lg border border-primary/10" />
                     <div className="bg-primary/5 rounded-lg border border-primary/10" />
                  </div>
               </div>
             </div>
          </div>
        </div>
      </section>
    </div>
  );
};

export default InsightSection;
