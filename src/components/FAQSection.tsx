"use client";

import React, { useState } from "react";

const FAQSection = () => {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const faqs = [
    {
      question: "Do I need to move all my subscriptions?",
      answer: "No. You can start with one and expand gradually.",
    },
    {
      question: "What happens if a charge is blocked?",
      answer: "The payment fails and the subscription cannot renew.",
    },
    {
      question: "Can I organize subscriptions by client or purpose?",
      answer: "Yes. You can create separate accounts for personal use, clients, or business operations.",
    },
    {
      question: "Can my team manage subscriptions with me?",
      answer: "Yes. You can invite team members and assign roles.",
    },
    {
      question: "Is this a bank?",
      answer: "No. We work with licensed financial partners.",
    },
  ];

  return (
    <section id="faqs" className="py-24 bg-background relative overflow-hidden">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-12">
        <div className="text-center max-w-3xl mx-auto mb-20 flex flex-col items-center">
          <div className="size-16 bg-primary/10 rounded-full flex items-center justify-center mb-6 animate-float-slow">
            <svg className="size-10 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h2 className="text-4xl sm:text-7xl font-extrabold text-foreground mb-6 tracking-tighter leading-none">
            Common <br/>
            <span className="text-gradient-green uppercase italic">questions.</span>
          </h2>
          <p className="text-xl text-foreground/60 font-medium italic mb-12">
            Everything you need to know about the gate.
          </p>
          <button
            onClick={() => {
              const el = document.getElementById("contact");
              el?.scrollIntoView({ behavior: "smooth" });
            }}
            className="btn-primary py-4 px-10 text-lg mb-8"
          >
            Contact Us
          </button>
        </div>

        <div className="max-w-4xl mx-auto space-y-4">
          {faqs.map((faq, idx) => (
            <div
              key={idx}
              className="anime-card group overflow-hidden transition-all duration-500"
              style={{ maxHeight: openIndex === idx ? "500px" : "100px" }}
            >
              <button
                onClick={() => setOpenIndex(openIndex === idx ? null : idx)}
                className="w-full p-8 flex items-center justify-between text-left group-hover:bg-secondary/10"
              >
                <span className="text-2xl font-bold text-foreground pr-8">{faq.question}</span>
                <div className={`size-10 rounded-full border border-primary/20 flex items-center justify-center shrink-0 transition-transform duration-500 ${openIndex === idx ? "rotate-45" : ""}`}>
                  <svg className="size-6 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                </div>
              </button>
              <div className={`px-8 pb-8 text-lg text-foreground/60 font-medium italic leading-relaxed transition-opacity duration-500 ${openIndex === idx ? "opacity-100" : "opacity-0"}`}>
                {faq.answer}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default FAQSection;
