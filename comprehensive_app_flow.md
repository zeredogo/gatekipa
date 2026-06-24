# Gatekeeper Platform: Comprehensive Application Flow and Feature Documentation

## 1. Executive Summary and Architectural Overview

The Gatekeeper platform is a state-of-the-art, high-assurance financial ecosystem designed to give users unprecedented control over their subscriptions, recurring payments, and virtual card expenditures. Built with a robust, highly scalable architecture, the platform comprises two primary front-end clients communicating with a centralized, secure backend infrastructure.

At its core, the ecosystem is divided into:
1. **The Gatekeeper Mobile Application**: A cross-platform Flutter application serving as the primary touchpoint for end-users. It offers features like virtual card creation, intelligent subscription detection, wallet management, and granular rule-based spending controls.
2. **The Gatekeeper Admin Portal (`gatekeeper-admin`)**: A comprehensive Next.js 16 web application utilizing NextAuth v5 for enterprise-grade administration. It provides administrative oversight, fraud detection, compliance management, reconciliation, and emergency security controls (such as the Kill Switch).
3. **The Backend Infrastructure**: Powered heavily by Firebase (Firestore, Firebase Auth, Cloud Functions) and deeply integrated with third-party banking and card-issuing providers.

### 1.1. Core Issuing Infrastructure
- **Bridgecard**: Utilized for Virtual USD card issuance and international transactions.
- **Sudo Africa**: The primary infrastructure for NGN Virtual Cards (Verve/Mastercard), recently migrated to solve stability and issuance bottlenecks.

The fundamental philosophy driving Gatekeeper is the **"Zero Auto-Debit" Security Architecture**. This architecture ensures that no user is ever caught off-guard by unauthorized, forgotten, or hidden subscription charges. By default, virtual cards can be placed in a "Dynamic Freeze" state, and every transaction is strictly evaluated against user-defined, highly customizable rules.

### 1.2. Core Technologies
- **Mobile Frontend**: Flutter, Riverpod (for state management, visible through the extensive use of `_provider.dart` files), dynamic theming, and local biometric authentication.
- **Admin Frontend**: Next.js (App Router), Tailwind CSS, Server Actions, React Server Components.
- **Backend/Database**: Firebase Cloud Firestore (NoSQL document structure), Firebase Authentication (Custom Claims for RBAC), Firebase Cloud Messaging (Push Notifications).
- **External Integrations**: Sudo Africa & Bridgecard APIs (Card Issuance and Processing), QoreID/SmileID (Identity verification), Paystack/Local Gateways (Wallet Funding).

---

## 2. Mobile User Journey: Authentication, Onboarding, and Identity Lifecycle

### 2.1. Authentication and Security Setup
The entry point into the Gatekeeper ecosystem is highly secured and optimized for friction-less onboarding.
- **Multi-Gate Auth**: Supports Phone (SMS OTP) and Email authentication.
- **Pin & Biometrics**: Users establish a cryptographic PIN and link FaceID/Fingerprint for high-risk actions (e.g., revealing card details or funding cards).

### 2.2. KYC Verification and Compliance Logic
Financial applications require strict compliance. Gatekeeper employs a **High-Availability KYC Strategy**:
1. **Local Data Capture**: The `BvnVerificationScreen` prompts the user for their 11-digit Bank Verification Number.
2. **Onboarding Uptime (The "Bypass")**: To prevent onboarding friction caused by third-party API downtime, Gatekeeper performs a local "soft-verification" that allows the user to complete their profile and explore the app immediately. 
3. **Provider-Side Validation**: All captured KYC data (BVN, NIN, Address, Selfie) is passed directly to **Sudo Africa** or **Bridgecard** during the customer registration phase (`ensureSudoCustomer`). 
4. **The Ultimate Gate**: Final validation is performed by the issuing provider against national databases (NIBSS). If the data is invalid, card issuance will fail, ensuring that no unauthorized user can access financial assets while legitimate users enjoy 100% onboarding uptime.

---

## 3. The Central Dashboard: Command and Control

The `DashboardScreen` is the nerve center of the Gatekeeper app, providing immediate, actionable intelligence.
- **Hello User Protocol**: Personalized greeting synced from Firestore.
- **Balance Card**: Beautifully stylized widget showing global wallet balance (NGN/USD).
- **Active Alerts**: Surfaces blocked charges or low-balance warnings in real-time.
- **Quick Access**: Direct links to "My Cards," "Analytics," and "Detection Engine."

---

## 4. Wallet Management: The Financial Core

The Wallet module acts as the funding source for all virtual cards, managed by the `WalletProvider`.
- **Funding Sources**: Supports Bank Transfer (Static Virtual Accounts via Paystack/Wema), and Card Deposits.
- **Biometric-Gated Transfers**: Moving funds from the main Wallet to a Virtual Card is strictly biometric-gated. This ensures funds cannot be moved without the user's physical presence, even if the device is unlocked.

---

## 5. The Virtual Card Engine: Sudo and Bridgecard Integration

The virtual card engine allows users to spawn fully functional cards, heavily augmented with proprietary spending rules.

### 5.1. NGN Cards (Sudo Africa Migration)
Gatekeeper recently migrated NGN card issuance to **Sudo Africa** using a **Gateway (Pool) Funding** model.
- **Pool Funding**: Eliminates the need for individual sub-accounts, resolving previous "sub-account creation not allowed" errors.
- **JIT (Just-In-Time) Authorization**: The backend utilizes a Sudo Webhook to perform real-time balance checks. When a card is charged, the system atomically checks the user's main wallet and the card's allocated limit before approving the transaction.

### 5.2. Advanced Card Rules
Users create programmable money constraints via the `CardRule` engine:
- **`max_per_txn`**: Caps single transaction amounts.
- **`monthly_cap`**: Limits total spend over 30 days.
- **`max_charges`**: Creates "Burner" cards (e.g., single-use cards).
- **`night_lockdown`**: Prevents charges during nighttime hours.
- **`block_if_amount_changes`**: Protects against silent subscription price hikes.

---

## 6. The Subscription Detection Engine

Intelligent machine learning engine managed by `DetectionProvider`.
- **How it Works**: Analyzes transaction descriptions (e.g., "Netflix", "Spotify") from linked accounts or SMS alerts.
- **Port to Gatekeeper**: Users can instantly convert a detected subscription into a dedicated Gatekeeper virtual card with pre-configured rules matching the merchant's billing cycle.

---

## 7. Deep Analytics and Financial Insights

- **Efficiency Portfolio**: Tracks "wasted" money from overlapping or unused subscriptions and provides an "Efficiency Score."
- **Savings Deep Dive**: Visualizes the total amount saved by Gatekeeper's rule engine blocking unauthorized or unexpected charges.

---

## 8. Gatekeeper Admin Portal: The Next.js Command Center

The administrative suite for internal operations, support, and security teams.
- **RBAC**: 12-role access control (Super Admin, Fraud, Compliance, Support).
- **Kill-Switch**: Emergency control to instantly freeze all cards and revoke all sessions in case of a systemic attack.
- **Compliance Inbox**: A manual review queue for flagged accounts where automated provider-side KYC validation requires human intervention.
- **Health Telemetry**: Real-time monitoring of Sudo/Bridgecard API uptime and internal system latency.

---

## 9. Conclusion

By combining a high-assurance Flutter mobile application with a robust Next.js administrative suite, Gatekeeper provides unparalleled control over digital spending. The migration to Sudo Africa and the implementation of a resilient, provider-delegated KYC flow ensures that the platform remains stable, compliant, and user-centric, maintaining the "Zero Auto-Debit" promise for all users.
