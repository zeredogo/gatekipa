"use client";

import React from "react";
import Image from "next/image";

const HowItWorksSection = () => {
  const steps = [
    {
      number: "01",
      title: "Create a card",
      description: "Generate a virtual card for any subscription or free trial.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
        </svg>
      ),
    },
    {
      number: "02",
      title: "Set your rules",
      description: "Decide how much can be charged, how often, and for how long.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
        </svg>
      ),
    },
    {
      number: "03",
      title: "Assign it",
      description: "Use it for personal subscriptions or client accounts.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
        </svg>
      ),
    },
    {
      number: "04",
      title: "We enforce your rules",
      description: "If a charge violates your settings, it is automatically blocked.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
        </svg>
      ),
    },
  ];

  return (
    <section id="how-it-works" className="py-24 bg-background relative">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            How do I <span className="text-gradient-green uppercase italic">get started?</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            No reminders. No manual cancellations. Just control.
          </p>
          <button
            onClick={() => {
              const el = document.getElementById("waitlist");
              el?.scrollIntoView({ behavior: "smooth" });
            }}
            className="btn-primary py-4 px-10 text-lg !mt-8"
          >
            Join the Waitlist
          </button>
        </div>

        <div className="grid lg:grid-cols-2 gap-12 items-center mt-16 px-4 sm:px-0">
          <div className="grid sm:grid-cols-2 gap-4 relative">
             {steps.map((step) => (
               <div key={step.number} className="anime-card p-8 flex flex-col gap-6 relative z-10 group bg-secondary/10 hover:bg-secondary/20">
                  <div className="flex items-center justify-between">
                    <div className="size-16 rounded-2xl bg-background border border-primary/20 flex items-center justify-center group-hover:scale-110 transition-transform group-hover:border-primary">
                      {step.icon}
                    </div>
                    <span className="text-5xl font-extrabold text-primary/10 group-hover:text-primary transition-colors font-mono">
                      {step.number}
                    </span>
                  </div>
                  <div>
                    <h3 className="text-2xl font-bold text-foreground mb-4">{step.title}</h3>
                    <p className="text-base text-foreground/60 font-medium leading-relaxed italic">
                      {step.description}
                    </p>
                  </div>
               </div>
             ))}
          </div>

          <div className="relative w-full h-[600px] flex justify-center items-center rounded-3xl bg-gradient-to-b from-primary/5 to-transparent overflow-hidden">
             <Image 
               src="/protected-money.jpg"
               alt="Gatekipa App - Create a card"
               fill
               className="object-contain p-4 drop-shadow-2xl"
             />
          </div>
        </div>
      </div>
    </section>
  );
};

export default HowItWorksSection;
