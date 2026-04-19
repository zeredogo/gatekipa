// functions/services/paystackService.js
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getMessaging } = require("firebase-admin/messaging");
const axios = require("axios");
const logger = require("firebase-functions/logger");

const PAYSTACK_SECRET_KEY = defineSecret("PAYSTACK_SECRET_KEY");


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
    secrets: [PAYSTACK_SECRET_KEY]
  },
  async (request) => {

    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { reference } = request.data;

    requireFields(request.data, ["reference"]);

    // ── Verify with Paystack ───────────────────────────────────────────────────
    const secretKey = PAYSTACK_SECRET_KEY.value();

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

        // Immutable Ledger Log
        const ledgerRef = db.collection("users").doc(uid).collection("wallet_transactions").doc(reference);
        t.set(ledgerRef, {
          id: reference,
          type: "credit",
          amount: verifiedAmount,
          method: "paystack",
          status: "completed",
          timestamp: Date.now()
        });
        
        logger.info(`[Paystack] verifyPaystackPayment: Successfully credited ${verifiedAmount} to UID ${uid}`);
      });
    } catch (e) {
      logger.error(`[Paystack] verifyPaystackPayment transaction failed: ${e.message}`, e);
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
exports.paystackWebhook = onRequest(
  {
    region: "us-central1",
    secrets: [PAYSTACK_SECRET_KEY]
  },
  async (req, res) => {
    // Only accept POST requests
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed" });
    }

    const crypto = require("crypto");
    const secretKey = PAYSTACK_SECRET_KEY.value();

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

    // Route by payment type
      if (event.event === "charge.success") {
      const data = event.data;
      const reference = data.reference;
      const amountKobo = data.amount;
      const uid = data.metadata?.uid;
      const plan = data.metadata?.plan; // set when purchasing a plan

      if (!uid) {
        console.warn(`[Paystack Webhook] Missing metadata.uid for ref: ${reference}`);
        return res.status(200).json({ status: "ignored_missing_uid" });
      }

      if (plan && ["free", "activation", "premium", "business"].includes(plan)) {
        // ── Plan purchase webhook failsafe ─────────────────────────────────────
        const planConfig = {
          free:       { price: 700,  cards: 1 },
          activation: { price: 1400, cards: 2 },
          premium:    { price: 2000, cards: 3 },
          business:   { price: 5000, cards: 5 },
        };

        const userRef        = db.collection("users").doc(uid);
        const idempotencyRef = db.collection("users").doc(uid).collection("plan_purchases").doc(reference);

        try {
          await db.runTransaction(async (t) => {
            const existing = await t.get(idempotencyRef);
            if (existing.exists) throw new Error("ALREADY_PROCESSED");

            t.set(idempotencyRef, {
              reference, plan,
              amountKobo,
              status: "success",
              timestamp: Date.now(),
              source: "webhook",
            });

            t.set(userRef, {
              planTier: plan,
              cardsIncluded: planConfig[plan].cards,
            }, { merge: true });
          });

          logger.info(`[Paystack Webhook] Plan '${plan}' activated for UID ${uid} via ref ${reference}`);

          // Push notification
          try {
            const uDoc = await db.collection("users").doc(uid).get();
            const fcmToken = uDoc.data()?.fcm_token;
            if (fcmToken) {
              await getMessaging().send({
                token: fcmToken,
                notification: {
                  title: `${plan.charAt(0).toUpperCase() + plan.slice(1)} Plan Activated! 🎉`,
                  body: `Your Gatekipa ${plan} plan is now active.`,
                },
                data: { type: "plan_activated", plan },
              });
            }
          } catch (_) { /* non-critical */ }

        } catch (e) {
          if (e.message !== "ALREADY_PROCESSED") {
            logger.error(`[Paystack Webhook] Plan activation failed for ${reference}:`, e);
            return res.status(500).json({ error: "Internal processing error" });
          }
        }

      } else {
        // ── Standard wallet top-up ─────────────────────────────────────────────
        const verifiedAmount = amountKobo / 100;

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

          // Immutable Ledger Log
          const ledgerRef = db.collection("users").doc(uid).collection("wallet_transactions").doc(reference);
          t.set(ledgerRef, {
            id: reference,
            type: "credit",
            amount: verifiedAmount,
            method: "paystack_webhook",
            status: "completed",
            timestamp: Date.now()
          });

          logger.info(`[Paystack Webhook] Successfully credited ${verifiedAmount} to UID ${uid}`);
          logger.info(`[Paystack Webhook] Successfully credited ${verifiedAmount} to UID ${uid}`);
        });

        // Outside atomic lock - trigger Push Notification
        try {
          const uDoc = await db.collection("users").doc(uid).get();
          const fcmToken = uDoc.data()?.fcm_token;
          if (fcmToken) {
            await getMessaging().send({
              token: fcmToken,
              notification: {
                title: `₦${verifiedAmount.toLocaleString()} Added!`,
                body: `Your wallet was successfully credited.`
              },
              data: { type: "wallet_funded", amount: String(verifiedAmount) }
            });
            logger.info(`[FCM] Sent wallet funding alert to UID ${uid}`);
          }
        } catch (fcmErr) {
          logger.error(`[FCM] Failed to send funding push alert to ${uid}:`, fcmErr);
        }

      } catch (e) {
        if (e.message !== "ALREADY_PROCESSED") {
          logger.error(`[Paystack Webhook] Transaction failed for ${reference}:`, e);
          return res.status(500).json({ error: "Internal processing error" });
        }
      }
      } // end wallet top-up
    } // end charge.success

    return res.status(200).json({ received: true });
  }
);
