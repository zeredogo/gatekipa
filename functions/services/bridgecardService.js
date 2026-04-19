/**
 * bridgecardService.js
 * 
 * Full integration layer for the Bridgecard Issuing API (LIVE PRODUCTION).
 * Handles:
 *   1. registerCardholder  — registers a user as a Bridgecard cardholder via BVN KYC
 *   2. createBridgecard    — issues a real NGN virtual Mastercard
 *   3. fundBridgecard      — tops up a Bridgecard from the NGN issuing wallet
 *   4. freezeBridgecard    — freezes / unfreezes a card
 *   5. bridgecardWebhook   — HMAC-verified POST webhook for transaction events
 * 
 * Auth header: "token: Bearer {BRIDGECARD_ACCESS_TOKEN}"
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineString, defineSecret } = require("firebase-functions/params");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail, requireAdmin, requireFields, requireKyc } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const axios = require("axios");
const AES256 = require("aes-everywhere");
const crypto = require("crypto");
const logger = require("firebase-functions/logger");
const { evaluateTransaction } = require("../engines/ruleEngine");


// ── Runtime config pulled from .env / Firebase secret params ─────────────────
const BRIDGECARD_ACCESS_TOKEN  = defineSecret("BRIDGECARD_ACCESS_TOKEN");
const BRIDGECARD_SECRET_KEY    = defineSecret("BRIDGECARD_SECRET_KEY");
const BRIDGECARD_WEBHOOK_SECRET = defineSecret("BRIDGECARD_WEBHOOK_SECRET");
const BASE_URL        = process.env.BRIDGECARD_BASE_URL
                        || "https://issuecards.api.bridgecard.co/v1/issuing/live";
const ISSUING_APP_ID  = process.env.BRIDGECARD_ISSUING_APP_ID || "8ea9a4b4-26b1-4aa6-8e29-25648057ab7d";

/** Shared axios instance with auth header */
function bridgecardClient() {
  return axios.create({
    baseURL: BASE_URL,
    headers: {
      "accept": "application/json",
      "Content-Type": "application/json",
      "token": `Bearer ${BRIDGECARD_ACCESS_TOKEN.value()}`,
      "issuing-app-id": ISSUING_APP_ID,
    },
    timeout: 60_000, // cardholder KYC can take ~45s
  });
}

/** AES-256 encrypt a 4-digit PIN using the Bridgecard secret key */
function encryptPin(pin) {
  return AES256.encrypt(String(pin), BRIDGECARD_SECRET_KEY.value());
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. registerCardholder
// Called from Flutter after KYC is complete. Registers the user with Bridgecard
// using BVN verification (synchronous endpoint).
// Stores the returned cardholder_id on the Firestore user doc.
// ─────────────────────────────────────────────────────────────────────────────
exports.registerCardholder = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["address", "city", "state", "postal_code", "house_no"]);

  // --- Check if already registered ---
  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() || {};
  const existing = userData.bridgecard_cardholder_id;
  if (existing) {
    return { success: true, cardholder_id: existing, already_registered: true };
  }

  const bvn = userData.bvn;

  // --- KYC Global Override ---
  // If identity params exist, override default BVN
  let identityObject = null;
  if (data.id_type) {
    const formattedIdType = data.id_type.trim().toUpperCase().replace(/\s+/g, "_");
    identityObject = {
      id_type: formattedIdType,
      id_no: data.id_no ? data.id_no.trim() : bvn?.trim(),
      id_image: data.id_image || userData.kycMeta?.photo || "https://via.placeholder.com/150",
      selfie_image: data.selfie_image || userData.bvnMeta?.photo || "https://via.placeholder.com/150",
    };
  } else if (bvn) {
    identityObject = {
      id_type: "NIGERIAN_BVN_VERIFICATION",
      bvn: bvn.trim(),
      selfie_image: userData.bvnMeta?.photo || data.selfie_image || "https://via.placeholder.com/150",
    };
  } else {
    throw new HttpsError("failed-precondition", "You must complete identity verification or provide advanced identity documents to register as a Cardholder.");
  }

  // Use data from request, fallback to user profile data if omitted
  const first_name = data.first_name || userData.firstName || "";
  const last_name = data.last_name || userData.lastName || "";
  const phone = data.phone || userData.phoneNumber || "";
  const email = data.email || userData.email;

  const { address, city, state, postal_code, house_no } = data;

  const payload = {
    first_name: first_name.trim(),
    last_name: last_name.trim(),
    phone: phone.trim(),                          // E.164, e.g. +2348012345678
    email_address: email ? email.trim() : `${uid}@gatekeeper.ng`,
    address: {
      address: address.trim(),
      city: city.trim(),
      state: state.trim(),
      country: data.country ? data.country.trim() : "Nigeria",
      postal_code: postal_code.trim(),
      house_no: house_no.trim(),
    },
    identity: identityObject,
    meta_data: { uid, app: "gatekeeper" },
  };

  try {
    const client = bridgecardClient();
    const res = await client.post("/cardholder/register_cardholder_synchronously", payload);
    const cardholder_id = res.data?.data?.cardholder_id;

    if (!cardholder_id) {
      throw new HttpsError("internal", res.data?.message || "Bridgecard: no cardholder_id returned.");
    }

    // Persist on Firestore user doc
    await db.collection("users").doc(uid).set(
      { bridgecard_cardholder_id: cardholder_id, bridgecard_status: "registered" },
      { merge: true }
    );

    return { success: true, cardholder_id };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] registerCardholder error:", msg);
    throw new HttpsError("failed-precondition", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. createBridgecard
// Issues a real NGN Mastercard virtual card for a registered cardholder.
// Stores the returned bridgecard card_id on the Firestore card doc.
// ─────────────────────────────────────────────────────────────────────────────
exports.createBridgecard = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN, BRIDGECARD_SECRET_KEY] }, async (request) => {

  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "pin"]);  // card_id = our Firestore card doc ID

  // IAM Enforcement
  await requireKyc(uid);

  const { card_id, pin } = data;

  // --- Verify the caller owns the card ---
  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  // --- Get the user's Bridgecard cardholder ID ---
  const userSnap = await db.collection("users").doc(uid).get();
  const cardholder_id = userSnap.data()?.bridgecard_cardholder_id;
  if (!cardholder_id) {
    throw new HttpsError("failed-precondition",
      "You must complete cardholder registration before issuing a card.");
  }

  // --- Already has a real card? ---
  const existing_bc_id = cardSnap.data()?.bridgecard_card_id;
  if (existing_bc_id) {
    return { success: true, bridgecard_card_id: existing_bc_id, already_issued: true };
  }

  const encryptedPin = encryptPin(pin);

  const cardCurrency = data.card_currency === "USD" ? "USD" : "NGN";
  const client = bridgecardClient();
  let feeToDeductNGN = 0;
  let deductCardsIncluded = false;

  const userData = userSnap.data();
  const cardsIncluded = userData?.cardsIncluded || 0;

  if (cardCurrency === "USD") {
    // 1. Fetch live bridgecard FX rate
    try {
      // Best-effort mapping on Bridgecard typical FX structure
      const fxRes = await client.get("/issuing/cards/fx");
      const rateStr = fxRes.data?.data?.rate_to_naira || fxRes.data?.data?.rate || 1600; 
      const rate = Number(rateStr);
      feeToDeductNGN = Math.ceil(3.5 * rate); 
    } catch(e) {
      console.warn("Bridgecard FX check failed, falling back to baseline 1600.", e.message);
      feeToDeductNGN = Math.ceil(3.5 * 1600);
    }
  } else {
    // NGN Card Logic: Subsidize via plan
    if (cardsIncluded > 0) {
      feeToDeductNGN = 0;
      deductCardsIncluded = true;
    } else {
      feeToDeductNGN = 700;
      // Also verify if their plan allows exceeding limits based on maxCards allowed
      const planTier = userData?.planTier || "none";
      if (planTier === "none" || planTier === "free") {
         throw new HttpsError("failed-precondition", "Free tier members cannot purchase additional cards. Please upgrade your plan.");
      }
    }
  }

  let didDeduct = false;
  const transaction_reference = `gk_card_fee_${card_id}_${Date.now()}`;
  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
  const ledgerRef = db.collection("users").doc(uid).collection("wallet_transactions").doc(transaction_reference);

  if (feeToDeductNGN > 0) {
    await db.runTransaction(async (t) => {
      const doc = await t.get(walletRef);
      if (!doc.exists) throw new HttpsError("failed-precondition", "Wallet not initialized.");
      if ((doc.data().balance || 0) < feeToDeductNGN) {
        throw new HttpsError("failed-precondition", `Insufficient funds. Needed: ~${feeToDeductNGN} NGN.`);
      }
      
      t.set(walletRef, { balance: FieldValue.increment(-feeToDeductNGN) }, { merge: true });
      t.set(ledgerRef, {
        type: "debit",
        amount: feeToDeductNGN,
        status: "successful",
        context: cardCurrency === "USD" ? "usd_card_creation" : "ngn_card_creation",
        card_id,
        created_at: Date.now()
      });
    });
    didDeduct = true;
  }

  const payload = {
    cardholder_id,
    card_type: "virtual",
    card_brand: "Mastercard",
    card_currency: cardCurrency,
    pin: encryptedPin,
    ...(cardCurrency === "USD" && { prefund_amount: 3 }),
    meta_data: { card_id, uid, app: "gatekeeper" },
  };

  try {
    const client = bridgecardClient();
    const res = await client.post("/cards/create_card", payload);
    const bridgecard_card_id = res.data?.data?.card_id;

    if (!bridgecard_card_id) {
      throw new HttpsError("internal", res.data?.message || "Bridgecard: no card_id returned.");
    }

    // Persist on Firestore card doc
    await db.collection("cards").doc(card_id).set(
      {
        bridgecard_card_id,
        bridgecard_currency: cardCurrency,
        bridgecard_status: "active",
      },
      { merge: true }
    );

    if (deductCardsIncluded) {
      await db.collection("users").doc(uid).update({
        cardsIncluded: FieldValue.increment(-1)
      });
    }

    return { success: true, bridgecard_card_id, currency: cardCurrency, deducted: feeToDeductNGN };
  } catch (err) {
    if (didDeduct) {
      console.warn(`[Bridgecard] createBridgecard failed. Rolling back ${feeToDeductNGN} NGN for ${uid}`);
      try {
        await db.runTransaction(async (rollbackT) => {
          rollbackT.set(walletRef, { balance: FieldValue.increment(feeToDeductNGN) }, { merge: true });
          rollbackT.set(ledgerRef, { status: "reversed", metadata: "Bridgecard API failure", reversed_at: Date.now() }, { merge: true });
        });
      } catch (rollbackErr) {
        console.error(`[CRITICAL] FAILED TO ROLLBACK FAILED CARD FEE FOR UID ${uid}`, rollbackErr);
      }
    }
    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] createBridgecard error:", msg);
    throw new HttpsError("failed-precondition", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. fundBridgecard
// Tops up a Bridgecard NGN card from the NGN issuing wallet.
// amount should be in Naira (we convert to kobo internally).
// ─────────────────────────────────────────────────────────────────────────────
exports.fundBridgecard = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "amount"]);
  const { card_id, amount } = data;

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be a strictly positive finite number.");
  }

  // IAM Enforcement
  await requireKyc(uid);

  // Verify ownership
  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition",
      "This card has not been issued via Bridgecard yet.");
  }

  const transaction_reference = `gk_${card_id}_${Date.now()}`;
  const amountKobo = String(Math.round(amount * 100)); // Bridgecard expects kobo

  // 1. Deduct from Gatekeeper Wallet first (Atomic Lock)
  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
  
  try {
    await db.runTransaction(async (t) => {
      const doc = await t.get(walletRef);
      const currentBalance = doc.exists ? (doc.data().balance || 0) : 0;
      
      if (currentBalance < amount) {
        throw new HttpsError("failed-precondition", "Insufficient funds in your Gatekeeper Vault.");
      }
      
      // Deduct funds locked in for card topup
      t.set(walletRef, { balance: FieldValue.increment(-amount) }, { merge: true });
      
      // Log the pending funding securely
      const reqRef = db.collection("card_funding_requests").doc(transaction_reference);
      t.set(reqRef, {
        uid,
        card_id,
        bridgecard_card_id,
        amount_ngn: amount,
        amount_kobo: amountKobo,
        transaction_reference,
        status: "processing",
        created_at: Date.now(),
      });
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Failed to lock funds for transfer.");
  }

  const payload = {
    card_id: bridgecard_card_id,
    amount: amountKobo,
    transaction_reference,
  };

  try {
    const client = bridgecardClient();
    const res = await client.post("/naira_cards/fund_naira_card", payload);

    return {
      success: true,
      message: "Funding is processing.",
      transaction_reference,
      bridgecard_response: res.data,
    };
  } catch (err) {
    logger.error("[Bridgecard] fundBridgecard error, triggering atomic rollback:", err);

    // 2. Critical Fallback: ROBUST Rollback wallet deduction if Bridgecard fails
    try {
      await db.runTransaction(async (rollbackT) => {
        rollbackT.set(walletRef, { balance: FieldValue.increment(amount) }, { merge: true });
        rollbackT.set(
          db.collection("card_funding_requests").doc(transaction_reference),
          { status: "failed", error: err.message },
          { merge: true }
        );
      });
      logger.info(`[Bridgecard] Successfully rolled back ${amount} to Vault for ref ${transaction_reference}`);
    } catch (rollbackErr) {
      logger.error(`[Bridgecard] CRITICAL - Rollback failed for ${transaction_reference}:`, rollbackErr);
    }

    const msg = err.response?.data?.message || err.message;
    throw new HttpsError("failed-precondition", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. freezeBridgecard / unfreezeBridgecard
// Freeze or unfreeze a Bridgecard NGN card.
// Not an HTTP endpoint. Requires passing secret in scope!
async function internalFreezeBridgecard(bridgecardCardId, freeze = true) {
  const client = bridgecardClient(); // Assumes caller scope injected BRIDGECARD_ACCESS_TOKEN secret
  const endpoint = freeze ? "/naira_cards/freeze_card" : "/naira_cards/unfreeze_card";
  await client.patch(endpoint, { card_id: bridgecardCardId });
}
exports.internalFreezeBridgecard = internalFreezeBridgecard;

exports.freezeBridgecard = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "freeze"]);
  const { card_id, freeze } = data;

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition", "Not a Bridgecard-issued card.");
  }

  const endpoint = freeze
    ? "/naira_cards/freeze_card"
    : "/naira_cards/unfreeze_card";

  try {
    const client = bridgecardClient();
    await client.patch(endpoint, { card_id: bridgecard_card_id });

    await db.collection("cards").doc(card_id).update({
      status: freeze ? "frozen" : "active",
      bridgecard_status: freeze ? "frozen" : "active",
    });

    return { success: true, frozen: freeze };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] freezeBridgecard error:", msg);
    throw new HttpsError("failed-precondition", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. adminFreezeCard
// Privileged endpoint used exclusively by the Next.js Admin Control Center.
// Bypasses isOwner checks and forcefully alters card state globally.
// ─────────────────────────────────────────────────────────────────────────────
exports.adminFreezeCard = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireAdmin(request.auth);
  
  const { card_id, freeze } = request.data;
  requireFields(request.data, ["card_id", "freeze"]);

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition", "Not a Bridgecard-issued card.");
  }

  try {
    await internalFreezeBridgecard(bridgecard_card_id, freeze);
    
    await cardSnap.ref.update({
      bridgecard_status: freeze ? "frozen" : "active",
      status: freeze ? "blocked" : "active",
      updatedAt: FieldValue.serverTimestamp()
    });

    return { success: true, message: `Admin successfully ${freeze ? 'froze' : 'unfroze'} the card.` };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    throw new HttpsError("aborted", `Failed Bridgecard Request: ${msg}`);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. bridgecardWebhook
// HMAC-SHA512 verified webhook for Bridgecard events.
// Receives real transaction authorisation events and settlement notifications.
// Endpoint: POST /bridgecardWebhook  (register this URL on the Bridgecard dashboard)
// ─────────────────────────────────────────────────────────────────────────────
exports.bridgecardWebhook = onRequest({ region: "us-central1", secrets: [BRIDGECARD_WEBHOOK_SECRET] }, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // --- Verify HMAC signature ---
  const signature = req.headers["x-bridgecard-signature"] || "";
  const hash = crypto
    .createHmac("sha512", BRIDGECARD_WEBHOOK_SECRET.value())
    .update(JSON.stringify(req.body))
    .digest("hex");

  if (signature !== hash) {
    console.warn("[Bridgecard Webhook] Invalid signature — rejecting.");
    return res.status(401).json({ error: "Invalid signature" });
  }

  const event = req.body;
  const eventType = event?.event;
  const eventData = event?.data;

  console.info(`[Bridgecard Webhook] Received event: ${eventType}`);

  try {
    switch (eventType) {
      // ── Real-time transaction authorisation ─────────────────────────────
      case "transaction.authorisation": {
        const bridgecard_card_id = eventData?.card_id;
        const amount_kobo = Number(eventData?.amount || 0);
        const amount_ngn = amount_kobo / 100;
        const merchant = eventData?.merchant_name || "Unknown";
        let approved = eventData?.status === "approved";
        let declineReason = eventData?.decline_reason || "Unknown";
        const authEventId = event?.id || `txn_${Date.now()}`;

        // Find the Firestore card doc by bridgecard_card_id
        const cardsSnap = await db.collection("cards")
          .where("bridgecard_card_id", "==", bridgecard_card_id)
          .limit(1)
          .get();

        if (!cardsSnap.empty) {
          const cardDoc = cardsSnap.docs[0];
          const card = cardDoc.data();

          // RULE ENGINE VALIDATION
          // Only evaluate if Bridgecard initially approved it
          if (approved) {
            const ruleEvaluation = await evaluateTransaction(cardDoc.id, amount_ngn, merchant);
            if (!ruleEvaluation.approved) {
              approved = false;
              declineReason = ruleEvaluation.reason;
              logger.warn(`[RuleEngine] BLOCKED authorized transaction. Reason: ${declineReason}`);
              
              // Force disable the card since Bridgecard thinks it's approved and we want it blocked
              await internalFreezeBridgecard(bridgecard_card_id, true).catch(e => logger.error("Freeze failed", e));
              await cardDoc.ref.update({ status: "blocked", bridgecard_status: "frozen" });
            }
          }

          const accountSnap = await db.collection("accounts").doc(card.account_id).get();
          const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : null;

          if (!ownerUid) {
             logger.error(`[Webhook Flow] Owner UID not found for card ${cardDoc.id}. Skipping.`);
             break;
          }

          const idempotencyRef = db.collection("webhook_events").doc(authEventId);

          try {
            await db.runTransaction(async (t) => {
              const existingEvent = await t.get(idempotencyRef);
              if (existingEvent.exists) {
                throw new Error("ALREADY_PROCESSED");
              }

              t.set(idempotencyRef, {
                processed_at: Date.now(),
                event: eventType,
              });

              // Write the transaction
              const newTxnRef = db.collection("transactions").doc();
              t.set(newTxnRef, {
                id: newTxnRef.id,
                card_id: cardDoc.id,
                account_id: card.account_id,
                merchant_name: merchant,
                amount: amount_ngn,
                status: approved ? "approved" : "declined",
                decline_reason: approved ? null : declineReason,
                source: "bridgecard",
                bridgecard_event: eventType,
                raw: eventData,
                timestamp: FieldValue.serverTimestamp(),
              });

              // Update card spent amount if approved
              if (approved) {
                t.set(cardDoc.ref, {
                  spent_amount: FieldValue.increment(amount_ngn),
                  charge_count: FieldValue.increment(1)
                }, { merge: true });

                const walletRef = db.collection("users").doc(ownerUid).collection("wallet").doc("balance");
                t.set(walletRef, { balance: FieldValue.increment(-100) }, { merge: true });

                const feeLedgerRef = db.collection("users").doc(ownerUid).collection("wallet_transactions").doc(`${authEventId}_fee`);
                t.set(feeLedgerRef, {
                  type: "debit",
                  amount: 100,
                  status: "successful",
                  context: "platform_transaction_fee",
                  card_id: cardDoc.id,
                  created_at: Date.now()
                });
              }
            });
          } catch (e) {
            if (e.message !== "ALREADY_PROCESSED") {
              throw e; // Rethrow real DB errors
            }
            // If already processed, we skip notification safely
            break; 
          }

          // Notify the account owner (outside transaction)
          if (ownerUid) {
            await db.collection("users").doc(ownerUid)
              .collection("notifications").add({
                title: approved
                  ? `₦${amount_ngn.toLocaleString()} approved at ${merchant}`
                  : `Transaction blocked at ${merchant}`,
                body: approved
                  ? `Your card ending in ${card.last4} was charged ₦${amount_ngn.toLocaleString()}.`
                  : `Reason: ${declineReason}`,
                timestamp: new Date(),
                isRead: false,
                type: approved ? "transaction" : "alert",
              });
              
            // Dispatch Firebase Cloud Messaging (FCM) physical push notification
            try {
              const uDoc = await db.collection("users").doc(ownerUid).get();
              const fcmToken = uDoc.data()?.fcm_token;
              
              let shouldSendPush = true;
              if (!approved) {
                const ruleSnap = await db.collection("rules")
                  .where("card_id", "==", cardDoc.id)
                  .where("sub_type", "==", "instant_breach_alert")
                  .limit(1)
                  .get();
                if (ruleSnap.empty) {
                  shouldSendPush = false;
                }
              }
              
              if (fcmToken && shouldSendPush) {
                await getMessaging().send({
                  token: fcmToken,
                  notification: {
                    title: approved ? `₦${amount_ngn.toLocaleString()} Approved` : `Charge Blocked!`,
                    body: approved
                      ? `Your card ending in ${card.last4} was charged at ${merchant}.`
                      : `We blocked a charge at ${merchant}. Reason: ${declineReason}`
                  },
                  data: {
                    type: approved ? "transaction_approved" : "transaction_blocked",
                    amount: String(amount_ngn),
                    merchant: merchant
                  }
                });
                logger.info(`[FCM] Push Notification dispatched to ${ownerUid} for ${approved ? 'approval' : 'block'}`);
              } else if (!approved) {
                 logger.info(`[FCM] Push notification suppressed for blocked charge on ${cardDoc.id} (no breach rule)`);
              }
            } catch (fcmErr) {
              logger.error(`[FCM] Failed to dispatch push notification to ${ownerUid}:`, fcmErr);
            }
          }
        }
        break;
      }

      // ── Card funding confirmed ───────────────────────────────────────────
      case "naira_card_credit_event.successful": {
        const txRef = eventData?.transaction_reference;
        if (txRef) {
          await db.collection("card_funding_requests")
            .where("transaction_reference", "==", txRef)
            .limit(1)
            .get()
            .then(snap => {
              if (!snap.empty) snap.docs[0].ref.update({ status: "completed" });
            });
        }
        break;
      }

      case "naira_card_credit_event.failed": {
        const txRef = eventData?.transaction_reference;
        if (txRef) {
          await db.collection("card_funding_requests")
            .where("transaction_reference", "==", txRef)
            .limit(1)
            .get()
            .then(snap => {
              if (!snap.empty) snap.docs[0].ref.update({ status: "failed" });
            });
        }
        break;
      }

      // ── Cardholder KYC verified (async registration flow) ───────────────
      case "cardholder_verification.successful": {
        const cardholder_id = eventData?.cardholder_id;
        const meta_uid = eventData?.meta_data?.uid;
        if (meta_uid) {
          await db.collection("users").doc(meta_uid).set(
            { bridgecard_status: "verified", bridgecard_cardholder_id: cardholder_id },
            { merge: true }
          );
        }
        break;
      }

      case "cardholder_verification.failed": {
        const meta_uid = eventData?.meta_data?.uid;
        if (meta_uid) {
          await db.collection("users").doc(meta_uid).set(
            { bridgecard_status: "failed" },
            { merge: true }
          );
        }
        break;
      }

      default:
        console.info(`[Bridgecard Webhook] Unhandled event type: ${eventType}`);
    }

    return res.status(200).json({ received: true });
  } catch (err) {
    console.error("[Bridgecard Webhook] Processing error:", err);
    return res.status(500).json({ error: "Internal processing error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 6. revealCardDetails
// Securely proxies Bridgecard's PCI-DSS endpoint to map raw card bytes locally.
// Never persists results natively!
// ─────────────────────────────────────────────────────────────────────────────
exports.revealCardDetails = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  requireFields(data, ["card_id"]);
  const { card_id } = data;

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");
  
  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition", "This card has not been issued via Bridgecard yet.");
  }

  try {
    const client = bridgecardClient();
    const res = await client.get(`/cards/get_card_details?card_id=${bridgecard_card_id}`);
    const cardData = res.data?.data;
    
    if (!cardData) {
      throw new HttpsError("internal", "Bridgecard did not return card data.");
    }
    
    return {
      success: true,
      card_number: cardData.card_number,
      cvv: cardData.cvv,
      expiry_month: cardData.expiry_month,
      expiry_year: cardData.expiry_year,
      last_4: cardData.last_4,
    };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] revealCardDetails error:", msg);
    throw new HttpsError("internal", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 7. getCardOtp
// Fetches the live 3D Secure OTP tied to the explicit Naira transaction amount.
// ─────────────────────────────────────────────────────────────────────────────
exports.getCardOtp = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  requireFields(data, ["card_id", "amount_ngn"]);
  const { card_id, amount_ngn } = data;

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");
  
  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition", "This card has not been issued via Bridgecard yet.");
  }

  try {
    const client = bridgecardClient();
    const amountKobo = String(Math.round(amount_ngn * 100));
    const res = await client.get(`/naira_cards/get_otp_message?card_id=${bridgecard_card_id}&amount=${amountKobo}`);
    
    return {
      success: true,
      otp: res.data?.data?.otp,
      message: res.data?.message,
    };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] getCardOtp error:", msg);
    throw new HttpsError("failed-precondition", msg);
  }
});
