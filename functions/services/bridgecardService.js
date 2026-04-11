/**
 * bridgecardService.js
 * 
 * Full integration layer for the Bridgecard Issuing API (sandbox).
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
const { defineString } = require("firebase-functions/params");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const axios = require("axios");
const AES256 = require("aes-everywhere");
const crypto = require("crypto");

// ── Runtime config pulled from .env / Firebase secret params ─────────────────
const ACCESS_TOKEN  = process.env.BRIDGECARD_ACCESS_TOKEN;
const SECRET_KEY    = process.env.BRIDGECARD_SECRET_KEY;
const WEBHOOK_SECRET = process.env.BRIDGECARD_WEBHOOK_SECRET;
const BASE_URL      = process.env.BRIDGECARD_BASE_URL
                        || "https://issuecards.api.bridgecard.co/v1/issuing/sandbox";

/** Shared axios instance with auth header */
function bridgecardClient() {
  return axios.create({
    baseURL: BASE_URL,
    headers: {
      "accept": "application/json",
      "Content-Type": "application/json",
      "token": `Bearer ${ACCESS_TOKEN}`,
    },
    timeout: 60_000, // cardholder KYC can take ~45s
  });
}

/** AES-256 encrypt a 4-digit PIN using the Bridgecard secret key */
function encryptPin(pin) {
  return AES256.encrypt(String(pin), SECRET_KEY);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. registerCardholder
// Called from Flutter after KYC is complete. Registers the user with Bridgecard
// using BVN verification (synchronous endpoint).
// Stores the returned cardholder_id on the Firestore user doc.
// ─────────────────────────────────────────────────────────────────────────────
exports.registerCardholder = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["first_name", "last_name", "phone", "bvn", "address"]);

  // --- Check if already registered ---
  const userDoc = await db.collection("users").doc(uid).get();
  const existing = userDoc.data()?.bridgecard_cardholder_id;
  if (existing) {
    return { success: true, cardholder_id: existing, already_registered: true };
  }

  const { first_name, last_name, phone, email, bvn, address } = data;
  // address must include: address, city, state, country, postal_code, house_no

  const payload = {
    first_name: first_name.trim(),
    last_name: last_name.trim(),
    phone: phone.trim(),                          // E.164, e.g. +2348012345678
    email_address: email ? email.trim() : `${uid}@gatekeeper.ng`,
    address: {
      address: address.address,
      city: address.city || "Lagos",
      state: address.state || "Lagos",
      country: "Nigeria",
      postal_code: address.postal_code || "100001",
      house_no: address.house_no || "1",
    },
    identity: {
      id_type: "NIGERIAN_BVN_VERIFICATION",
      bvn: bvn.trim(),
      selfie_image: data.selfie_image || "https://via.placeholder.com/150",
    },
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
exports.createBridgecard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "pin"]);  // card_id = our Firestore card doc ID

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

  const payload = {
    cardholder_id,
    card_type: "virtual",
    card_brand: "Mastercard",
    card_currency: "NGN",
    pin: encryptedPin,
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
        bridgecard_currency: "NGN",
        bridgecard_status: "active",
      },
      { merge: true }
    );

    return { success: true, bridgecard_card_id };
  } catch (err) {
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
exports.fundBridgecard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "amount"]);
  const { card_id, amount } = data;

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be a strictly positive finite number.");
  }

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
    // 2. Critical Fallback: Rollback wallet deduction if Bridgecard fails
    await walletRef.update({ balance: FieldValue.increment(amount) }).catch(() => {});
    await db.collection("card_funding_requests").doc(transaction_reference).update({
      status: "failed", error: err.message
    }).catch(() => {});

    const msg = err.response?.data?.message || err.message;
    console.error("[Bridgecard] fundBridgecard error:", msg);
    throw new HttpsError("failed-precondition", msg);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. freezeBridgecard / unfreezeBridgecard
// Freeze or unfreeze a Bridgecard NGN card.
// ─────────────────────────────────────────────────────────────────────────────
async function internalFreezeBridgecard(bridgecard_card_id, freeze) {
  if (!bridgecard_card_id) return;
  const endpoint = freeze ? "/naira_cards/freeze_card" : "/naira_cards/unfreeze_card";
  const client = bridgecardClient();
  await client.patch(endpoint, { card_id: bridgecard_card_id });
}
exports.internalFreezeBridgecard = internalFreezeBridgecard;

exports.freezeBridgecard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
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
// 5. bridgecardWebhook
// HMAC-SHA512 verified webhook for Bridgecard events.
// Receives real transaction authorisation events and settlement notifications.
// Endpoint: POST /bridgecardWebhook  (register this URL on the Bridgecard dashboard)
// ─────────────────────────────────────────────────────────────────────────────
exports.bridgecardWebhook = onRequest({ region: "us-central1" }, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // --- Verify HMAC signature ---
  const signature = req.headers["x-bridgecard-signature"] || "";
  const rawBody = JSON.stringify(req.body); // body-parser must parse as JSON
  const expectedSig = crypto
    .createHmac("sha512", WEBHOOK_SECRET)
    .update(rawBody)
    .digest("hex");

  if (signature !== expectedSig) {
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
        const approved = eventData?.status === "approved";

        // Find the Firestore card doc by bridgecard_card_id
        const cardsSnap = await db.collection("cards")
          .where("bridgecard_card_id", "==", bridgecard_card_id)
          .limit(1)
          .get();

        if (!cardsSnap.empty) {
          const cardDoc = cardsSnap.docs[0];
          const card = cardDoc.data();

          // Write the transaction
          await db.collection("transactions").add({
            card_id: cardDoc.id,
            account_id: card.account_id,
            merchant_name: merchant,
            amount: amount_ngn,
            status: approved ? "approved" : "declined",
            decline_reason: approved ? null : (eventData?.decline_reason || "Unknown"),
            source: "bridgecard",
            bridgecard_event: eventType,
            raw: eventData,
            timestamp: new Date(),
          });

          // Update card spent amount if approved
          if (approved) {
            await cardDoc.ref.update({
              spent_amount: (card.spent_amount || 0) + amount_ngn,
              charge_count: (card.charge_count || 0) + 1,
            });
          }

          // Notify the account owner
          const accountSnap = await db.collection("accounts").doc(card.account_id).get();
          if (accountSnap.exists) {
            const ownerUid = accountSnap.data().owner_user_id;
            await db.collection("users").doc(ownerUid)
              .collection("notifications").add({
                title: approved
                  ? `₦${amount_ngn.toLocaleString()} approved at ${merchant}`
                  : `Transaction blocked at ${merchant}`,
                body: approved
                  ? `Your card ending in ${card.last4} was charged ₦${amount_ngn.toLocaleString()}.`
                  : `Reason: ${eventData?.decline_reason || "Policy violation"}`,
                timestamp: new Date(),
                isRead: false,
                type: approved ? "transaction" : "alert",
              });
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
