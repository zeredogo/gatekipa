const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { db } = require("../utils/firebase");
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

    // ── 3. Send Welcome Email ───────────────────────────────────────────────
    if (data.email) {
      const emailHtml = `
        <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
          <h1 style="color: #1a1a1a;">Welcome to Gatekipa! 🚀</h1>
          <p>Hi ${data.display_name || data.name || "there"},</p>
          <p>Welcome to <strong>Gatekipa</strong>! We're thrilled to have you join us.</p>
          <p>Your wallet has been successfully initialized and you're ready to start taking control of your subscriptions.</p>
          <div style="background: #f4f4f5; padding: 20px; border-radius: 12px; margin: 20px 0;">
            <p style="margin: 0;">If you have any questions or need help exploring the platform, simply reply to this email or visit our help center.</p>
          </div>
          <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
        </div>
      `;
      
      // Dispatch non-blocking email
      sendEmail({
        to: data.email,
        subject: "Welcome to Gatekipa! 🎉",
        html: emailHtml,
      }).catch(err => console.error("Failed to send welcome email:", err));
    }
  }
);

// ── Secure Plan Upgrade via Paystack ───────────────────────────────────────
const { onCall, HttpsError } = require("firebase-functions/v2/https");

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
 *   premium    — ₦2,000
 *   business   — ₦5,000
 */
exports.purchasePlan = onCall(
  { region: "us-central1", enforceAppCheck: true, secrets: [PAYSTACK_SECRET_KEY] },
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
      premium:    { price: 2000, cards: 3 },
      business:   { price: 5000, cards: 5 },
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

        // Activate the plan
        t.set(userRef, {
          planTier: plan,
          cardsIncluded: cardsToAllocate,
        }, { merge: true });
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
