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
const { requireVerifiedEmail, requireAdmin, requireFields, requireKyc, requirePin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const axios = require("axios");
const AES256 = require("aes-everywhere");
const crypto = require("crypto");
const logger = require("firebase-functions/logger");
const { evaluateTransaction, userHasSentinelAccess } = require("../engines/ruleEngine");
const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
const { assertValidTransition } = require("../core/stateMachine");
// Loaded lazily to avoid circular require (transactionService ↔ bridgecardService)
let _processTransactionInternal;
function getOrchestrator() {
  if (!_processTransactionInternal) {
    _processTransactionInternal = require("./transactionService").processTransactionInternal;
  }
  return _processTransactionInternal;
}


// ── Runtime config pulled from .env / Firebase secret params ─────────────────
const BRIDGECARD_ACCESS_TOKEN  = defineSecret("BRIDGECARD_ACCESS_TOKEN");
const BRIDGECARD_SECRET_KEY    = defineSecret("BRIDGECARD_SECRET_KEY");
const BRIDGECARD_WEBHOOK_SECRET = defineSecret("BRIDGECARD_WEBHOOK_SECRET");
const BASE_URL        = process.env.BRIDGECARD_BASE_URL
                        || "https://issuecards.api.bridgecard.co/v1/issuing";
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

  // ── Server-side data quality validation ──────────────────────────────────
  const nameRe = /^[a-zA-Z\-' ]{2,}$/;
  if (data.first_name && !nameRe.test(data.first_name.trim())) {
    throw new HttpsError("invalid-argument", "First name must be at least 2 letters (no numbers or special characters).");
  }
  if (data.last_name && !nameRe.test(data.last_name.trim())) {
    throw new HttpsError("invalid-argument", "Last name must be at least 2 letters (no numbers or special characters).");
  }
  if (data.address.trim().length < 5) {
    throw new HttpsError("invalid-argument", "Street address must be at least 5 characters.");
  }
  if (data.city.trim().length < 2) {
    throw new HttpsError("invalid-argument", "City must be at least 2 characters.");
  }
  if (data.state.trim().length < 2) {
    throw new HttpsError("invalid-argument", "State must be at least 2 characters.");
  }
  if (!/^[0-9]{4,10}$/.test(data.postal_code.trim())) {
    throw new HttpsError("invalid-argument", "Postal code must be 4-10 digits.");
  }
  if (data.house_no.trim().length < 1) {
    throw new HttpsError("invalid-argument", "House number is required.");
  }
  if (data.phone !== undefined && data.phone !== null) {
    if (data.phone.trim() === "") {
      throw new HttpsError("invalid-argument", "Phone number cannot be empty.");
    }
    const cleanedPhone = data.phone.trim().replace(/[\s\-]/g, "");
    if (!/^\+?[0-9]{10,15}$/.test(cleanedPhone)) {
      throw new HttpsError("invalid-argument", "Phone number must be a valid format (e.g. +2348012345678).");
    }
  }

  // --- Check if already registered ---
  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() || {};
  const existing = userData.bridgecard_cardholder_id;
  if (existing) {
    return { success: true, cardholder_id: existing, already_registered: true };
  }

  const bvn = userData.bvn;

  // --- KYC Global Override ---
  // If identity params exist, override default BVN or use verified KYC
  let identityObject = null;
  if (data.id_type) {
    const formattedIdType = data.id_type.trim().toUpperCase().replace(/\s+/g, "_");
    identityObject = {
      id_type: formattedIdType,
      id_no: data.id_no ? data.id_no.trim() : (bvn?.trim() || "000000000"),
      id_image: data.id_image || userData.kycMeta?.photo || "https://via.placeholder.com/150",
      selfie_image: data.selfie_image || userData.bvnMeta?.photo || "https://via.placeholder.com/150",
    };
  } else if (bvn) {
    identityObject = {
      id_type: "NIGERIAN_BVN_VERIFICATION",
      bvn: bvn.trim(),
      selfie_image: userData.bvnMeta?.photo || data.selfie_image || "https://via.placeholder.com/150",
    };
  } else if (userData.kycStatus === "verified") {
    // If the user has completed the generalized upload flow, use their stored document or fallback
    identityObject = {
      id_type: "PASSPORT",
      id_no: userData.kycMeta?.idNumber || "A00000000",
      id_image: userData.kycMeta?.photo || "https://via.placeholder.com/150",
      selfie_image: userData.kycMeta?.selfie || "https://via.placeholder.com/150",
    };
  } else {
    throw new HttpsError("failed-precondition", "You must complete Government Issued ID verification to register as a Cardholder.");
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
    const status = err.response?.status;
    const msg = err.response?.data?.message || err.message;
    logger.error("[Bridgecard] registerCardholder error:", { status, message: msg, url: "/cardholder/register_cardholder_synchronously" });
    
    // Auto-heal: If Bridgecard rejects the ID details, revert the local KYC lock
    // so the user can re-submit their documents via the Profile screen.
    if (userData.kycStatus === "verified") {
      await db.collection("users").doc(uid).update({ kycStatus: "unverified" }).catch(() => {});
    }

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

  requireFields(data, ["card_id", "pin", "transactionPin"]);  // pin = Card ATM PIN, transactionPin = Gatekipa Security PIN

  // IAM Enforcement
  await requireKyc(uid);
  
  // SECURE TRANSACTION PIN ENFORCEMENT
  await requirePin(uid, data.transactionPin);

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

  if (cardCurrency === "USD") {
    try {
      const fxRes = await client.get("/issuing/cards/fx");
      const rateStr = fxRes.data?.data?.rate_to_naira || fxRes.data?.data?.rate || 1600; 
      const rate = Number(rateStr);
      feeToDeductNGN = Math.ceil(3.5 * rate); 
    } catch(e) {
      console.warn("Bridgecard FX check failed, falling back to baseline 1600.", e.message);
      feeToDeductNGN = Math.ceil(3.5 * 1600);
    }
  }

  const transaction_reference = `gk_card_fee_${card_id}_${Date.now()}`;
  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
  const userRef = db.collection("users").doc(uid);
  const ledgerRef = db.collection("wallet_ledger").doc(transaction_reference);

  let didDeductBalance = false;

  // ── ATOMIC FEE / QUOTA DEDUCTION ──────────────────────────────────────────
  await db.runTransaction(async (t) => {
    const userDoc = await t.get(userRef);
    const userData = userDoc.data() || {};
    
    if (cardCurrency === "NGN") {
      const cardsIncluded = userData.cardsIncluded || 0;
      if (cardsIncluded > 0) {
        feeToDeductNGN = 0;
        deductCardsIncluded = true;
        // Atomically decrement card quota
        t.update(userRef, { cardsIncluded: FieldValue.increment(-1) });
      } else {
        feeToDeductNGN = 700;
        const planTier = userData.planTier || "none";
        if (planTier === "none" || planTier === "free") {
           throw new HttpsError("failed-precondition", "Free tier members cannot purchase additional cards. Please upgrade your plan.");
        }
      }
    }

    if (feeToDeductNGN > 0) {
      const walletDoc = await t.get(walletRef);
      if (!walletDoc.exists) throw new HttpsError("failed-precondition", "Wallet not initialized.");
      if ((walletDoc.data().balance || 0) < feeToDeductNGN) {
        throw new HttpsError("failed-precondition", `Insufficient funds. Needed: ~${feeToDeductNGN} NGN.`);
      }
      
      // Atomically deduct fee
      t.set(walletRef, { balance: FieldValue.increment(-feeToDeductNGN) }, { merge: true });
      t.set(ledgerRef, {
        type: "debit",
        amount: feeToDeductNGN,
        status: "successful",
        context: cardCurrency === "USD" ? "usd_card_creation" : "ngn_card_creation",
        user_id: uid,
        card_id,
        created_at: Date.now()
      });
      didDeductBalance = true;
    }
  });

  const queueId = `cpq_${card_id}_${Date.now()}`;
  const provisioningQueueRef = db.collection("card_provisioning_queue").doc(queueId);

  // Phase 3: Pre-flight lock — written BEFORE the Bridgecard API call.
  // The ghostCardSweeper queries for items stuck in PENDING for > 5 minutes
  // and auto-heals or auto-refunds them without human intervention.
  await provisioningQueueRef.set({
    queue_id: queueId,
    uid,
    card_id,
    cardholder_id,
    card_currency: cardCurrency,
    fee_deducted_kobo: Math.round(feeToDeductNGN * 100),
    status: "PENDING",
    created_at: Date.now(),
  });

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
    const bridgecardClientAuth = bridgecardClient();
    const res = await bridgecardClientAuth.post("/cards/create_card", payload);
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

    // Phase 3: Mark DLQ queue item as COMPLETED — sweeper will ignore this
    await provisioningQueueRef.set({ status: "COMPLETED", bridgecard_card_id, completed_at: Date.now() }, { merge: true });

    return { success: true, bridgecard_card_id, currency: cardCurrency, deducted: feeToDeductNGN };
  } catch (err) {
    // ── ATOMIC ROLLBACK ON BRIDGECARD API FAILURE ─────────────────────────
    console.warn(`[Bridgecard] createBridgecard failed. Rolling back for ${uid}`);
    try {
      await db.runTransaction(async (rollbackT) => {
        if (deductCardsIncluded) {
          rollbackT.update(userRef, { cardsIncluded: FieldValue.increment(1) });
        }
        if (didDeductBalance && feeToDeductNGN > 0) {
          rollbackT.set(walletRef, { balance: FieldValue.increment(feeToDeductNGN) }, { merge: true });
          rollbackT.set(ledgerRef, { status: "reversed", metadata: "Bridgecard API failure", reversed_at: Date.now() }, { merge: true });
        }
      });
    } catch (rollbackErr) {
      console.error(`[CRITICAL] FAILED TO ROLLBACK CARD CREATION (Quota/Fee) FOR UID ${uid}`, rollbackErr);
    }
    
    // Phase 3: Mark DLQ queue item as FAILED — sweeper won't try to auto-refund
    // (explicit rollback already ran above, so no double-refund)
    await provisioningQueueRef.set({ status: "EXPLICIT_ROLLBACK", error: msg, failed_at: Date.now() }, { merge: true });

    const msg2 = err.response?.data?.message || err.message;
    console.error("[Bridgecard] createBridgecard error:", msg2);
    throw new HttpsError("failed-precondition", msg2);
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
    const isNetworkOrTimeout = !err.response || err.response.status >= 500;
    
    if (isNetworkOrTimeout) {
      logger.warn(`[Bridgecard] Network timeout/5xx for ${transaction_reference}. Skipping rollback, marking for reconciliation.`);
      await db.collection("card_funding_requests").doc(transaction_reference).update({
        status: "requires_reconciliation",
        error: "Network timeout or 5xx error."
      });
      throw new HttpsError("internal", "The issuing network timed out. Your funds are secure while we verify the transaction status.");
    }

    logger.error("[Bridgecard] fundBridgecard 4xx error, triggering atomic rollback:", err);

    // 2. Critical Fallback: ROBUST Rollback wallet deduction if Bridgecard fails synchronously (4xx)
    try {
      await db.runTransaction(async (rollbackT) => {
        rollbackT.set(walletRef, { balance: FieldValue.increment(amount) }, { merge: true });
        rollbackT.set(
          db.collection("card_funding_requests").doc(transaction_reference),
          { status: "failed", error: err.response?.data?.message || err.message },
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

  // Enforce state machine
  const currentStatus = cardSnap.data().local_status || cardSnap.data().status;
  const targetStatus = freeze ? "frozen" : "active";
  try { assertValidTransition(currentStatus, targetStatus); }
  catch (e) { throw new HttpsError("failed-precondition", e.message); }

  try {
    const client = bridgecardClient();
    await client.patch(endpoint, { card_id: bridgecard_card_id });

    await db.collection("cards").doc(card_id).update({
      local_status: targetStatus,
      status: freeze ? "frozen" : "active",
      lifecycle_version: FieldValue.increment(1),
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
exports.adminFreezeCard = onCall({ region: "us-central1", secrets: [BRIDGECARD_ACCESS_TOKEN], enforceAppCheck: false }, async (request) => {
  requireAdmin(request.auth);
  
  const { card_id, freeze } = request.data;
  requireFields(request.data, ["card_id", "freeze"]);

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const bridgecard_card_id = cardSnap.data()?.bridgecard_card_id;
  if (!bridgecard_card_id) {
    throw new HttpsError("failed-precondition", "Not a Bridgecard-issued card.");
  }

  const currentStatus = cardSnap.data().local_status || cardSnap.data().status;
  const targetStatus = freeze ? "frozen" : "active";
  try { assertValidTransition(currentStatus, targetStatus); }
  catch (e) { throw new HttpsError("failed-precondition", e.message); }

  try {
    await internalFreezeBridgecard(bridgecard_card_id, freeze);

    await cardSnap.ref.update({
      local_status: targetStatus,
      status: freeze ? "blocked" : "active",
      lifecycle_version: FieldValue.increment(1),
      bridgecard_status: freeze ? "frozen" : "active",
      updatedAt: FieldValue.serverTimestamp(),
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
exports.bridgecardWebhook = onRequest({ region: "us-central1", secrets: [BRIDGECARD_WEBHOOK_SECRET], enforceAppCheck: false }, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // --- Verify HMAC signature ---
  const signature = req.headers["x-bridgecard-signature"] || "";
  const hash = crypto
    .createHmac("sha512", BRIDGECARD_WEBHOOK_SECRET.value())
    .update(req.rawBody)
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
    // ── System mode gate — fail-closed on LOCKDOWN ─────────────────────────
    const systemMode = await getSystemMode();
    if (systemMode === "LOCKDOWN") {
      logger.warn(`[Bridgecard Webhook] System is LOCKDOWN. Rejecting ${eventType}.`);
      return res.status(200).json({ received: true, skipped: "LOCKDOWN" });
    }

    switch (eventType) {
      // ── Real-time transaction authorisation ─────────────────────────────
      case "transaction.authorisation": {
        const bridgecard_card_id = eventData?.card_id;
        const amount_kobo = Number(eventData?.amount || 0);
        const amount_ngn = amount_kobo / 100;
        const merchant = eventData?.merchant_name || "Unknown";
        const merchantCountry = eventData?.merchant_country || "";
        const transactionCurrency = eventData?.currency || eventData?.transaction_currency || "";
        // Round to nearest second to tolerate minor timestamp drift between retries
        const txnTimeSec = Math.floor(Number(eventData?.transaction_date || eventData?.created_at || Date.now()) / 1000);
        let approved = eventData?.status === "approved";
        let declineReason = eventData?.decline_reason || "Unknown";
        const authEventId = event?.id || `txn_${Date.now()}`;

        // ── Phase 4: Composite idempotency hash ────────────────────────────
        // Deduplicates by logical charge identity rather than Bridgecard's event ID.
        // Survives webhook retries that rotate the event ID for the same card swipe.
        const compositeHash = crypto
          .createHash("sha256")
          .update(`${bridgecard_card_id}:${amount_kobo}:${merchant}:${txnTimeSec}`)
          .digest("hex");
        const compositeIdempotencyKey = `bc_charge:${compositeHash}`;

        // ── Webhook deduplication — primary guard on composite hash ─────────
        const hashRef = db.collection("webhook_events").doc(compositeIdempotencyKey);
        const existingHash = await hashRef.get();
        if (existingHash.exists) {
          logger.info(`[Bridgecard Webhook] Duplicate charge (composite hash ${compositeHash.slice(0,12)}…) — skipping.`);
          return res.status(200).json({ received: true, skipped: "duplicate_hash" });
        }

        // Secondary guard on raw event ID (catches rapid-fire identical event IDs)
        const eventRef = db.collection("webhook_events").doc(authEventId);
        const existingEvent = await eventRef.get();
        if (existingEvent.exists) {
          logger.info(`[Bridgecard Webhook] Duplicate event ${authEventId} — skipping.`);
          return res.status(200).json({ received: true, skipped: "duplicate" });
        }

        // Reserve both slots atomically (best-effort before DB writes)
        await Promise.all([
          hashRef.set({ event: eventType, received_at: FieldValue.serverTimestamp(), status: "processing", authEventId }),
          eventRef.set({ event: eventType, received_at: FieldValue.serverTimestamp(), status: "processing", compositeHash }),
        ]);

        // Find the Firestore card doc by bridgecard_card_id
        const cardsSnap = await db.collection("cards")
          .where("bridgecard_card_id", "==", bridgecard_card_id)
          .limit(1)
          .get();

        if (!cardsSnap.empty) {
          const cardDoc = cardsSnap.docs[0];
          const card = cardDoc.data();
          const cardStatus = card.local_status || card.status;

          // ── Rule engine — only runs if Bridgecard approved AND card is active ──
          if (approved && cardStatus === "active") {
            const ruleEvaluation = await evaluateTransaction(cardDoc.id, amount_ngn, merchant, { merchantCountry, transactionCurrency });
            if (!ruleEvaluation.approved) {
              approved = false;
              declineReason = ruleEvaluation.reason;
              logger.warn(`[RuleEngine] BLOCKED authorized transaction. Reason: ${declineReason}`);
              // Best-effort re-freeze at Bridgecard side
              await internalFreezeBridgecard(bridgecard_card_id, true)
                .catch(e => logger.error("[Webhook] Emergency freeze failed", e));
              // State machine: active → frozen
              await cardDoc.ref.update({
                local_status: "frozen",
                status: "blocked",
                lifecycle_version: FieldValue.increment(1),
                bridgecard_status: "frozen",
              });
            }
          } else if (approved && cardStatus !== "active") {
            // Card was frozen/terminated while the Bridgecard charge was in-flight
            approved = false;
            declineReason = `Card is ${cardStatus}`;
            logger.warn(`[Webhook] Charge on non-active card ${cardDoc.id} (${cardStatus}) — declining.`);
          }

          const accountSnap = await db.collection("accounts").doc(card.account_id).get();
          const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : null;

          if (!ownerUid) {
            logger.error(`[Webhook] Owner UID missing for card ${cardDoc.id}. Skipping.`);
            await eventRef.set({ status: "error", error: "missing_owner" }, { merge: true });
            break;
          }

          if (approved) {
            // ── Route approved charge through orchestrator ──────────────────
            try {
              await getOrchestrator()({
                type: "card_charge",
                userId: ownerUid,
                amount: amount_ngn,
                // Phase 4: Use composite hash as idempotency key — immune to event ID rotation
                idempotencyKey: compositeIdempotencyKey,
                metadata: {
                  cardId: cardDoc.id,
                  accountId: card.account_id,
                  merchantName: merchant,
                  bridgecardRef: authEventId,
                  compositeHash,
                },
                correlationId: `bridgecardWebhook:${authEventId}`,
              });
              await Promise.all([
                eventRef.set({ status: "completed" }, { merge: true }),
                hashRef.set({ status: "completed" }, { merge: true }),
              ]);
            } catch (orchErr) {
              logger.error(`[Webhook] Orchestrator failed for ${authEventId}:`, orchErr.message);
              await Promise.all([
                eventRef.set({ status: "failed", error: orchErr.message }, { merge: true }),
                hashRef.set({ status: "failed", error: orchErr.message }, { merge: true }),
              ]);
              // Don't throw — we must return 200 to Bridgecard to prevent retries
              // that could double-charge. The UNKNOWN status in the txn document
              // will be caught by the reconciliation cron.
            }
          } else {
            // ── Declined: write transaction record + notify ─────────────────
            const txnRef = db.collection("transactions").doc();
            await txnRef.set({
              user_id: ownerUid,
              card_id: cardDoc.id,
              account_id: card.account_id,
              type: "card_charge",
              status: "DECLINED",
              amount: amount_ngn,
              merchant_name: merchant,
              decline_reason: declineReason,
              source: "bridgecard_webhook",
              bridgecard_event_id: authEventId,
              created_at: FieldValue.serverTimestamp(),
            });
            await eventRef.set({ status: "declined", reason: declineReason }, { merge: true });
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
                const isSentinel = userHasSentinelAccess(uDoc.data());
                if (!isSentinel) {
                  shouldSendPush = false;
                } else {
                  const ruleSnap = await db.collection("rules")
                    .where("card_id", "==", cardDoc.id)
                    .where("sub_type", "==", "instant_breach_alert")
                    .limit(1)
                    .get();
                  if (ruleSnap.empty) {
                    shouldSendPush = false;
                  }
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
          const snap = await db.collection("card_funding_requests").where("transaction_reference", "==", txRef).limit(1).get();
          if (!snap.empty) {
            const reqDoc = snap.docs[0];
            const reqData = reqDoc.data();
            // Prevent double refunds
            if (reqData.status !== "failed" && reqData.status !== "explicit_rollback") {
              const uid = reqData.uid;
              const amountNgn = reqData.amount_ngn || (reqData.amount_kobo / 100);
              const walletRef = db.doc(`users/${uid}/wallet/balance`);
              const ledgerRef = db.collection("wallet_ledger").doc();
              
              try {
                await db.runTransaction(async (t) => {
                  const reqCurrent = await t.get(reqDoc.ref);
                  if (reqCurrent.data().status === "failed" || reqCurrent.data().status === "explicit_rollback") return;
                  
                  // Refund wallet
                  t.set(walletRef, { balance: FieldValue.increment(amountNgn) }, { merge: true });
                  
                  // Record ledger entry
                  t.set(ledgerRef, {
                    user_id: uid,
                    type: "credit",
                    amount: amountNgn,
                    status: "success",
                    metadata: { reason: "bridgecard_funding_failed_refund", transaction_reference: txRef },
                    created_at: Date.now()
                  });
                  
                  // Update request
                  t.update(reqDoc.ref, { status: "failed", refunded_at: Date.now() });
                });
                logger.info(`[Webhook] Async Refunded ${amountNgn} NGN to ${uid} for failed funding ${txRef}`);
              } catch (e) {
                logger.error(`[Webhook] CRITICAL - Failed to refund ${txRef} for ${uid}`, e);
              }
            }
          }
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
