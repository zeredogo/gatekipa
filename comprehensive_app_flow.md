# Gatekeeper Platform: Comprehensive Application Flow and Feature Documentation

## 1. Executive Summary and Architectural Overview

The Gatekeeper platform is a state-of-the-art, high-assurance financial ecosystem designed to give users unprecedented control over their subscriptions, recurring payments, and virtual card expenditures. Built with a robust, highly scalable architecture, the platform comprises two primary front-end clients communicating with a centralized, secure backend infrastructure.

At its core, the ecosystem is divided into:
1. **The Gatekeeper Mobile Application**: A cross-platform Flutter application serving as the primary touchpoint for end-users. It offers features like virtual card creation, intelligent subscription detection, wallet management, and granular rule-based spending controls.
2. **The Gatekeeper Admin Portal (`gatekeeper-admin`)**: A comprehensive Next.js 16 web application utilizing NextAuth v5 for enterprise-grade administration. It provides administrative oversight, fraud detection, compliance management, reconciliation, and emergency security controls (such as the Kill Switch).
3. **The Backend Infrastructure**: Powered heavily by Firebase (Firestore, Firebase Auth, Cloud Functions) and deeply integrated with third-party banking and card-issuing providers (specifically Bridgecard for virtual USD/NGN card issuance).

The fundamental philosophy driving Gatekeeper is the **"Zero Auto-Debit" Security Architecture**. This architecture ensures that no user is ever caught off-guard by unauthorized, forgotten, or hidden subscription charges. By default, virtual cards can be placed in a "Dynamic Freeze" state, and every transaction is strictly evaluated against user-defined, highly customizable rules.

### 1.1. Core Technologies
- **Mobile Frontend**: Flutter, Riverpod (for state management, visible through the extensive use of `_provider.dart` files), dynamic theming, and local biometric authentication.
- **Admin Frontend**: Next.js (App Router), Tailwind CSS, Server Actions, React Server Components.
- **Backend/Database**: Firebase Cloud Firestore (NoSQL document structure), Firebase Authentication (Custom Claims for RBAC), Firebase Cloud Messaging (Push Notifications).
- **External Integrations**: Bridgecard API (Card Issuance and Processing), QoreID/Local verification (BVN/NIN), Paystack/Local Gateways (Wallet Funding).

This document serves as an exhaustive, 4000+ word deep dive into every single flow, feature, data model, and user journey within both the mobile app and the administrative portal.

---

## 2. Mobile User Journey: Authentication, Onboarding, and Identity Lifecycle

The entry point into the Gatekeeper ecosystem is highly secured and optimized for friction-less onboarding while maintaining strict Know Your Customer (KYC) compliance.

### 2.1. The Launch and Splash Experience
When the user launches the application, the `SplashScreen` initializes the app's critical services. During this phase, the app checks the local secure storage for existing session tokens and queries the `AuthProvider` to determine the user's current authentication state. If a session exists, the app evaluates whether the user's biometric token is valid and whether their KYC status is complete.

### 2.2. The Onboarding Carousel
For first-time users, the `OnboardingScreen` presents a visually immersive, beautifully designed carousel utilizing dynamic animations and glassmorphism elements. This flow highlights the core value propositions:
- **"Stop Unwanted Charges"**: Visualizing the Zero Auto-Debit architecture.
- **"Smart Virtual Cards"**: Introducing Bridgecard-powered disposable and rule-based cards.
- **"Deep Analytics"**: Showcasing the savings and efficiency metrics the app provides.

### 2.3. Authentication Flows
Gatekeeper supports a multi-gate authentication strategy to ensure flexibility and security.
- **Phone Authentication (`PhoneAuthScreen` & `OtpScreen`)**: Users enter their mobile number. Firebase Auth sends an OTP via SMS. The `OtpScreen` securely captures this input, verifying it against Firebase. This is the primary identity anchor for many local users.
- **Email Authentication (`EmailAuthScreen` & `EmailVerifyPendingScreen`)**: Alternatively, or additionally, users can sign up using their email. If an email is used, the system places the user in a "pending verification" state until they click the magic link sent to their inbox, actively tracked by the `EmailVerifyPendingScreen`.

### 2.4. KYC Verification and Compliance
Financial applications require strict compliance. The `KycScreen`, `KycVerificationScreen`, and `BvnVerificationScreen` orchestrate this process.
1. **Tier 1 (Basic)**: Requires basic profile information and email verification.
2. **Tier 2 (BVN/NIN)**: The `BvnVerificationScreen` prompts the user for their Bank Verification Number or National Identity Number. The system validates this data against backend APIs (such as QoreID). Due to historical stability issues with third-party providers, the platform has implemented robust fallback mechanisms and "bypasses" that allow onboarding to proceed gracefully while flagging the account for administrative review in the `gatekeeper-admin` portal.

### 2.5. Profile and Security Setup
Once authenticated and verified, the user establishes their local security parameters.
- **Pin Management (`PinManagementScreen`)**: The user sets a 4 or 6-digit cryptographic PIN used to authorize high-risk actions (like viewing a virtual card's CVV or transferring funds).
- **Biometrics (`BiometricsScreen`)**: The app strongly encourages linking FaceID or Fingerprint authentication. The biometric signature is tied to the local device keychain, enabling "Biometric-gated wallet-to-card funding." This ensures that even if the app is left open, funds cannot be moved without physical presence.
- **Premium Upgrade (`PremiumUpgradeScreen`)**: The user is presented with subscription tiers. The standard Premium plan is standardized at ₦1,999/month, offering higher virtual card limits, advanced rule creation, and a 30-day lifecycle management for Business cards.

---

## 3. The Central Dashboard: Command and Control

The `DashboardScreen` is the nerve center of the Gatekeeper app. It is designed to provide immediate, actionable intelligence to the user at a single glance.

### 3.1. Dashboard UI Components
- **Top Bar**: Displays a personalized greeting (using the "Hello User" display name protocol synced from Firestore), notification bell with an unread badge indicator, and quick access to the user's profile avatar.
- **Balance Card**: A prominent, beautifully stylized widget showing the user's global wallet balance. It includes quick-action buttons for "Add Funds," "Withdraw," and "Transfer."
- **Active Alerts**: Immediately below the balance, the dashboard surfaces critical, time-sensitive alerts. For example, if an auto-debit attempt was blocked by a rule, an alert ("Spotify charge of $9.99 blocked - Insufficient Card Limit") is displayed here.
- **Recent Activity**: A consolidated feed of transactions across all virtual cards and the main wallet. It uses iconography to distinguish between wallet funding, successful card charges, blocked charges, and subscription renewals.
- **Quick Access Grid**: Large, tappable areas leading to "My Cards," "Analytics," "Detection Engine," and "Settings."

### 3.2. Global Search Interface
The `SearchScreen` and `SearchBarWidget` provide instantaneous, global search capabilities across the user's entire dataset. Leveraging a specialized `SearchProvider`, the user can type a merchant name (e.g., "Netflix"), a specific transaction amount, or a card name. The search engine queries local SQLite caches (for speed) and falls back to Firestore for deep historical searches, presenting results categorized by Transactions, Cards, and Notifications.

---

## 4. Wallet Management: The Financial Core

The Wallet module is responsible for the user's primary fiat balance, acting as the funding source for all virtual cards. The logic is strictly defined in the `WalletModel` and managed by the `WalletProvider`.

### 4.1. The Wallet Data Model
The `WalletModel` encapsulates the user's financial state:
- `userId`: The unique identifier linking to the `accounts` collection.
- `balance`: A double precision float representing the available fiat.
- `currency`: Primarily defaulted to 'NGN' (Nigerian Naira) or 'USD' depending on the user's locale and tier.
- `lastFunded`: A timestamp of the most recent successful deposit.
- `isLocked`: A critical security boolean. If true (triggered either by the user or by the Admin Fraud team), no outgoing transactions can occur.

### 4.2. Adding Funds and Withdrawals
The `AddFundsScreen` provides multiple avenues to deposit money into the Gatekeeper ecosystem:
- **Bank Transfer**: The app generates a dedicated, static virtual bank account number (via partners like Paystack, Wema, or Monnify) assigned uniquely to the user.
- **Card Deposit**: Users can bind a traditional debit/credit card to top up their wallet instantly.
The `WalletScreen` displays the full transaction ledger specific to the wallet, separating it from virtual card expenditures.

### 4.3. Biometric-Gated Wallet-to-Card Funding
A cornerstone of the platform's security is how funds move from the main Wallet to individual Virtual Cards. Because virtual cards can be heavily exposed online, users must explicitly allocate funds to them. This action is **strictly biometric-gated**. The `WalletProvider` intercepts the transfer request, calls the native device biometrics API, and only upon successful authentication does it commit the atomic transaction in Firestore, debiting the wallet and crediting the card balance.

---

## 5. The Virtual Card Engine: Granular Control and Bridgecard Integration

The virtual card engine is the most complex and powerful feature of the Gatekeeper platform. It allows users to spawn fully functional Visa/Mastercard virtual cards powered by Bridgecard, heavily augmented with proprietary spending rules.

### 5.1. The VirtualCardModel
The `VirtualCardModel` is a rich data structure stored in the `cards` top-level collection. Key attributes include:
- **Core Identifiers**: `id`, `accountId`, `name` (e.g., "Netflix Card", "AWS Hosting").
- **Status Enum**: `active`, `blocked`, `expired`, `pending_issuance`, `frozen`. The `frozen` state is part of the "Dynamic Freeze" default-deny architecture.
- **Bridgecard Metadata**: `bridgecardCardId`, `bridgecardStatus`, `bridgecardCurrency`. This ensures complete synchronization with the issuing partner.
- **Financial State**: `balanceLimit`, `spentAmount`, `chargeCount`.
- **Security Features**: `last4`, `maskedNumber`, and an encrypted `cvv` (only revealed after PIN/Biometric auth).

### 5.2. Advanced Card Rules and Constraints
What separates Gatekeeper from standard fintech apps is the `CardRule` engine. Users do not just create cards; they create programmable money constraints. The `CardRule` model supports various `subType` enums:
- **`max_per_txn`**: Hard cap on a single transaction amount.
- **`monthly_cap`**: Hard limit on total spend over a 30-day rolling window.
- **`expiry_date` & `valid_duration`**: Time-bombing a card. A user can create a card that ceases to function exactly 48 hours after creation.
- **`max_charges`**: "Burner" mode. Setting this to `1` creates a true single-use virtual card. If a merchant tries to charge it a second time, it automatically declines.
- **`block_after_first`**: Similar to max charges, specifically designed for free trials.
- **`block_if_amount_changes`**: A highly specialized feature that locks the card to the exact amount of the first authorization. If Netflix raises its price from $15.99 to $17.99, the transaction is rejected, protecting the user from silent price hikes.
- **`night_lockdown`**: Prevents the card from being charged between user-defined nighttime hours (e.g., 12 AM to 6 AM) to prevent nocturnal fraud.

### 5.3. Card Creation and Lifecycle Flow
The `CardCreationScreen` walks the user through a guided wizard:
1. **Purpose Selection**: Choose between a Subscription card, an E-commerce card, or a Burner card.
2. **Rule Configuration**: The UI dynamically updates based on the purpose, suggesting constraints like "Block after 1 charge" for Burner cards.
3. **Funding**: The user allocates an initial balance limit from their main wallet.
4. **Issuance**: The app communicates with the Firebase Cloud Functions backend, which in turn orchestrates the API call to Bridgecard. Upon successful callback, the card is instantly available.

In the `CardDetailScreen`, users can perform lifecycle actions: Freeze/Unfreeze, Terminate, Reveal Details, or Update Rules. The "Dynamic Freeze" architecture encourages users to keep cards frozen until the exact moment they need to make a purchase, virtually eliminating the risk of stolen card details being exploited.

---

## 6. The Subscription Detection Engine

One of the most innovative features is the intelligent detection engine, managed by the `DetectionProvider` and visualized in the `DetectedSubscriptionsScreen` and `DetectionSetupScreen`.

### 6.1. How Detection Works
Many users do not know exactly how many subscriptions they have. Gatekeeper solves this by analyzing the user's linked bank account data or SMS transaction alerts (where OS permissions allow, primarily on Android). 
The `DetectionProvider` utilizes a lightweight, local on-device machine learning parser to identify recurring patterns in transaction descriptions (e.g., detecting keywords like "AMZN Prime", "Spotify", "Netflix", "Apple").

### 6.2. The User Flow
In the `DetectionSetupScreen`, the user grants the necessary permissions. The engine then scans historical data and populates the `DetectedSubscriptionsScreen`. This screen presents a list of recognized subscriptions, the estimated next billing date, and the historical cost.

Crucially, the user can tap on any detected subscription and instantly select "Port to Gatekeeper". This triggers a workflow that generates a dedicated Virtual Card specifically pre-configured with rules matching that exact subscription (e.g., creating a card with a monthly cap of $16 specifically for Netflix). The app then provides instructions to the user on how to update their payment method on the merchant's site.

---

## 7. Deep Analytics and Financial Insights

Gatekeeper is not just a payment gateway; it is a financial intelligence platform. The `AnalyticsHubScreen` acts as the command center for this data.

### 7.1. Efficiency Portfolio
The `EfficiencyPortfolioScreen` tracks "wasted" money. If a user has a subscription that they haven't interacted with, or if they have multiple overlapping subscriptions (e.g., three different music streaming services), the analytics engine flags this. It calculates an "Efficiency Score" out of 100.

### 7.2. Savings Deep Dive
The `SavingsDeepDiveScreen` is the psychological reward center of the app. Every time the `CardRule` engine blocks an unauthorized charge (e.g., a free trial attempting to convert to a paid plan because the `block_after_first` rule was active), the amount of that blocked transaction is added to the "Total Money Saved" metric.
This screen visualizes these savings over time with interactive charts. It also powers the automated "Savings Insights" push notifications ("Gatekeeper just saved you ₦4,500 by blocking an unexpected auto-debit!").

---

## 8. Notifications and Real-time Communication

The `NotificationCenterScreen` and `NotificationDetailScreen` are driven by the `NotificationProvider` and deeply integrated with Firebase Cloud Messaging (FCM).

### 8.1. Notification Architecture
Notifications in Gatekeeper are highly structured events represented by the `NotificationModel`. They are categorized into:
- **Transactional**: Funds added, withdrawals completed.
- **Security**: Failed login attempts, new device sign-ins.
- **Rule Breaches**: A transaction was declined due to hitting a `monthly_cap` or `night_lockdown`.
- **Lifecycle**: 5/3/2-day proactive renewal notifications. For example, if a user has an active subscription virtual card, the system will send push notifications 5 days, 3 days, and 2 days before the expected charge date, reminding them to ensure sufficient wallet balance or to freeze the card if they wish to cancel.

---

## 9. Gatekeeper Admin Portal (`gatekeeper-admin`): The Next.js Command Center

The administrative side of the platform is a robust Next.js web application designed for the internal operations, support, and security teams. It utilizes React Server Components and Server Actions to securely interact directly with the Firebase Admin SDK and PostgreSQL analytics databases.

### 9.1. Authentication and RBAC
The `login/page.tsx` and `api/auth/route.ts` manage staff access. Standard Firebase Client SDK authentication is explicitly bypassed for internal routes to prevent client-side manipulation. Instead, authentication relies on HTTP-only Session Cookies generated via the Firebase Admin SDK.
Access is strictly governed by a 12-role RBAC (Role-Based Access Control) system (e.g., Super Admin, L1 Support, L2 Fraud, Compliance Officer). A user's Custom Claims dictate which Next.js routes they can access.

### 9.2. Dashboard Layout and Navigation
The `layout.tsx` within the `(dashboard)` group provides a persistent sidebar. The navigation structure reflects the operational departments:
- **Users**: Search, view, suspend, or ban user accounts. The `users/[id]/page.tsx` provides a 360-degree view of a user's wallet balance, card inventory, and recent activity.
- **Cards**: Global oversight of all issued Bridgecard virtual cards. Admins can view the aggregate exposure and monitor for anomalous velocity (e.g., hundreds of cards created in minutes).
- **Transactions & Reconciliation**: The `transactions/page.tsx` and `reconciliation/page.tsx` are critical for the finance team. They ensure parity between the internal Gatekeeper ledger (Firestore) and the issuing partner's ledger (Bridgecard). Any discrepancies are flagged in the reconciliation queue.
- **Compliance & Fraud**: The `compliance/page.tsx` acts as the inbox for manual KYC review (e.g., when the BVN bypass is used during onboarding). The `fraud/page.tsx` utilizes algorithmic flags to identify high-risk accounts.

### 9.3. The Ultimate Security Control: The Kill-Switch
Located at `kill-switch/page.tsx` and backed by the highly restricted `api/kill-switch/route.ts`, the Kill-Switch is a super-admin-only feature designed for catastrophic scenarios.
If the platform detects a massive BIN attack, an exploit in the Bridgecard API, or a systemic failure, an authorized executive can activate the Kill-Switch. This instantly executes a distributed Cloud Function that:
1. Revokes all active user session tokens.
2. Changes the status of every active Virtual Card in the database to `frozen`.
3. Disables all wallet deposit endpoints.
This ensures that the platform "fails closed," preventing financial hemorrhage while the engineering team investigates.

### 9.4. E2E, Health, and Rules Modules
- **`health/page.tsx`**: A Grafana-style dashboard surfacing real-time telemetry from Firebase, Bridgecard API uptime, and internal system latency.
- **`rules/page.tsx`**: Allows operations teams to adjust global platform rules, such as temporarily lowering the maximum deposit limit during high-risk periods.
- **`webhooks/page.tsx`**: An interface to monitor incoming webhooks from Bridgecard and Paystack, ensuring that asynchronous events (like a delayed transaction settlement) are correctly processed by the backend.

---

## 10. Core Technical Workflows and Data Consistency

To ensure the system remains perfectly synchronized across the mobile app, the admin portal, and external providers, several technical workflows are rigorously enforced.

### 10.1. Atomic Transactions and The Data Paradox
Financial operations (like funding a virtual card from the main wallet) must be perfectly atomic. The backend utilizes Firestore Transactions to ensure that the debit from the `WalletModel` and the credit to the `VirtualCardModel` succeed or fail together. This prevents the "Data Paradox" where a user's wallet is deducted but the card is not funded.

### 10.2. Real-time Synchronization
The mobile app relies heavily on Riverpod Providers listening to Firestore streams. When an admin in the `gatekeeper-admin` portal clicks "Freeze" on a user's card via `cards/[id]/page.tsx`, that change is written to Firestore. The `VirtualCardModel` stream in the user's mobile app instantly detects this update, and the UI dynamically reflects the card as "Frozen" in less than 300 milliseconds, without requiring a pull-to-refresh.

### 10.3. Environment Configuration and Deployment
The Next.js admin portal is deployed on Vercel. Because it utilizes the Firebase Admin SDK, it requires secure injection of service account private keys. The system employs a specialized private key parser to handle escaped newlines in Vercel's environment variables (`\n`), a common failure point that historically led to "Unauthenticated" runtime exceptions. This ensures robust, production-grade stability across deployments.

## 11. Conclusion

The Gatekeeper platform represents a paradigm shift in personal subscription and expense management. By combining a highly responsive, user-centric Flutter mobile application with an enterprise-grade Next.js administrative suite, the ecosystem operates with unparalleled security, transparency, and control. 

From the biometric-gated wallet flows and the intricate rule-based Bridgecard integrations to the overarching Zero Auto-Debit architecture and the emergency Kill-Switch mechanism, every single feature has been meticulously designed to protect the user's financial assets and provide deep, actionable insights into their spending behavior. The extensive use of modern web and mobile frameworks ensures that the platform is not only beautiful and engaging but also exceptionally resilient and scalable for the future.
