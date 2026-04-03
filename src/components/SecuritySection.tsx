"use client";

import React from "react";

const SecuritySection = () => {
  const pillars = [
    {
      title: "Secure Infrastructure",
      description: "Bank-grade encryption on every card generated.",
      icon: "🛡️",
    },
    {
      title: "Data Protection",
      description: "We never store your direct card details.",
      icon: "🔒",
    },
    {
      title: "Trusted Partners",
      description: "Partnered with licensed financial providers.",
      icon: "🤝",
    },
    {
      title: "Real-time Monitoring",
      description: "Instant blocks on fraudulent attempts.",
      icon: "⚡",
    },
  ];

  return (
    <section id="security" className="py-24 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <div className="size-16 bg-primary/10 rounded-full flex items-center justify-center mb-6 animate-float">
            <svg className="size-10 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            Your money is <br/>
            <span className="text-gradient-green uppercase italic">safe.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Gatekipa uses bank-grade security and partners with industry leaders to keep your data protected.
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8 mb-20">
          {pillars.map((pillar) => (
            <div key={pillar.title} className="anime-card p-10 flex flex-col items-center text-center gap-6 group hover:border-primary">
              <div className="text-5xl group-hover:scale-110 transition-transform">{pillar.icon}</div>
              <div>
                <h3 className="text-2xl font-bold text-foreground mb-4">{pillar.title}</h3>
                <p className="text-lg text-foreground/60 font-medium italic">{pillar.description}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Paystack Badge */}
        <div className="anime-card p-12 bg-secondary/10 flex flex-col items-center gap-8 border-dashed border-primary/40">
           <div className="text-center">
              <div className="text-sm font-bold text-primary/60 uppercase tracking-widest mb-2">Proudly Powered By</div>
              <div className="text-4xl font-extrabold text-foreground tracking-tighter">PAYSTACK</div>
           </div>
           <p className="max-w-2xl text-center text-lg text-foreground/70 font-medium italic leading-relaxed">
             Gatekipa leverages Paystack's world-class payment infrastructure to process transactions securely. We never store sensitive card details directly on our servers.
           </p>
           <div className="flex items-center gap-4 text-primary font-bold text-sm tracking-widest uppercase animate-pulse">
              <svg className="size-5" fill="currentColor" viewBox="0 0 20 20"><path d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" /></svg>
              Verified Infrastructure
           </div>
        </div>
      </div>
    </section>
  );
};

export default SecuritySection;
