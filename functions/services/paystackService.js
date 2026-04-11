// functions/services/paystackService.js
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const axios = require("axios");

/**
 * verifyPaystackPayment
 *
 * Called by the Flutter app immediately after Paystack's client-side charge
 * succeeds. We verify the transaction reference server-side with the Paystack
 * secret key BEFORE crediting the wallet — the client cannot forge this.
 *
 * Setup: Add your Paystack secret key via Firebase Secret Manager:
 *   firebase functions:secrets:set PAYSTACK_SECRET_KEY
 * Or via .env in local development (functions/.env):
 *   PAYSTACK_SECRET_KEY=sk_test_xxxxx
 */
exports.verifyPaystackPayment = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
    // secrets: ["PAYSTACK_SECRET_KEY"],
  },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { reference } = request.data;

    requireFields(request.data, ["reference"]);

    // ── Verify with Paystack ───────────────────────────────────────────────────
    const secretKey =
      process.env.PAYSTACK_SECRET_KEY ||
      (request.app ? process.env.PAYSTACK_SECRET_KEY : null);

    if (!secretKey) {
      throw new HttpsError(
        "failed-precondition",
        "Payment verification is not configured. Contact support."
      );
    }

    let verifiedAmount;
    try {
      const response = await axios.get(
        `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
        {
          headers: {
            Authorization: `Bearer ${secretKey}`,
          },
        }
      );

      const { status, data } = response.data;

      if (!status || data.status !== "success") {
        throw new HttpsError(
          "failed-precondition",
          "Payment was not successful. Please try again."
        );
      }

      // Paystack returns amount in kobo (1 NGN = 100 kobo)
      verifiedAmount = data.amount / 100;

      if (verifiedAmount <= 0) {
        throw new HttpsError("invalid-argument", "Invalid payment amount.");
      }

      // Enforce Identity Parity (Crucial anti-spoofing mechanism)
      const paystackEmail = data.customer?.email?.toLowerCase();
      const userEmail = request.auth.token.email?.toLowerCase();
      
      if (!userEmail) {
        // Fallback to strict UID metadata verification if email is missing from Auth claims
        const txUid = data.metadata?.uid;
        if (txUid !== uid) {
          throw new HttpsError(
            "permission-denied",
            "Identity mismatch: Paystack transaction metadata UID does not match the active caller."
          );
        }
      } else if (paystackEmail !== userEmail) {
         throw new HttpsError(
           "permission-denied",
           "Identity mismatch: The Paystack transaction email does not match the active account."
         );
      }
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        `Failed to verify payment with Paystack: ${err.message}`
      );
    }

    // ── Record & credit atomically ─────────────────────────────────────────────
    const walletRef = db
      .collection("users")
      .doc(uid)
      .collection("wallet")
      .doc("balance");

    const idempotencyRef = db
      .collection("users")
      .doc(uid)
      .collection("funding_history")
      .doc(reference);

    try {
      await db.runTransaction(async (t) => {
        // Atomic Idempotency Guard - Must acquire lock inside transaction
        const existingTx = await t.get(idempotencyRef);
        if (existingTx.exists) {
          throw new Error("ALREADY_PROCESSED");
        }

        // Mark reference as processed (idempotency)
        t.set(idempotencyRef, {
          reference,
          amount: verifiedAmount,
          method: "paystack_card",
          status: "success",
          timestamp: Date.now(),
        });

        // Credit the wallet
        t.set(walletRef, { balance: FieldValue.increment(verifiedAmount) }, { merge: true });
      });
    } catch (e) {
      if (e.message === "ALREADY_PROCESSED") {
        throw new HttpsError("already-exists", "This payment has already been processed.");
      }
      throw new HttpsError("internal", "Failed to commit wallet funding transaction.");
    }

    return { success: true, amount_credited: verifiedAmount };
  }
);

/**
 * paystackWebhook
 *
 * HMAC-SHA512 verified listener for Paystack server-to-server events.
 * This guarantees the user's wallet is funded even if their connection
 * drops immediately after paying via the Paystack frontend overlay.
 */
exports.paystackWebhook = require("firebase-functions/v2/https").onRequest(
  { region: "us-central1" },
  async (req, res) => {
    // Only accept POST requests
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed" });
    }

    const crypto = require("crypto");
    const secretKey = process.env.PAYSTACK_SECRET_KEY;

    if (!secretKey) {
      console.error("PAYSTACK_SECRET_KEY is not configured.");
      return res.status(500).json({ error: "Configuration Error" });
    }

    // ── Verify HMAC signature ──────────────────────────────────────────────────
    const hash = crypto
      .createHmac("sha512", secretKey)
      .update(JSON.stringify(req.body))
      .digest("hex");

    if (hash !== req.headers["x-paystack-signature"]) {
      console.warn("[Paystack Webhook] Invalid signature");
      return res.status(401).json({ error: "Invalid signature" });
    }

    const event = req.body;
    console.info(`[Paystack Webhook] Processed event: ${event.event}`);

    // We only care about successful charges
    if (event.event === "charge.success") {
      const data = event.data;
      const reference = data.reference;
      const amountKobo = data.amount;
      const verifiedAmount = amountKobo / 100;
      
      const uid = data.metadata?.uid;

      // Without a target UID, we cannot route the funds
      if (!uid) {
        console.warn(`[Paystack Webhook] Missing metadata.uid for ref: ${reference}`);
        return res.status(200).json({ status: "ignored_missing_uid" });
      }

      // ── Record & credit atomically ─────────────────────────────────────────────
      const walletRef = db
        .collection("users")
        .doc(uid)
        .collection("wallet")
        .doc("balance");

      const idempotencyRef = db
        .collection("users")
        .doc(uid)
        .collection("funding_history")
        .doc(reference);

      try {
        await db.runTransaction(async (t) => {
          // Atomic Idempotency Guard - Must acquire lock inside transaction
          const existingTx = await t.get(idempotencyRef);
          if (existingTx.exists) {
            throw new Error("ALREADY_PROCESSED");
          }

          t.set(idempotencyRef, {
            reference,
            amount: verifiedAmount,
            method: "paystack_webhook",
            status: "success",
            timestamp: Date.now(),
          });

          // Credit the wallet
          t.set(
            walletRef,
            { balance: FieldValue.increment(verifiedAmount) },
            { merge: true }
          );
        });
      } catch (e) {
        if (e.message !== "ALREADY_PROCESSED") {
          console.error(`[Paystack Webhook] Transaction failed for ${reference}:`, e);
          return res.status(500).json({ error: "Internal processing error" });
        }
      }
    }

    return res.status(200).json({ received: true });
  }
);
