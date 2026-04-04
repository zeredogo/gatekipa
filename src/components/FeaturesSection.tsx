"use client";

import React from "react";

const FeaturesSection = () => {
  const features = [
    {
      title: "Subscription Cards",
      description: "Create dedicated cards for each subscription.",
      icon: "💳",
    },
    {
      number: "HERO FEATURE",
      title: "Trial Protection",
      description: "Use one-time cards for free trials. Auto-expires, no surprise renewals.",
      icon: "🛡️",
    },
    {
      title: "Rule-Based Controls",
      description: "Set limits, expiry dates, and usage rules.",
      icon: "⚙️",
    },
    {
      title: "Automatic Blocking",
      description: "Charges outside your rules are declined instantly.",
      icon: "🚫",
    },
    {
      title: "Multi-Account Manager",
      description: "Organize subscriptions by personal use, client, or business.",
      icon: "📂",
    },
    {
      title: "Search & Organization",
      description: "Find cards, subscriptions, and accounts instantly.",
      icon: "🔍",
    },
    {
      title: "Team Collaboration",
      description: "Invite team members and manage subscriptions together.",
      icon: "👥",
    },
    {
      title: "Kill Switch",
      description: "Disable any card instantly.",
      icon: "⏹️",
    },
    {
      title: "Smart Alerts",
      description: "Get notified before and after important events.",
      icon: "🔔",
    },
    {
      title: "Insights & Analytics",
      description: "See how much you’ve saved and identify wasted subscriptions.",
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
            Built to <span className="text-gradient-green uppercase italic">control.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Powerful tools built specifically to control subscription payments.
          </p>
          <button
            onClick={() => {
              const el = document.getElementById("waitlist");
              el?.scrollIntoView({ behavior: "smooth" });
            }}
            className="btn-primary py-4 px-10 text-lg !mt-8"
          >
            Get Early Access
          </button>
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
