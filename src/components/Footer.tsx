"use client";

import React from "react";

const Footer = () => {
  const currentYear = new Date().getFullYear();

  const sections = [
    {
      title: "Product",
      links: [
        { name: "How It Works", href: "#how-it-works" },
        { name: "Features", href: "#features" },
        { name: "Security", href: "#security" },
      ],
    },
    {
      title: "Company",
      links: [
        { name: "FAQs", href: "#faqs" },
        { name: "Contact", href: "#contact" },
        { name: "Privacy Policy", href: "/privacy" },
        { name: "Terms & Conditions", href: "/terms" },
      ],
    },
  ];

  return (
    <footer className="py-20 bg-background border-t border-primary/10 relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 lg:gap-8">
        <div className="lg:col-span-2 space-y-8">
          <a href="/" className="flex items-center group">
            <div className="w-40 lg:w-48 overflow-hidden group-hover:scale-105 transition-transform duration-300">
              <img src="/logo2.png" alt="Gatekipa Logo" className="w-full h-auto object-contain" />
            </div>
          </a>
          <p className="text-lg text-foreground/50 max-w-sm font-medium italic">
            Taking back control of your subscriptions, one card at a time. Built for Nigeria, for individuals and businesses. Block the next charge before it happens.
          </p>
          <div className="text-sm font-bold text-primary/60 uppercase tracking-widest">
            © {currentYear} Westgate Stratagem. All rights reserved.
          </div>
        </div>

        {sections.map((section) => (
          <div key={section.title} className="space-y-6">
            <h4 className="text-sm font-bold text-foreground/40 uppercase tracking-[0.2em]">
              {section.title}
            </h4>
            <ul className="space-y-4">
              {section.links.map((link) => (
                <li key={link.name}>
                  <a
                    href={link.href}
                    className="text-lg font-bold text-foreground/70 hover:text-primary transition-colors italic hover:underline decoration-primary/30 decoration-2 underline-offset-4"
                  >
                    {link.name}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </footer>
  );
};

export default Footer;
