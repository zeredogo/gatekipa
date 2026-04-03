"use client";

import React from "react";

const FeaturesSection = () => {
  const features = [
    {
      title: "Subscription Cards",
      description: "Generate dedicated virtual cards for each service you use.",
      icon: "💳",
    },
    {
      title: "Rule-Based Controls",
      description: "Set custom limits and merchant-specific rules.",
      icon: "⚙️",
    },
    {
      title: "Trial Protection",
      description: "Auto-block cards after free trials expire.",
      icon: "🛡️",
    },
    {
      title: "Automatic Blocking",
      description: "Any charge outside your rules is instantly denied.",
      icon: "🚫",
    },
    {
      title: "Multi-Account Manager",
      description: "Organize by personal, clients, and business.",
      icon: "📂",
    },
    {
      title: "Search & Organize",
      description: "Find any subscription across cards instantly.",
      icon: "🔍",
    },
    {
      title: "Team Collaboration",
      description: "Invite your team and set departmental limits.",
      icon: "👥",
    },
    {
      title: "Kill Switch",
      description: "One-click to disable any card or account instantly.",
      icon: "⏹️",
    },
    {
      title: "Smart Alerts",
      description: "Get notified before any charge is processed.",
      icon: "🔔",
    },
    {
      title: "Insights (Premium)",
      description: "See exactly where your money is going every month.",
      icon: "📈",
    },
  ];

  return (
    <section id="features" className="py-24 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <div className="size-12 bg-primary/20 rounded-full flex items-center justify-center mb-6 animate-pulse-glow">
            <svg className="size-6 text-primary" fill="currentColor" viewBox="0 0 20 20">
              <path d="M5 3a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2V5a2 2 0 00-2-2H5zM5 11a2 2 0 00-2 2v2a2 2 0 002 2h2a2 2 0 002-2v-2a2 2 0 00-2-2H5zM11 5a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V5zM11 13a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
            </svg>
          </div>
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            Everything you <br/>
            <span className="text-gradient-green uppercase italic">need.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Powerful features built to give you total control over your cash flow.
          </p>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
          {features.map((feature, idx) => (
            <div
              key={feature.title}
              className="anime-card p-8 flex flex-col gap-6 group hover:border-primary border-primary/10 transition-colors bg-secondary/10"
              style={{ animationDelay: `${idx * 100}ms` }}
            >
              <div className="text-4xl group-hover:scale-125 transition-transform duration-500">
                {feature.icon}
              </div>
              <div>
                <h3 className="text-xl font-bold text-foreground mb-2">{feature.title}</h3>
                <p className="text-sm text-foreground/60 font-medium italic leading-relaxed">
                  {feature.description}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default FeaturesSection;
