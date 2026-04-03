"use client";

import React from "react";

const ContactSection = () => {
  return (
    <section id="contact" className="py-24 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <div className="size-16 bg-primary/10 rounded-full flex items-center justify-center mb-6 animate-float-slow">
            <svg className="size-10 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
            </svg>
          </div>
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            Get in <br/>
            <span className="text-gradient-green uppercase italic">touch.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium">
            Have questions? We're here to help you take back control.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <div className="anime-card p-12 text-center group bg-secondary/10 hover:border-primary">
            <div className="text-4xl mb-6 group-hover:scale-110 transition-transform">📧</div>
            <h3 className="text-2xl font-bold text-foreground mb-4">Email Us</h3>
            <a
              href="mailto:support@gatekipa.com"
              className="text-xl font-bold text-primary hover:text-primary/80 transition-colors underline underline-offset-4"
            >
              support@gatekipa.com
            </a>
          </div>
          <div className="anime-card p-12 text-center group bg-secondary/10 hover:border-primary">
            <div className="text-4xl mb-6 group-hover:scale-110 transition-transform">📍</div>
            <h3 className="text-2xl font-bold text-foreground mb-4">Visit Us</h3>
            <p className="text-xl font-bold text-foreground/60 italic leading-relaxed">
              Lagos, Nigeria.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
};

export default ContactSection;
