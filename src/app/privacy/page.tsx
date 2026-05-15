import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";

export default function PrivacyPolicy() {
  return (
    <main className="bg-background min-h-screen text-foreground">
      <Navbar />
      <div className="pt-32 pb-24 px-4 max-w-4xl mx-auto">
        <h1 className="text-4xl sm:text-6xl font-extrabold mb-8 tracking-tighter">
          Privacy <span className="text-gradient-green">Policy</span>
        </h1>
        <div className="space-y-6 text-lg text-foreground/80 font-medium leading-relaxed">
          <p>
            Effective Date: April 2026
          </p>
          <p>
            At Gatekipa, we take your privacy seriously. This Privacy Policy outlines how we collect, use, and protect your personal information when you use our subscription management services.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">1. Information We Collect</h2>
          <p>
            We collect information you provide directly to us, such as your name, email address, and payment information when you register for an account or contact us. We also collect usage data to help us improve our platform.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">2. How We Use Your Information</h2>
          <p>
            The information we collect is used to provide, maintain, and improve our services, process transactions, send notifications about your subscription rules, and communicate with you about updates and offers.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">3. Data Security</h2>
          <p>
            We implement bank-grade encryption and standard security measures to protect your personal and financial data. However, no electronic transmission or storage system is entirely secure, and we cannot guarantee absolute security.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">4. Sharing Your Information</h2>
          <p>
            We do not sell your personal data to third parties. We may share necessary information with trusted service providers (like payment processors) strictly for the purpose of operating Gatekipa.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">5. Contact Us</h2>
          <p>
            If you have questions about this Privacy Policy, please contact us at <a href="mailto:hello@gatekipa.com" className="text-primary underline">hello@gatekipa.com</a>.
          </p>
        </div>
      </div>
      <Footer />
    </main>
  );
}
