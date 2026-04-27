const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../utils/firebase");
const { requirePin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { sendEmail } = require("./emailService");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");
const logger = require("firebase-functions/logger");

const RESEND_API_KEY = defineSecret("RESEND_API_KEY");
const PAYSTACK_SECRET_KEY = defineSecret("PAYSTACK_SECRET_KEY");

/**
 * Triggered when a new user document is created in /users/{userId}.
 * - Normalises required fields (id, type, active_account_id)
 * - Idempotently initialises the user's wallet subcollection
 */
exports.onUserCreated = onDocumentCreated(
  { document: "users/{userId}", region: "us-central1", secrets: [RESEND_API_KEY] },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const userId = event.params.userId;
    const data = snap.data();

    // ── 1. Normalise top-level user fields ──────────────────────────────────
    const updates = {};
    if (!data.id)   updates.id   = userId;
    if (!data.type) updates.type = "individual";
    
    if (data.planTier === undefined) updates.planTier = "none";
    if (data.cardsIncluded === undefined) updates.cardsIncluded = 0;

    // Ensure server-side created_at is set (client may have sent epoch ms)
    if (!data.created_at) updates.created_at = FieldValue.serverTimestamp();

    // Initialise active_account_id to null if not already present
    if (data.active_account_id === undefined) {
      updates.active_account_id = null;
    }

    if (Object.keys(updates).length > 0) {
      await snap.ref.update(updates);
    }

    // ── 2. Idempotently initialise wallet balance doc ───────────────────────
    const walletRef = snap.ref.collection("wallet").doc("balance");
    const walletSnap = await walletRef.get();
    if (!walletSnap.exists) {
      await walletRef.set({
        user_id: userId,
        balance: 0,
        currency: "NGN",
        created_at: FieldValue.serverTimestamp(),
      });
    }

    // ── 3. Send Welcome & Verification Email ───────────────────────────────
    if (data.email) {
      try {
        const verifyLink = await admin.auth().generateEmailVerificationLink(data.email);

        const emailHtml = `
          <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
            <h1 style="color: #1a1a1a;">Welcome to Gatekipa! 🚀</h1>
            <p>Hi ${data.display_name || data.name || "there"},</p>
            <p>Welcome to <strong>Gatekipa</strong>! We're thrilled to have you join us.</p>
            <p>Your wallet has been successfully initialized. To fully unlock your account and start creating cards seamlessly, please verify your email address by clicking the link below:</p>
            
            <div style="text-align: center; margin: 30px 0;">
              <a href="${verifyLink}" style="background-color: #0d6efd; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block;">Verify Email Address</a>
            </div>

            <p style="font-size: 13px; color: #666;">If the button doesn't work, copy and paste this link into your browser:<br/>
            <a href="${verifyLink}" style="color: #0d6efd; word-break: break-all;">${verifyLink}</a></p>

            <div style="background: #f4f4f5; padding: 20px; border-radius: 12px; margin: 20px 0;">
              <p style="margin: 0;">If you have any questions or need help exploring the platform, simply reply to this email or visit our help center.</p>
            </div>
            <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
          </div>
        `;
        
        // Dispatch non-blocking email
        sendEmail({
          to: data.email,
          subject: "Action Required: Verify your Gatekipa Account 🎉",
          html: emailHtml,
        }).catch(err => logger.error("Failed to send welcome email:", err));
      } catch (e) {
        logger.error("Failed to generate verify link or send email:", e);
      }
    }
  }
);

// ── Manual Resend Verification Email ───────────────────────────────────────

exports.resendVerificationEmail = onCall(
  { region: "us-central1", secrets: [RESEND_API_KEY] },
  async (request) => {
    const uid = request.auth?.uid;
    const email = request.auth?.token?.email;
    if (!uid || !email) {
      throw new HttpsError("unauthenticated", "User must be authenticated with an email address.");
    }

    try {
      const verifyLink = await admin.auth().generateEmailVerificationLink(email);

      const emailHtml = `
        <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
          <h1 style="color: #1a1a1a;">Verify your Gatekipa Account 🚀</h1>
          <p>Hi,</p>
          <p>You recently requested to resend your email verification link.</p>
          <p>To fully unlock your account and start creating cards seamlessly, please verify your email address by clicking the link below:</p>
          
          <div style="text-align: center; margin: 30px 0;">
            <a href="${verifyLink}" style="background-color: #0d6efd; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block;">Verify Email Address</a>
          </div>

          <p style="font-size: 13px; color: #666;">If the button doesn't work, copy and paste this link into your browser:<br/>
          <a href="${verifyLink}" style="color: #0d6efd; word-break: break-all;">${verifyLink}</a></p>

          <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
        </div>
      `;
      
      // Dispatch non-blocking email
      await sendEmail({
        to: email,
        subject: "Action Required: Verify your Gatekipa Account 🎉",
        html: emailHtml,
      });

      return { success: true };
    } catch (e) {
      logger.error("[resendVerificationEmail] Failed to generate verify link or send email:", e);
      throw new HttpsError("internal", "Failed to send verification email.");
    }
  }
);

// ── Secure Password Reset via Resend ───────────────────────────────────────

exports.requestPasswordReset = onCall(
  { region: "us-central1", secrets: [RESEND_API_KEY] },
  async (request) => {
    const email = request.data?.email;
    if (!email) {
      throw new HttpsError("invalid-argument", "Email address is required.");
    }

    try {
      // 1. Generate the reset link via Firebase Admin
      const resetLink = await admin.auth().generatePasswordResetLink(email);

      // 2. Format a professional HTML email
      const emailHtml = `
        <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
          <h1 style="color: #1a1a1a;">Reset Your Password 🔒</h1>
          <p>Hi,</p>
          <p>We received a request to reset your Gatekipa password. If you didn't make this request, you can safely ignore this email.</p>
          <p>Click the secure link below to choose a new password:</p>
          
          <div style="text-align: center; margin: 30px 0;">
            <a href="${resetLink}" style="background-color: #027A48; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block;">Reset Password</a>
          </div>

          <p style="font-size: 13px; color: #666;">If the button doesn't work, copy and paste this link into your browser:<br/>
          <a href="${resetLink}" style="color: #027A48; word-break: break-all;">${resetLink}</a></p>

          <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
        </div>
      `;

      // 3. Dispatch non-blocking email via Resend
      await sendEmail({
        to: email,
        subject: "Action Required: Reset Your Gatekipa Password",
        html: emailHtml,
      });

      return { success: true };
    } catch (e) {
      logger.error("[requestPasswordReset] Failed to generate link or send email:", e);
      // We purposefully throw a generic error to prevent email enumeration
      throw new HttpsError("internal", "If your email is registered, a reset link will be sent.");
    }
  }
);

// ── Secure Plan Upgrade via Paystack ───────────────────────────────────────

/**
 * purchasePlan
 *
 * Verifies a Paystack payment reference server-side before activating the
 * user's plan tier. The Flutter client:
 *  1. Initiates a Paystack inline checkout (with metadata.uid & metadata.plan)
 *  2. On callback, calls this function with { reference, plan }
 *  3. We verify with Paystack, enforce identity parity, then atomically activate.
 *
 * Plan prices:
 *   free       — ₦700
 *   activation — ₦1,400
 *   premium    — ₦1,999  (Sentinel Prime)
 *   business   — ₦5,000  (Business Plan)
 */
exports.purchasePlan = onCall(
  { region: "us-central1", secrets: [PAYSTACK_SECRET_KEY] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "User must be authenticated.");

    const { plan, reference } = request.data;

    if (!["free", "activation", "premium", "business"].includes(plan)) {
      throw new HttpsError("invalid-argument", "Invalid plan type requested.");
    }
    if (!reference) {
      throw new HttpsError("invalid-argument", "Payment reference is required.");
    }

    const planConfig = {
      free:       { price: 700,  cards: 1 },
      activation: { price: 1400, cards: 2 },
      premium:    { price: 1999, cards: 3 },
      business:   { price: 5000, cards: 5 }, // Standardized ₦5000 recurring fee
    };

    const expectedAmountKobo = planConfig[plan].price * 100;
    const cardsToAllocate    = planConfig[plan].cards;

    // ── 1. Verify payment with Paystack ──────────────────────────────────────
    const secretKey = PAYSTACK_SECRET_KEY.value();
    if (!secretKey) {
      throw new HttpsError("failed-precondition", "Payment gateway not configured.");
    }

    let paystackData;
    try {
      const resp = await axios.get(
        `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
        { headers: { Authorization: `Bearer ${secretKey}` } }
      );
      const { status, data } = resp.data;
      if (!status || data.status !== "success") {
        throw new HttpsError("failed-precondition", "Payment was not successful.");
      }
      paystackData = data;
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[purchasePlan] Paystack verify error:", err.message);
      throw new HttpsError("internal", "Could not verify payment with Paystack.");
    }

    // ── 2. Identity & amount parity ──────────────────────────────────────────
    const metaUid = paystackData.metadata?.uid;
    if (metaUid && metaUid !== uid) {
      throw new HttpsError("permission-denied", "Payment does not belong to this account.");
    }

    const paidAmountKobo = paystackData.amount;
    if (paidAmountKobo < expectedAmountKobo) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient payment. Expected ₦${planConfig[plan].price}, received ₦${paidAmountKobo / 100}.`
      );
    }

    // ── 3. Idempotency guard + atomic plan activation ────────────────────────
    const userRef         = db.collection("users").doc(uid);
    const idempotencyRef  = db.collection("users").doc(uid).collection("plan_purchases").doc(reference);
    const ledgerRef       = db.collection("users").doc(uid)
                             .collection("wallet_transactions")
                             .doc(`plan_${plan}_${reference}`);

    try {
      await db.runTransaction(async (t) => {
        const existing = await t.get(idempotencyRef);
        if (existing.exists) throw new Error("ALREADY_PROCESSED");

        // Idempotency record
        t.set(idempotencyRef, {
          reference,
          plan,
          amountKobo: paidAmountKobo,
          status: "success",
          timestamp: Date.now(),
        });

        // Immutable ledger entry
        t.set(ledgerRef, {
          type: "debit",
          amount: paidAmountKobo / 100,
          status: "successful",
          context: "plan_purchase",
          method: "paystack",
          metadata: plan,
          reference,
          created_at: Date.now(),
        });

        const isTrial = (plan === "free" || plan === "activation");
        const updates = {
          planTier: plan,
          cardsIncluded: cardsToAllocate,
          subscription_expiry_date: Date.now() + (30 * 24 * 60 * 60 * 1000), // 30-day base plan
        };
        
        if (isTrial) {
          updates.sentinel_trial_expiry_date = Date.now() + (5 * 24 * 60 * 60 * 1000);
        }

        t.set(userRef, updates, { merge: true });
      });
    } catch (err) {
      if (err.message === "ALREADY_PROCESSED") {
        // Payment already applied — idempotent success
        return { success: true, newTier: plan, cardsIncluded: cardsToAllocate };
      }
      logger.error("[purchasePlan] Transaction failed:", err);
      throw new HttpsError("internal", "Failed to activate plan.");
    }

    logger.info(`[purchasePlan] UID ${uid} activated '${plan}' via ref ${reference}`);
    return { success: true, newTier: plan, cardsIncluded: cardsToAllocate };
  }
);

/**
 * purchasePlanFromVault
 *
 * Activates a plan by directly deducting from the user's wallet balance.
 */
exports.purchasePlanFromVault = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "User must be authenticated.");

    const { plan, pin } = request.data;
    if (!["free", "activation", "premium", "business"].includes(plan)) {
      throw new HttpsError("invalid-argument", "Invalid plan type requested.");
    }

    // SECURE TRANSACTION PIN ENFORCEMENT
    await requirePin(uid, pin);

    const planConfig = {
      free:       { price: 700,  cards: 1 },
      activation: { price: 1400, cards: 2 },
      premium:    { price: 1999, cards: 3 },
      business:   { price: 5000, cards: 5 }, // Standardized ₦5000 recurring fee
    };

    const cost = planConfig[plan].price;
    const cardsToAllocate = planConfig[plan].cards;

    const userRef    = db.collection("users").doc(uid);
    const walletRef  = userRef.collection("wallet").doc("balance");
    const reference  = `VAULT-PLAN-${Date.now()}`;
    const ledgerRef  = userRef.collection("wallet_transactions").doc(`plan_${plan}_${reference}`);

    try {
      await db.runTransaction(async (t) => {
        const walletSnap = await t.get(walletRef);
        if (!walletSnap.exists) throw new Error("WALLET_NOT_INITIALIZED");
        
        const walletData = walletSnap.data() || {};
        const currentBalanceKobo = walletData.balance_kobo 
          ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
          
        const currentBalanceNgn = currentBalanceKobo / 100;
        
        if (currentBalanceNgn < cost) throw new Error("INSUFFICIENT_FUNDS");

        const costKobo = Math.round(cost * 100);

        // Deduct from wallet (Dual Write)
        t.update(walletRef, { 
          balance_kobo: FieldValue.increment(-costKobo),
          cached_balance: FieldValue.increment(-cost),
          balance: FieldValue.increment(-cost)
        });

        // 1. Immutable ledger entry
        t.set(ledgerRef, {
          type: "debit",
          amount: cost,
          status: "successful",
          context: "plan_purchase",
          method: "vault",
          metadata: plan,
          reference,
          created_at: Date.now(),
        });

        // 2. Activate the plan
        const isTrial = (plan === "free" || plan === "activation");
        const updates = {
          planTier: plan,
          cardsIncluded: cardsToAllocate,
          subscription_expiry_date: Date.now() + (30 * 24 * 60 * 60 * 1000), // 30-day base plan
        };
        
        if (isTrial) {
          updates.sentinel_trial_expiry_date = Date.now() + (5 * 24 * 60 * 60 * 1000);
        }

        t.set(userRef, updates, { merge: true });
      });
    } catch (err) {
      if (err.message === "WALLET_NOT_INITIALIZED") {
        throw new HttpsError("failed-precondition", "Your wallet has not been set up yet. Please contact support or restart the app.");
      }
      if (err.message === "INSUFFICIENT_FUNDS") {
        throw new HttpsError("failed-precondition", "Insufficient funds in your vault. Please top up and try again.");
      }
      logger.error("[purchasePlanFromVault] Transaction failed:", err);
      throw new HttpsError("internal", "Failed to activate plan from vault.");
    }

    logger.info(`[purchasePlanFromVault] UID ${uid} activated '${plan}' from vault`);
    return { success: true, newTier: plan, cardsIncluded: cardsToAllocate };
  }
);
