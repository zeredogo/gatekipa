"use client";

import React from "react";

const PainSection = () => {
  const painPoints = [
    {
      title: "For Individuals",
      description: "Stop watching money bleed away to services you no longer use.",
      features: [
        "One-click trial cancellation",
        "Auto-block unknown charges",
        "Centralized expense dashboard",
      ],
      icon: (
        <svg className="size-8 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
        </svg>
      ),
    },
    {
      title: "For Businesses",
      description: "Scale your operations without losing control of service overheads.",
      features: [
        "Departmental budget limits",
        "Employee spending controls",
        "Unified compliance reporting",
      ],
      icon: (
        <svg className="size-8 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
        </svg>
      ),
    },
  ];

  return (
    <section id="pain-points" className="py-24 px-4 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <h2 className="text-4xl sm:text-6xl font-extrabold text-foreground mb-6 tracking-tight leading-tight">
            Stop the <br />
            <span className="text-gradient-green uppercase">Invisible Leak.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Over ₦50,000 is lost annually per person to forgotten &quot;free trials&quot; and zombie subscriptions. We block them at the gate.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8">
          {painPoints.map((point) => (
            <div
              key={point.title}
              className="anime-card p-10 flex flex-col items-start gap-6 hover:border-primary/40 group"
            >
              <div className="size-16 bg-primary/10 rounded-2xl flex items-center justify-center border border-primary/20 group-hover:scale-110 transition-transform">
                {point.icon}
              </div>
              <div>
                <h3 className="text-3xl font-bold text-foreground mb-4">{point.title}</h3>
                <p className="text-lg text-foreground/60 mb-8 font-medium">
                  {point.description}
                </p>
                <ul className="space-y-4">
                  {point.features.map((feature) => (
                    <li key={feature} className="flex items-center gap-3 text-foreground/80 font-semibold italic">
                      <div className="size-2 bg-primary rounded-full animate-pulse" />
                      {feature}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default PainSection;
