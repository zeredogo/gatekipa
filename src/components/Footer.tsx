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
    <footer className="bg-background relative overflow-hidden">
      {/* Download CTA Block */}
      <div className="border-y border-primary/10 bg-secondary/5 py-16">
        <div className="max-w-[1600px] mx-auto px-4 sm:px-12 flex flex-col md:flex-row items-center justify-between gap-8">
          <div>
            <h3 className="text-3xl sm:text-5xl font-extrabold text-foreground mb-4 tracking-tighter">
              Ready to take <span className="text-primary italic">control?</span>
            </h3>
            <p className="text-lg text-foreground/60 font-medium max-w-xl">
              Download the Gatekipa app today and stop paying for subscriptions you didn&apos;t approve. Available now on Android.
            </p>
          </div>
          <div className="flex shrink-0">
            <a 
              href="https://play.google.com/store/apps/details?id=com.gatekipa.gatekeeper" 
              target="_blank" 
              rel="noopener noreferrer"
              className="btn-primary py-5 px-10 text-xl shadow-2xl hover:scale-[1.02] flex items-center gap-3"
            >
              <svg className="size-6" viewBox="0 0 24 24" fill="currentColor">
                <path d="M17.523 15.341l-4.624-4.624 4.886-4.886a1.077 1.077 0 0 0-.172-1.637L16.29 3.411a1.077 1.077 0 0 0-1.258-.095L4.47 9.873a1.075 1.075 0 0 0 0 1.834l10.562 6.557a1.077 1.077 0 0 0 1.258-.095l1.323-.783a1.077 1.077 0 0 0 .172-1.637l-.262-.408zM5.38 10.79L14.7 5.1l-3.8 3.8-5.52 1.89zm10.76 6.55L6.82 11.66l5.52-1.89 3.8-3.8v11.37zM18.8 12l2.42-1.42a1.077 1.077 0 0 0 0-1.85L18.8 7.3V12z"/>
              </svg>
              Download App
            </a>
          </div>
        </div>
      </div>

      <div className="py-20 max-w-[1600px] mx-auto px-4 sm:px-12 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 lg:gap-8">
        <div className="lg:col-span-2 space-y-8">
          <a href="/" className="flex items-center group">
            <div className="w-40 lg:w-48 overflow-hidden group-hover:scale-105 transition-transform duration-300">
              <img src="/logo2.png" alt="Gatekipa Logo" className="w-full h-auto object-contain" />
            </div>
          </a>
          <p className="text-lg text-foreground/50 max-w-sm font-medium italic">
            Taking back control of your subscriptions, one card at a time. Built for Nigeria, for individuals and businesses. Block the next charge before it happens.
          </p>
          <div className="pt-2">
            <a 
              href="https://play.google.com/store/apps/details?id=com.gatekipa.gatekeeper" 
              target="_blank" 
              rel="noopener noreferrer"
              className="inline-block hover:opacity-90 transition-opacity"
            >
              <img 
                src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" 
                alt="Get it on Google Play" 
                className="h-14 w-auto" 
              />
            </a>
          </div>
          <div className="text-sm font-bold text-primary/60 uppercase tracking-widest mt-4">
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
