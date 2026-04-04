"use client";

import React from "react";

const HowItWorksSection = () => {
  const steps = [
    {
      number: "01",
      title: "Join",
      description: "Secure your spot on the waitlist to get early access.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
        </svg>
      ),
    },
    {
      number: "02",
      title: "Invite",
      description: "Move up the queue by inviting friends with your referral link.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      ),
    },
    {
      number: "03",
      title: "Verify",
      description: "Get early access to our private beta and set up your cards.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
        </svg>
      ),
    },
    {
      number: "04",
      title: "Control",
      description: "Take back 100% control of every subscription payment.",
      icon: (
        <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>
      ),
    },
  ];

  return (
    <section id="how-it-works" className="py-24 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            How it <span className="text-gradient-green uppercase italic">works.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Don&apos;t just track. Control. Gatekipa puts you in the driver&apos;s seat of your recurring expenses.
          </p>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4 px-4 sm:px-0 relative">
           {/* Step Connectors Desktop */}
           <div className="hidden lg:block absolute top-[6.5rem] left-[15%] right-[15%] h-px bg-gradient-to-r from-primary/10 via-primary/40 to-primary/10 z-0" />

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
      </div>
    </section>
  );
};

export default HowItWorksSection;
