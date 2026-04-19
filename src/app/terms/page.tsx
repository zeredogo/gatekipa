import React from "react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";

export default function TermsAndConditions() {
  return (
    <main className="bg-background min-h-screen text-foreground">
      <Navbar />
      <div className="pt-32 pb-24 px-4 max-w-4xl mx-auto">
        <h1 className="text-4xl sm:text-6xl font-extrabold mb-8 tracking-tighter">
          Terms and <span className="text-gradient-green">Conditions</span>
        </h1>
        <div className="space-y-6 text-lg text-foreground/80 font-medium leading-relaxed">
          <p>
            These Terms and Conditions (“Terms”) govern your access to and use of the GATEKIPA application and services (“Gatekipa”, “we”, “us”, or “our”). By accessing or using Gatekipa, you agree to be legally bound by these Terms and Conditions (“Terms”). If you do not agree, please do not use the Service.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">1. SERVICE DESCRIPTION</h2>
          <p>
            1.1 Gatekipa is a subscription management and payment control platform, that enables users to manage recurring payments across third party services.
          </p>
          <p>1.2 Gatekipa allows users to:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Create virtual payment cards linked to subscriptions</li>
            <li>Define spending limits, usage rules, and expiration dates</li>
            <li>Generate one-time cards for free trials</li>
            <li>Track and organize subscriptions (personal, client, or business)</li>
            <li>Enable or disable cards in real time</li>
            <li>Receive notifications for billing and subscription events</li>
            <li>Collaborate with team members on subscription management</li>
          </ul>
          <p>
            <span className="font-bold">1.3 Non-Banking Status</span><br/>
            Gatekipa is not a bank or deposit by taking institution and does not hold customer funds.
          </p>
          <p>
            <span className="font-bold">1.4 Payment Infrastructure</span><br/>
            All payment processing services are provided through licensed third-party financial institutions and payment processors, including but not limited to Paystack.
          </p>

          <h2 className="text-2xl font-bold text-foreground mt-8">2. REGULATORY COMPLIANCE</h2>
          <p>2.1 Gatekipa operates in compliance with applicable Nigerian laws, including:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Nigeria Data Protection Regulation (NDPR)</li>
            <li>Consumer protection laws</li>
            <li>Applicable Central Bank of Nigeria (CBN) guidelines</li>
          </ul>
          <p>2.2 Where applicable, international data protection and security standards are observed in line with global best practices.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">3. ELIGIBILITY AND ONBOARDING</h2>
          <p>3.1 You must:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Be at least 18 years old</li>
            <li>Possess legal capacity to contract</li>
            <li>Provide accurate, complete, and verifiable information</li>
          </ul>
          <p>3.2 Gatekipa reserves the right to conduct identity verification (KYC) where required by law or its partners.</p>
          <p>3.3 Businesses must ensure that only authorized representatives act on their behalf.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">4. USER OBLIGATIONS</h2>
          <p>You agree to:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Use the Service only for lawful purposes</li>
            <li>Maintain the confidentiality of your credentials</li>
            <li>Ensure that your card configurations reflect your intended usage</li>
            <li>Promptly update account information</li>
          </ul>
          <p>You shall not:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Use the platform for fraudulent or unlawful transaction</li>
            <li>Attempt to bypass system controls or security features</li>
            <li>Misrepresent your identity or authority</li>
          </ul>

          <h2 className="text-2xl font-bold text-foreground mt-8">5. VIRTUAL CARDS AND PAYMENT CONTROLS</h2>
          <p>5.1 Gatekipa enables users to create and manage virtual cards subject to user-defined controls.</p>
          <p>5.2 Users retain full responsibility for:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Configured limits and restrictions</li>
            <li>Subscription obligations to third-party providers</li>
          </ul>
          <p>5.3 Gatekipa will act on your instructions but does not control third-party billing practices.</p>
          <p>5.4 Disabling a card may not reverse already authorized transactions.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">6. PAYMENTS AND THIRD-PARTY SERVICES</h2>
          <p>6.1 Payment transactions are processed exclusively by licensed third-party providers.</p>
          <p>6.2 By using Gatekipa, you agree to comply with:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>The terms of such payment providers</li>
            <li>Applicable card network rules</li>
          </ul>
          <p>6.3 Gatekipa:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Does not store sensitive card data except in tokenized form</li>
            <li>Does not guarantee uninterrupted payment processing</li>
            <li>Shall not be liable for third-party system failures</li>
          </ul>

          <h2 className="text-2xl font-bold text-foreground mt-8">7. FAILED TRANSACTIONS</h2>
          <p>7.1 Transactions may fail due to:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Insufficient funds</li>
            <li>User-imposed restrictions</li>
            <li>Technical or network errors</li>
            <li>Security flags by payment partners</li>
          </ul>
          <p>7.2 Gatekipa shall not be liable for:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Subscription cancellations or penalties resulting from failed payments</li>
            <li>Losses arising from third-party actions</li>
          </ul>
          <p>7.3 Users will receive notifications of failed transactions where possible.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">8. REFUND POLICY</h2>
          <p>8.1 Gatekipa does not issue refunds for payments made to third-party service providers.</p>
          <p>8.2 All subscription related refund requests must be directed to the relevant service provider.</p>
          <p>8.3 Where a transaction error is attributable to Gatekipa or its partners, investigations will be conducted, and any applicable reversals will be handled in accordance with partner policies and applicable law.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">9. DISPUTES AND CHARGEBACKS</h2>
          <p>9.1 Users must first contact Gatekipa support for dispute resolution.</p>
          <p>9.2 Chargebacks initiated without prior engagement may result in:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Account suspension</li>
            <li>Restriction of services</li>
            <li>Recovery actions where applicable</li>
          </ul>

          <h2 className="text-2xl font-bold text-foreground mt-8">10. TEAM ACCESS AND PERMISSIONS</h2>
          <p>10.1 Users may invite team members to manage subscriptions.</p>
          <p>10.2 The primary account holder assumes full responsibility for:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Permissions granted</li>
            <li>Actions performed by team members</li>
          </ul>
          <p>10.3 Gatekipa shall not be liable for misuse arising from shared access.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">11. NOTIFICATIONS AND ALERTS</h2>
          <p>11.1 Gatekipa provides system generated notifications relating to:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Upcoming charges</li>
            <li>Failed or successful transactions</li>
            <li>Subscription activity</li>
          </ul>
          <p>11.2 Delivery is not guaranteed and may be affected by external factors.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">12. DATA PROTECTION AND PRIVACY</h2>
          <p>12.1 Gatekipa employs industry-standard safeguards, including:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>End-to-end encryption</li>
            <li>Secure authentication mechanisms</li>
            <li>Access control protocols</li>
          </ul>
          <p>12.2 Personal data is processed in accordance with:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Applicable Nigerian data protection laws (including NDPR)</li>
            <li>Recognized international data protection principles</li>
          </ul>
          <p>12.3 Users consent to the collection and processing of data necessary for service delivery.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">13. INTELLECTUAL PROPERTY</h2>
          <p>All intellectual property rights in the Service remain vested in Gatekipa or its licensors. Unauthorized reproduction, distribution, or modification is strictly prohibited.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">14. LIMITATION OF LIABILITY</h2>
          <p>To the maximum extent permitted by law, Gatekipa shall not be liable for:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Indirect, incidental, or consequential damages</li>
            <li>Loss of revenue, profits, or data</li>
            <li>Third-party service failures</li>
            <li>User misconfiguration of card controls</li>
          </ul>

          <h2 className="text-2xl font-bold text-foreground mt-8">15. DISCLAIMER</h2>
          <p>The Service is provided on an “as is” and “as available” basis without warranties of any kind, whether express or implied.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">16. TERMINATION AND SUSPENSION</h2>
          <p>Gatekipa reserves the right to suspend or terminate access where:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>There is a breach of these Terms</li>
            <li>Required by law or regulatory directive</li>
            <li>Suspicious or fraudulent activity is detected</li>
          </ul>
          <p>You may stop using the Service at any time.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">17. GOVERNING LAW AND DISPUTE RESOLUTION</h2>
          <p>17.1 These Terms shall be governed by the laws of the Federal Republic of Nigeria.</p>
          <p>17.2 Disputes shall be resolved through:</p>
          <ul className="list-disc pl-6 space-y-2">
            <li>Initial good-faith negotiation</li>
            <li>Failing which, submission to competent courts in Nigeria</li>
          </ul>

          <h2 className="text-2xl font-bold text-foreground mt-8">18. AMENDMENTS</h2>
          <p>We may revise these Terms at any time. Continued use constitutes acceptance of the updated Terms.</p>

          <h2 className="text-2xl font-bold text-foreground mt-8">19. CONTACT</h2>
          <p>For support or inquiries, kindly send us an email at <a href="mailto:hello@gatekipa.com" className="text-primary underline">hello@gatekipa.com</a>.</p>
        </div>
      </div>
      <Footer />
    </main>
  );
}
