// functions/services/paystackService.js
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getMessaging } = require("firebase-admin/messaging");
const axios = require("axios");
const logger = require("firebase-functions/logger");
// Import the orchestrator — all wallet mutations go through it
const { processTransactionInternal } = require("./transactionService");


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
      // FIX: Only reject when Paystack actually returns a customer email AND it mismatches.
      // Old code: `paystackEmail !== userEmail` threw permission-denied when Paystack
      // returned null for the customer email field (no customer object on DVA top-ups).
      const paystackEmail = data.customer?.email?.toLowerCase();
      const userEmail = request.auth.token.email?.toLowerCase();

      if (!userEmail) {
        // Fallback: no email on Auth token — verify via UID in transaction metadata
        const txUid = data.metadata?.uid;
        if (txUid !== uid) {
          throw new HttpsError(
            "permission-denied",
            "Identity mismatch: Paystack transaction metadata UID does not match the active caller."
          );
        }
      } else if (paystackEmail && paystackEmail !== userEmail) {
        // Only enforce when Paystack actually returned a customer email
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

    // ── Route through orchestrator ──────────────────────────────────────────────
    // Idempotency key = Paystack reference. Prevents double credit on retries.
    try {
      await processTransactionInternal({
        type: "wallet_funding",
        userId: uid,
        amount: verifiedAmount,
        idempotencyKey: `${uid}:wallet_funding:${reference}`,
        metadata: { paystackRef: reference, source: "paystack" },
        correlationId: `verifyPaystackPayment:${uid}:${reference}`,
      });
    } catch (e) {
      logger.error(`[Paystack] processTransactionInternal failed: ${e.message}`, e);
      if (e.message?.includes("idempotent")) {
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
    secrets: [PAYSTACK_SECRET_KEY],
    enforceAppCheck: false
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
      .update(req.rawBody)
      .digest("hex");

    if (hash !== req.headers["x-paystack-signature"]) {
      console.warn("[Paystack Webhook] Invalid signature");
      return res.status(401).json({ error: "Invalid signature" });
    }

    const event = req.body;
    console.info(`[Paystack Webhook] Processed event: ${event.event}`);

    // Route by payment type
    try {
      if (event.event === "charge.success") {
      const data = event.data;  // Scoped to this block
      const reference = data.reference;
      const amountKobo = data.amount;
      const plan = data.metadata?.plan; // set when purchasing a plan

      // Robust UID extraction (handles DVA bank transfers where metadata is on the customer)
      let uid = data.metadata?.uid || data.customer?.metadata?.uid;

      if (!uid && data.customer?.customer_code) {
        try {
          const userQuery = await db.collection("users")
            .where("paystack_customer_id", "==", data.customer.customer_code)
            .limit(1).get();
          if (!userQuery.empty) {
            uid = userQuery.docs[0].id;
          }
        } catch (err) {
          logger.error("[Paystack Webhook] Failed to look up user by customer_code:", err);
        }
      }

      // Fallback: look up by email (handles DVA transfers where customer_code is also missing)
      if (!uid && data.customer?.email) {
        try {
          const emailQuery = await db.collection("users")
            .where("email", "==", data.customer.email)
            .limit(1).get();
          if (!emailQuery.empty) {
            uid = emailQuery.docs[0].id;
            logger.info(`[Paystack Webhook] UID resolved via email fallback for ref: ${reference}`);
          }
        } catch (err) {
          logger.error("[Paystack Webhook] Failed to look up user by email:", err);
        }
      }

      if (!uid) {
        console.warn(`[Paystack Webhook] Missing metadata.uid for ref: ${reference}`);
        return res.status(200).json({ status: "ignored_missing_uid" });
      }

      if (plan && ["free", "activation", "premium", "business"].includes(plan)) {
        // ── Plan purchase webhook failsafe ─────────────────────────────────────
        const planConfig = {
          free:       { price: 700,  cards: 1 },
          activation: { price: 1400, cards: 2 },
          premium:    { price: 1999, cards: 3 }, // FIX: was 2000, correct price is 1999
          business:   { price: 5000, cards: 5 },
        };

        const isTrial = plan === "free" || plan === "activation";
        const nowMs   = Date.now();

        // FIX: Webhook failsafe was missing subscription_expiry_date and sentinel_trial_expiry_date.
        // Without subscription_expiry_date, expirationCron downgrades the user within 24h.
        // Without sentinel_trial_expiry_date, trial users get no Sentinel access via this path.
        const planUpdates = {
          planTier: plan,
          cardsIncluded: planConfig[plan].cards,
          subscription_expiry_date: nowMs + (30 * 24 * 60 * 60 * 1000),
        };
        if (isTrial) {
          planUpdates.sentinel_trial_expiry_date = nowMs + (5 * 24 * 60 * 60 * 1000);
        }

        const userRef        = db.collection("users").doc(uid);
        const idempotencyRef = db.collection("users").doc(uid).collection("plan_purchases").doc(reference);
        const ledgerRef      = db.collection("users").doc(uid).collection("wallet_transactions").doc(`plan_${plan}_${reference}`);

        try {
          await db.runTransaction(async (t) => {
            const existing = await t.get(idempotencyRef);
            if (existing.exists) throw new Error("ALREADY_PROCESSED");

            t.set(idempotencyRef, {
              reference, plan,
              amountKobo,
              status: "success",
              timestamp: nowMs,
              source: "webhook",
            });

            t.set(ledgerRef, {
              type: "debit",
              amount: amountKobo / 100,
              status: "successful",
              context: "plan_purchase",
              method: "paystack_webhook",
              metadata: plan,
              reference,
              created_at: nowMs,
            });

            t.set(userRef, planUpdates, { merge: true });
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
        // ── Standard wallet top-up via orchestrator ─────────────────────────────
        const verifiedAmount = amountKobo / 100;

        try {
          await processTransactionInternal({
            type: "wallet_funding",
            userId: uid,
            amount: verifiedAmount,
            idempotencyKey: `${uid}:wallet_funding:${reference}`,
            metadata: { paystackRef: reference, source: "paystack_webhook" },
            correlationId: `paystackWebhook:${uid}:${reference}`,
          });
          logger.info(`[Paystack Webhook] Credited ${verifiedAmount} to UID ${uid}`);
        } catch (e) {
          if (!e.message?.includes("idempotent")) {
            logger.error(`[Paystack Webhook] Transaction failed for ${reference}:`, e);
            return res.status(500).json({ error: "Internal processing error" });
          }
          // Already processed — idempotent, succeed silently
        }
      } // end else (Standard wallet top-up)
      } // end charge.success
      // BUG FIX: `charge.refunded` does NOT exist in Paystack's event catalog.
      // The correct event for refunds is `refund.processed`.
      else if (event.event === "refund.processed") {
        // Re-declare `data` in this scope — it is NOT accessible from the charge.success block above.
        const refundData = event.data;
        const reference = refundData.transaction?.reference || refundData.transaction_reference;
        const amountKobo = refundData.amount;

        let uid = refundData.customer?.metadata?.uid;

        if (!uid && refundData.customer?.customer_code) {
          try {
            const userQuery = await db.collection("users")
              .where("paystack_customer_id", "==", refundData.customer.customer_code)
              .limit(1).get();
            if (!userQuery.empty) uid = userQuery.docs[0].id;
          } catch (err) {
            logger.error("[Paystack Webhook] Failed to look up user by customer_code for refund:", err);
          }
        }

        // Fallback: email lookup for refunds
        if (!uid && refundData.customer?.email) {
          try {
            const emailQuery = await db.collection("users")
              .where("email", "==", refundData.customer.email)
              .limit(1).get();
            if (!emailQuery.empty) uid = emailQuery.docs[0].id;
          } catch (err) {
            logger.error("[Paystack Webhook] Failed to look up user by email for refund:", err);
          }
        }

        if (!uid) {
          console.warn(`[Paystack Webhook] Missing uid for refund ref: ${reference}`);
          return res.status(200).json({ status: "ignored_missing_uid" });
        }

        const plan = refundData.metadata?.plan;
        
        // Only process wallet refunds if it wasn't a plan purchase
        if (!plan) {
          const refundedAmount = amountKobo / 100;
          
          const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
          const idempotencyRef = db.collection("users").doc(uid).collection("funding_history").doc(`refund_${reference}`);

          try {
            await db.runTransaction(async (t) => {
              const existingTx = await t.get(idempotencyRef);
              if (existingTx.exists) throw new Error("ALREADY_PROCESSED");

              t.set(idempotencyRef, {
                reference: `refund_${reference}`,
                original_reference: reference,
                amount: refundedAmount,
                method: "paystack_webhook_refund",
                status: "success",
                timestamp: Date.now(),
              });

              // BUG FIX: Must write all 3 balance fields atomically.
              // Only writing `balance` left `balance_kobo` and `cached_balance` out of sync,
              // causing the user's displayed wallet balance to be wrong after a refund.
              const refundKobo = Math.round(refundedAmount * 100);
              t.set(walletRef, {
                balance_kobo: FieldValue.increment(-refundKobo),
                cached_balance: FieldValue.increment(-refundedAmount),
                balance: FieldValue.increment(-refundedAmount),
              }, { merge: true });

              const ledgerRef = db.collection("users").doc(uid).collection("wallet_transactions").doc(`refund_${reference}`);
              t.set(ledgerRef, {
                id: `refund_${reference}`,
                type: "debit",
                amount: refundedAmount,
                method: "paystack_refund",
                status: "completed",
                timestamp: Date.now()
              });
              
              logger.info(`[Paystack Webhook] Successfully processed refund of ${refundedAmount} for UID ${uid}`);
            });
          } catch (e) {
            if (e.message !== "ALREADY_PROCESSED") {
              logger.error(`[Paystack Webhook] Refund transaction failed for ${reference}:`, e);
              return res.status(500).json({ error: "Internal processing error" });
            }
          }
        }
      }

      // ── DVA assignment events ──────────────────────────────────────────────────
      // Paystack fires these when a bank transfer to a Dedicated Virtual Account is
      // processed. `charge.success` is also fired and handles the wallet credit,
      // so we only need to handle the failure case here for audit logging.
      else if (event.event === "dedicatedaccount.assign.failed") {
        const assignData = event.data;
        logger.error(`[Paystack DVA] Assignment failed for customer: ${assignData?.customer?.customer_code}`, assignData);
        // Best-effort audit log only — no wallet mutation needed
        await db.collection("dva_assignment_failures").add({
          customer_code: assignData?.customer?.customer_code,
          account_number: assignData?.dedicated_account?.account_number,
          reason: assignData?.reason || "Unknown",
          raw: JSON.stringify(assignData),
          created_at: FieldValue.serverTimestamp(),
        }).catch(e => logger.error("[Paystack DVA] Failed to log assignment failure:", e));
      }

      return res.status(200).json({ received: true });
    } catch (criticalErr) {
      logger.error(`[Paystack Webhook] Critical Unhandled Error:`, criticalErr);
      return res.status(500).json({ error: "Unhandled webhook crash" });
    }
  }
);
