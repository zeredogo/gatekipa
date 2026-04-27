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
      "token": `Bearer ${BRIDGECARD_ACCESS_TOKEN.value().trim()}`,
      "issuing-app-id": ISSUING_APP_ID,
    },
    timeout: 60_000, // cardholder KYC can take ~45s
  });
}

/** AES-256 encrypt a 4-digit PIN using the Bridgecard secret key */
function encryptPin(pin) {
  const secret = BRIDGECARD_SECRET_KEY.value().trim();
  let encryptedPin = "";
  // Bridgecard's backend API struggles to parse URL-unsafe base64 chars (+ and /) properly.
  // We loop to generate a safe salt combination string. 
  let attempts = 0;
  while (attempts < 100) {
    encryptedPin = AES256.encrypt(String(pin), secret);
    if (!encryptedPin.includes("+") && !encryptedPin.includes("/")) {
      return encryptedPin;
    }
    attempts++;
  }
  // Fallback (rare but safe)
  return encryptedPin;
}

exports.bridgecardClient = bridgecardClient;

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
  // IMPORTANT: Bridgecard validates every image URL. Placeholder or empty URLs
  // will cause an "Invalid ID url" 400 rejection. We must fail FAST here.
  let identityObject = null;
  if (data.id_type) {
    // --- Government ID path (NIN, INTERNATIONAL_PASSPORT, PVC, DRIVERS_LICENSE) ---
    // Per Bridgecard docs: requires id_no, id_image (real URL), and bvn.
    const formattedIdType = data.id_type.trim().toUpperCase().replace(/\s+/g, "_");
    const idImage = data.id_image || userData.kycMeta?.photo;
    const selfieImage = data.selfie_image || userData.bvnMeta?.photo || userData.kycMeta?.selfie;
    const idNo = data.id_no ? data.id_no.trim() : (userData.kycMeta?.idNumber || null);
    const bvnForId = data.bvn_for_id || bvn;
    
    if (!idImage || idImage.includes('placeholder') || idImage.startsWith('data:')) {
      throw new HttpsError(
        "failed-precondition",
        "A valid government ID photo URL is required. Please complete the ID upload step in your profile."
      );
    }
    if (!selfieImage || selfieImage.includes('placeholder') || selfieImage.startsWith('data:')) {
      throw new HttpsError(
        "failed-precondition",
        "A valid selfie photo URL is required. Please complete the selfie upload step in your profile."
      );
    }
    if (!idNo) {
      throw new HttpsError("failed-precondition", "ID number is required for government ID verification.");
    }
    identityObject = {
      id_type: formattedIdType,
      id_no: idNo,
      id_image: idImage,
      ...(bvnForId ? { bvn: bvnForId.trim() } : {}),
    };
  } else if (bvn) {
    // --- BVN path (simplest & most reliable for Nigerian users) ---
    // Per Bridgecard docs: only needs bvn + selfie_image. No id_image.
    const selfieImage = data.selfie_image || userData.bvnMeta?.photo || userData.kycMeta?.selfie;
    if (!selfieImage || selfieImage.includes('placeholder') || selfieImage.startsWith('data:')) {
      throw new HttpsError(
        "failed-precondition",
        "A valid selfie photo URL is required for BVN verification. Please complete the selfie step in your profile."
      );
    }
    identityObject = {
      id_type: "NIGERIAN_BVN_VERIFICATION",
      bvn: bvn.trim(),
      selfie_image: selfieImage,
    };
  } else if (userData.kycStatus === "verified" && userData.kycMeta?.idNumber) {
    // --- Fallback: user completed internal KYC ---
    const selfieImage = userData.kycMeta.selfie;
    const idNo = userData.kycMeta.idNumber;
    
    if (!selfieImage || selfieImage.includes('placeholder')) {
      throw new HttpsError(
        "failed-precondition",
        "Your profile is missing a selfie photo. Please complete identity verification in your profile settings."
      );
    }

    if (userData.kycMeta.country === 'Nigeria' && !userData.kycMeta.photo) {
      // Treat ID Number as BVN for Nigerians who didn't upload a document photo
      identityObject = {
        id_type: "NIGERIAN_BVN_VERIFICATION",
        bvn: idNo,
        selfie_image: selfieImage,
      };
    } else if (userData.kycMeta.photo) {
      // Treat as Government ID if photo was provided
      const idImage = userData.kycMeta.photo;
      const idType = userData.kycMeta.idType || "NIGERIAN_NIN";
      identityObject = {
        id_type: idType.trim().toUpperCase().replace(/\s+/g, "_"),
        id_no: idNo,
        id_image: idImage,
      };
    } else {
      throw new HttpsError("failed-precondition", "A valid government ID photo URL is required for non-Nigerian users.");
    }
  } else {
    throw new HttpsError("failed-precondition", "You must complete Government Issued ID or BVN verification to register as a Cardholder.");
  }

  // Use data from request, fallback to user profile data if omitted
  const first_name = data.first_name || userData.firstName || "";
  const last_name = data.last_name || userData.lastName || "";
  let phone = data.phone || userData.phoneNumber || "";
  
  // Format phone to international (+234...)
  if (phone) {
    phone = phone.replace(/[^0-9+]/g, ''); // strip spaces, dashes, etc
    if (!phone.startsWith('+')) {
      if (phone.startsWith('0') && phone.length === 11) {
        phone = '+234' + phone.substring(1);
      } else if (phone.startsWith('234')) {
        phone = '+' + phone;
      } else {
        // Fallback for Nigeria, adjust if app supports other countries
        phone = '+234' + phone; 
      }
    }
  }
  
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
    const bridgecardResponse = err.response?.data;
    const msg = bridgecardResponse?.message || err.message;
    logger.error("[Bridgecard] registerCardholder error details:", { 
      status, 
      message: msg, 
      responseData: bridgecardResponse,
      url: "/cardholder/register_cardholder_synchronously" 
    });
    
    // Auto-heal: ONLY revert kycStatus if Bridgecard explicitly rejected the
    // user's identity documents with a 400 error. This prevents transient
    // network failures, timeouts (ECONNABORTED), and Bridgecard 5xx errors
    // from wiping out a legitimately verified user's KYC status.
    const isIdentityRejection = status === 400 && msg && (
      msg.toLowerCase().includes("bvn") ||
      msg.toLowerCase().includes("identity") ||
      msg.toLowerCase().includes("id number") ||
      msg.toLowerCase().includes("invalid id") ||
      msg.toLowerCase().includes("verification failed") ||
      msg.toLowerCase().includes("not found") ||
      msg.toLowerCase().includes("mismatch")
    );

    if (isIdentityRejection && userData.kycStatus === "verified") {
      logger.warn(`[Bridgecard] Identity explicitly rejected (HTTP 400). Reverting kycStatus for UID ${uid}. Reason: ${msg}`);
      await db.collection("users").doc(uid).update({ kycStatus: "unverified" }).catch(() => {});
    } else if (userData.kycStatus === "verified") {
      // Log that we intentionally preserved the user's verified status
      logger.info(`[Bridgecard] registerCardholder failed (status=${status}) but NOT reverting kycStatus — transient error, not identity rejection.`);
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

  // Personal cards (free/instant plan) use account_id === uid as the ownership proof
  // because no separate accounts/{uid} document exists for them.
  const cardAccountId = cardSnap.data().account_id;
  if (cardAccountId !== uid) {
    const accountSnap = await db.collection("accounts").doc(cardAccountId).get();
    if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
      throw new HttpsError("permission-denied", "Not your card.");
    }
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
  logger.info(`[Bridgecard] Raw pin length: ${String(pin).length}. Encrypted pin length: ${encryptedPin.length}`);

  const cardCurrency = data.card_currency === "USD" ? "USD" : "NGN";
  const client = bridgecardClient();
  let feeToDeductNGN = 0;
  let deductCardsIncluded = false;
  
  const cardLimit = data.card_limit || "500000"; // Default $5k spending limit
  const requiredFundingUsd = cardLimit === "1000000" ? 4 : 3;

  if (cardCurrency === "USD") {
    try {
      // Use Gatekipa's custom rate from system_state/global
      const sysStateSnap = await db.doc("system_state/global").get();
      const sysData = sysStateSnap.exists ? sysStateSnap.data() : {};
      
      let rate = sysData.gatekipa_usd_rate;
      
      if (!rate || !Number.isFinite(rate)) {
        logger.warn("[Bridgecard] gatekipa_usd_rate not found in system_state/global, falling back to 1700.");
        rate = 1700;
      }
      
      // $3 (or $4) minimum prefund + $0.5 Gatekipa fee converted to NGN for wallet deduction
      const totalUsdCost = requiredFundingUsd + 0.5;
      feeToDeductNGN = Math.ceil(totalUsdCost * rate);
      logger.info(`[Bridgecard] Gatekipa USD card FX rate: ${rate}. NGN equivalent of $${totalUsdCost}: ${feeToDeductNGN}`);
    } catch(e) {
      logger.warn("[Bridgecard] FX rate fetch failed. Using safe fallback of 1700.", e.message);
      const totalUsdCost = requiredFundingUsd + 0.5;
      feeToDeductNGN = Math.ceil(totalUsdCost * 1700); // Safe conservative fallback
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
        if (planTier === "none") {
           throw new HttpsError("failed-precondition", "You must purchase a plan before creating additional cards.");
        }
      }
    }

    if (feeToDeductNGN > 0) {
      const walletDoc = await t.get(walletRef);
      if (!walletDoc.exists) throw new HttpsError("failed-precondition", "Wallet not initialized.");
      const walletData = walletDoc.data() || {};
      const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
      const currentBalanceNgn = currentBalanceKobo / 100;

      if (currentBalanceNgn < feeToDeductNGN) {
        throw new HttpsError("failed-precondition", `Insufficient funds. Needed: ~${feeToDeductNGN} NGN.`);
      }
      
      const feeToDeductKobo = Math.round(feeToDeductNGN * 100);

      // Atomically deduct fee (Dual Write)
      t.update(walletRef, { 
        balance_kobo: FieldValue.increment(-feeToDeductKobo),
        cached_balance: FieldValue.increment(-feeToDeductNGN),
        balance: FieldValue.increment(-feeToDeductNGN) 
      });
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

  // ── BUILD BRIDGECARD CREATE CARD PAYLOAD ────────────────────────────────────
  // STRICTLY per Bridgecard USD Cards API docs:
  // - card_type: "virtual" or "physical" (required)
  // - card_brand: "Mastercard" (required, only option)
  // - card_currency: "USD" or "NGN" (required)
  // - card_limit: "500000" ($5k) or "1000000" ($10k) — REQUIRED for USD cards
  // - funding_amount: string in cents, min "300" for $5k limit — REQUIRED for USD
  // - pin: AES-256 encrypted 4-digit PIN (required)
  // - transaction_reference: optional but used for idempotency
  const usdCreationRef = `gk_usd_create_${card_id}_${Date.now()}`;

  const payload = {
    cardholder_id,
    card_type: "virtual",
    card_brand: "Mastercard",
    card_currency: cardCurrency,
    pin: encryptedPin,
    ...(cardCurrency === "USD" && {
      card_limit: cardLimit,
      funding_amount: requiredFundingUsd === 4 ? "400" : "300",  // minimum funding (cents)
      transaction_reference: usdCreationRef,
    }),
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
    // Define error message FIRST — used both in queue doc and thrown error.
    const errMsg = err.response?.data?.message || err.message || "Unknown Bridgecard error";
    console.warn(`[Bridgecard] createBridgecard failed for ${uid}. Reason: ${errMsg}. Rolling back.`);
    try {
      await db.runTransaction(async (rollbackT) => {
        if (deductCardsIncluded) {
          rollbackT.update(userRef, { cardsIncluded: FieldValue.increment(1) });
        }
        if (didDeductBalance && feeToDeductNGN > 0) {
          const feeKobo = Math.round(feeToDeductNGN * 100);
          rollbackT.update(walletRef, { 
            balance_kobo: FieldValue.increment(feeKobo),
            cached_balance: FieldValue.increment(feeToDeductNGN),
            balance: FieldValue.increment(feeToDeductNGN) 
          });
          rollbackT.set(ledgerRef, { status: "reversed", metadata: "Bridgecard API failure", reversed_at: Date.now() }, { merge: true });
        }
      });
    } catch (rollbackErr) {
      console.error(`[CRITICAL] FAILED TO ROLLBACK CARD CREATION (Quota/Fee) FOR UID ${uid}`, rollbackErr);
    }
    
    // Phase 3: Mark DLQ queue item as FAILED with the real error message.
    await provisioningQueueRef.set({ status: "EXPLICIT_ROLLBACK", error: errMsg, failed_at: Date.now() }, { merge: true });

    console.error("[Bridgecard] createBridgecard error:", errMsg);
    throw new HttpsError("failed-precondition", errMsg);
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
  // FIX: Personal (free-tier) cards have account_id === uid but NO accounts/{uid} doc.
  // Mirrors the same pattern used correctly in createBridgecard (line 301-306).
  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const cardAccountId = cardSnap.data().account_id;
  if (cardAccountId !== uid) {
    const accountSnap = await db.collection("accounts").doc(cardAccountId).get();
    if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
      throw new HttpsError("permission-denied", "Not your card.");
    }
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
      if (!doc.exists) {
        throw new HttpsError("failed-precondition", "Your wallet has not been initialized. Please contact support.");
      }
      const walletData = doc.data();
      // Use balance_kobo as authoritative source (matches the dual-write standard).
      const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
      const currentBalanceNgn = currentBalanceKobo / 100;
      
      if (currentBalanceNgn < amount) {
        throw new HttpsError("failed-precondition", "Insufficient funds in your Gatekeeper Vault.");
      }
      
      const amountKoboNum = Math.round(amount * 100);
      // Dual-write deduction — keeps all three balance fields in sync.
      t.update(walletRef, {
        balance_kobo: FieldValue.increment(-amountKoboNum),
        cached_balance: FieldValue.increment(-amount),
        balance: FieldValue.increment(-amount),
      });
      
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

  // Route to the correct Bridgecard endpoint based on card currency.
  // Per docs: NGN cards → /naira_cards/fund_naira_card (amount in kobo)
  //           USD cards → /cards/fund_card (amount in cents, string)
  const cardData = cardSnap.data();
  const bridgecardCurrency = cardData.bridgecard_currency || "NGN";
  
  let fundEndpoint;
  let fundPayload;
  
  if (bridgecardCurrency === "USD") {
    // USD cards: amount sent to Flutter UI is in NGN, but Bridgecard fund_card 
    // expects USD cents. We cannot silently convert without a live rate — so we
    // require the Flutter caller to send a usd_amount_cents field for USD cards.
    if (!data.usd_amount_cents) {
      throw new HttpsError("invalid-argument", "USD card funding requires 'usd_amount_cents' (integer, in cents e.g. 300 = $3).");
    }
    const usdCents = Math.round(data.usd_amount_cents);
    if (usdCents < 100) {
      throw new HttpsError("invalid-argument", "Minimum USD card funding is $1 (100 cents).");
    }
    fundEndpoint = "/cards/fund_card";
    fundPayload = {
      card_id: bridgecard_card_id,
      amount: String(usdCents), // docs say string, in cents
      transaction_reference,
    };
  } else {
    // NGN cards: amount in kobo (string)
    fundEndpoint = "/naira_cards/fund_naira_card";
    fundPayload = {
      card_id: bridgecard_card_id,
      amount: amountKobo,
      transaction_reference,
    };
  }

  try {
    const client = bridgecardClient();
    const res = await client.post(fundEndpoint, fundPayload);

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
        const refundKobo = Math.round(amount * 100);
        // Full dual-write refund — all three balance fields must be restored.
        rollbackT.update(walletRef, {
          balance_kobo: FieldValue.increment(refundKobo),
          cached_balance: FieldValue.increment(amount),
          balance: FieldValue.increment(amount),
        });
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
// Freeze or unfreeze a card. Accepts an optional currency parameter.
// BUG FIX (Bug A): USD cards must use /cards/ endpoints.
//   Old code always used /naira_cards/ regardless of currency, so USD card
//   freeze/unfreeze calls always hit the wrong endpoint and silently failed.
async function internalFreezeBridgecard(bridgecardCardId, freeze = true, currency = "NGN") {
  const client = bridgecardClient();
  const isUsd = (currency || "NGN").toUpperCase() === "USD";
  let endpoint;
  if (isUsd) {
    endpoint = freeze ? "/cards/freeze_card" : "/cards/unfreeze_card";
  } else {
    endpoint = freeze ? "/naira_cards/freeze_card" : "/naira_cards/unfreeze_card";
  }
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

  // --- Verify AES-256 signature (per Bridgecard docs) ---
  // Docs: decrypt x-webhook-signature header with your secret key using AES-256.
  // The decrypted value must equal your webhook secret key.
  const signatureHeader = req.headers["x-webhook-signature"] || "";
  let signatureValid = false;
  try {
    const AES256 = require("aes-everywhere");
    const decrypted = AES256.decrypt(signatureHeader, BRIDGECARD_WEBHOOK_SECRET.value());
    signatureValid = (decrypted === BRIDGECARD_WEBHOOK_SECRET.value());
  } catch (sigErr) {
    logger.error("[Bridgecard Webhook] AES signature decode failed:", sigErr.message);
  }

  if (!signatureValid) {
    console.warn("[Bridgecard Webhook] Invalid AES-256 signature — rejecting.");
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
      // ── NGN card debit (successful payment) ─────────────────────────────
      // Bridgecard docs event: naira_card_debit_event.successful
      // Fields: card_id (via cardholder_id lookup), amount (kobo string), currency, description, transaction_reference
      case "naira_card_debit_event.successful":
      case "card_debit_event.successful": {
        const bridgecard_card_id = eventData?.card_id;
        // For naira cards amount is in kobo, for USD cards amount is in cents
        const isUsdEvent = eventType === "card_debit_event.successful";
        const rawAmount = Number(eventData?.amount || 0);
        const amount_ngn = isUsdEvent ? rawAmount / 100 : rawAmount / 100; // both divide by 100 (kobo/cents)
        const merchant = eventData?.description || eventData?.merchant_name
          || eventData?.enriched_transaction?.merchant_name || "Unknown Merchant";
        const merchantCountry = eventData?.merchant_country || "";
        const transactionCurrency = eventData?.currency || "NGN";
        const txnTimeSec = Number(eventData?.transaction_timestamp || Math.floor(Date.now() / 1000));
        const authEventId = eventData?.transaction_reference || `txn_${Date.now()}`;

        // ── Phase 4: Composite idempotency hash ────────────────────────────
        // Deduplicates by logical charge identity rather than Bridgecard's event ID.
        // Survives webhook retries that rotate the event ID for the same card swipe.
        // BUG FIX: was using `amount_kobo` which was never declared — the variable is `rawAmount`.
        const compositeHash = crypto
          .createHash("sha256")
          .update(`${bridgecard_card_id}:${rawAmount}:${merchant}:${txnTimeSec}`)
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

          // NOTE: debit_event.successful means Bridgecard already approved the charge.
          // We cannot reverse it, but we run the rule engine for audit/alert purposes.
          if (cardStatus !== "active") {
            logger.warn(`[Webhook] Successful debit on non-active card ${cardDoc.id} (${cardStatus}). Flagging for review.`);
          }

          // BUG FIX (Bug E): Personal cards have account_id === uid with NO accounts document.
          // Old code: accountSnap.exists === false → ownerUid = null → entire charge skipped.
          // Fix: if accountSnap missing, treat account_id itself as the ownerUid (personal card).
          let ownerUid = null;
          if (card.account_id) {
            const accountSnap = await db.collection("accounts").doc(card.account_id).get();
            if (accountSnap.exists) {
              ownerUid = accountSnap.data().owner_user_id;
            } else {
              // Personal card — account_id IS the owner's UID
              ownerUid = card.account_id;
              logger.info(`[Webhook] Personal card detected for ${cardDoc.id} — ownerUid resolved from account_id.`);
            }
          }

          if (!ownerUid) {
            logger.error(`[Webhook] Owner UID could not be resolved for card ${cardDoc.id}. Skipping.`);
            await eventRef.set({ status: "error", error: "missing_owner" }, { merge: true });
            break;
          }

          // ── Route confirmed debit through orchestrator ──────────────────
          try {
            await getOrchestrator()({
              type: "card_charge",
              userId: ownerUid,
              amount: amount_ngn,
              idempotencyKey: compositeIdempotencyKey,
              metadata: {
                cardId: cardDoc.id,
                accountId: card.account_id,
                merchantName: merchant,
                bridgecardRef: authEventId,
                compositeHash,
                currency: transactionCurrency,
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
          }

          // ── Notify owner ────────────────────────────────────────────────
          if (ownerUid) {
            const currSymbol = transactionCurrency === "USD" ? "$" : "₦";
            await db.collection("users").doc(ownerUid)
              .collection("notifications").add({
                title: `${currSymbol}${amount_ngn.toLocaleString()} spent at ${merchant}`,
                body: `Your card ending in ${card.last4 || card.last_4 || "****"} was charged.`,
                timestamp: new Date(),
                isRead: false,
                type: "transaction",
              });
            try {
              const uDoc = await db.collection("users").doc(ownerUid).get();
              const fcmToken = uDoc.data()?.fcm_token;
              if (fcmToken) {
                await getMessaging().send({
                  token: fcmToken,
                  notification: {
                    title: `${currSymbol}${amount_ngn.toLocaleString()} Charged`,
                    body: `Your card was used at ${merchant}.`,
                  },
                  data: { type: "transaction_approved", amount: String(amount_ngn), merchant },
                });
              }
            } catch (fcmErr) {
              logger.error(`[FCM] Push failed for debit:`, fcmErr);
            }
          }
        }
        break;
      }

      // ── NGN card declined payment ────────────────────────────────────────
      case "naira_card_debit_event.declined":
      case "card_debit_event.declined": {
        const bridgecard_card_id = eventData?.card_id;
        const rawAmount = Number(eventData?.amount || 0);
        const amount_ngn = rawAmount / 100;
        const merchant = eventData?.description || eventData?.decline_reason?.split(".")[0] || "Unknown";
        const declineReason = eventData?.decline_reason || "Transaction declined";
        const transactionCurrency = eventData?.currency || "NGN";
        const authEventId = eventData?.transaction_reference || `txn_dec_${Date.now()}`;

        const cardsSnap = await db.collection("cards")
          .where("bridgecard_card_id", "==", bridgecard_card_id).limit(1).get();
        if (!cardsSnap.empty) {
          const cardDoc = cardsSnap.docs[0];
          const card = cardDoc.data();
          const accountSnap = await db.collection("accounts").doc(card.account_id).get();
          const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : null;

          // Write declined transaction record
          await db.collection("transactions").add({
            user_id: ownerUid,
            card_id: cardDoc.id,
            account_id: card.account_id,
            type: "card_charge",
            status: "DECLINED",
            amount: amount_ngn,
            currency: transactionCurrency,
            merchant_name: merchant,
            decline_reason: declineReason,
            source: "bridgecard_webhook",
            bridgecard_event_id: authEventId,
            created_at: FieldValue.serverTimestamp(),
          });

          if (ownerUid) {
            await db.collection("users").doc(ownerUid).collection("notifications").add({
              title: `Transaction Declined at ${merchant}`,
              body: declineReason,
              timestamp: new Date(), isRead: false, type: "alert",
            });
            try {
              const uDoc = await db.collection("users").doc(ownerUid).get();
              const fcmToken = uDoc.data()?.fcm_token;
              if (fcmToken) {
                await getMessaging().send({
                  token: fcmToken,
                  notification: { title: "Transaction Declined", body: `Charge at ${merchant} was declined.` },
                  data: { type: "transaction_declined", merchant },
                });
              }
            } catch (fcmErr) { logger.error("[FCM] Declined push failed:", fcmErr); }
          }
        }
        break;
      }

      // ── USD card reversal (merchant refund) ──────────────────────────────
      case "card_reversal_event.successful": {
        const txRef = eventData?.transaction_reference;
        const amount_cents = Number(eventData?.amount || 0);
        logger.info(`[Webhook] USD card reversal received. Ref: ${txRef}, amount: $${amount_cents / 100}`);
        // Reversals credit back to the card — record for audit
        await db.collection("transactions").add({
          type: "card_reversal",
          status: "COMPLETED",
          amount: amount_cents / 100,
          currency: "USD",
          bridgecard_card_id: eventData?.card_id,
          transaction_reference: txRef,
          source: "bridgecard_webhook",
          created_at: FieldValue.serverTimestamp(),
        });
        break;
      }

      // ── Card creation confirmed/failed ───────────────────────────────────
      case "card_creation_event.successful": {
        const meta_uid = eventData?.meta_data?.uid || eventData?.meta_data?.user_id;
        const bc_card_id = eventData?.card_id;
        if (meta_uid && bc_card_id) {
          // Find the card doc by bridgecard_card_id and mark it active
          const snap = await db.collection("cards")
            .where("bridgecard_card_id", "==", bc_card_id).limit(1).get();
          if (!snap.empty) {
            await snap.docs[0].ref.update({ status: "active", local_status: "active", bridgecard_status: "active" });
          }
        }
        break;
      }

      case "card_creation_event.failed": {
        const bc_card_id = eventData?.card_id;
        const reason = eventData?.reason || "Card creation failed at Bridgecard";
        if (bc_card_id) {
          const snap = await db.collection("cards")
            .where("bridgecard_card_id", "==", bc_card_id).limit(1).get();
          if (!snap.empty) {
            await snap.docs[0].ref.update({ status: "failed", local_status: "failed", fail_reason: reason });
          }
        }
        break;
      }

      // ── USD card credit (top-up confirmed) ──────────────────────────────
      case "card_credit_event.successful": {
        const txRef = eventData?.transaction_reference;
        if (txRef) {
          await db.collection("card_funding_requests")
            .where("transaction_reference", "==", txRef).limit(1).get()
            .then(snap => { if (!snap.empty) snap.docs[0].ref.update({ status: "completed" }); });
        }
        break;
      }

      case "card_credit_event.failed": {
        // USD card funding failed — refund wallet (mirrors naira_card_credit_event.failed logic)
        const txRef = eventData?.transaction_reference;
        if (txRef) {
          const snap = await db.collection("card_funding_requests")
            .where("transaction_reference", "==", txRef).limit(1).get();
          if (!snap.empty) {
            const reqDoc = snap.docs[0];
            const reqData = reqDoc.data();
            if (reqData.status !== "failed") {
              const uid = reqData.uid;
              const amountNgn = reqData.amount_ngn || 0;
              const walletRef = db.doc(`users/${uid}/wallet/balance`);
              await db.runTransaction(async (t) => {
                const cur = await t.get(reqDoc.ref);
                if (cur.data().status === "failed") return;
                const refundKobo = Math.round(amountNgn * 100);
                t.update(walletRef, {
                  balance_kobo: FieldValue.increment(refundKobo),
                  cached_balance: FieldValue.increment(amountNgn),
                  balance: FieldValue.increment(amountNgn),
                });
                t.update(reqDoc.ref, { status: "failed", refunded_at: Date.now() });
              });
            }
          }
        }
        break;
      }

      // ── Card frozen due to 30-day inactivity ─────────────────────────────
      case "card_freezed_due_to_30_days_inactivity_event.successful": {
        const bc_card_id = eventData?.card_id;
        if (bc_card_id) {
          const snap = await db.collection("cards")
            .where("bridgecard_card_id", "==", bc_card_id).limit(1).get();
          if (!snap.empty) {
            const cardDoc = snap.docs[0];
            await cardDoc.ref.update({ status: "frozen", local_status: "frozen", bridgecard_status: "frozen", freeze_reason: "30_day_inactivity" });
            const accountSnap = await db.collection("accounts").doc(cardDoc.data().account_id).get();
            const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : null;
            if (ownerUid) {
              await db.collection("users").doc(ownerUid).collection("notifications").add({
                title: "Card Frozen — Inactivity",
                body: "Your card was frozen after 30 days of no activity. Fund and unfreeze to reactivate.",
                timestamp: new Date(), isRead: false, type: "alert",
              });
            }
          }
        }
        break;
      }

      // ── Card flagged for fraud ────────────────────────────────────────────
      case "card_flagged_due_to_suspiscion_of_fraud.activated": {
        const bc_card_id = eventData?.card_id;
        if (bc_card_id) {
          const snap = await db.collection("cards")
            .where("bridgecard_card_id", "==", bc_card_id).limit(1).get();
          if (!snap.empty) {
            await snap.docs[0].ref.update({ status: "blocked", local_status: "frozen", bridgecard_status: "frozen", freeze_reason: "fraud_suspicion" });
          }
        }
        break;
      }

      // ── USD card deleted (maintenance fee unpaid) ─────────────────────────
      case "card_delete_event.successful": {
        const bc_card_id = eventData?.card_id;
        if (bc_card_id) {
          const snap = await db.collection("cards")
            .where("bridgecard_card_id", "==", bc_card_id).limit(1).get();
          if (!snap.empty) {
            const cardDoc = snap.docs[0];
            await cardDoc.ref.update({ status: "terminated", local_status: "terminated", bridgecard_status: "deleted", terminated_at: FieldValue.serverTimestamp() });
            const accountSnap = await db.collection("accounts").doc(cardDoc.data().account_id).get();
            const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : null;
            if (ownerUid) {
              await db.collection("users").doc(ownerUid).collection("notifications").add({
                title: "USD Card Deleted",
                body: "Your USD card was deleted due to an unpaid monthly maintenance fee. Please create a new card.",
                timestamp: new Date(), isRead: false, type: "alert",
              });
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
                  
                  // Full dual-write refund — all three balance fields must be restored.
                  const refundKobo = Math.round(amountNgn * 100);
                  t.update(walletRef, {
                    balance_kobo: FieldValue.increment(refundKobo),
                    cached_balance: FieldValue.increment(amountNgn),
                    balance: FieldValue.increment(amountNgn),
                  });
                  
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
  
  // FIX: Personal (free-tier) cards have account_id === uid but NO accounts/{uid} doc.
  const revealAccountId = cardSnap.data().account_id;
  if (revealAccountId !== uid) {
    const accountSnap = await db.collection("accounts").doc(revealAccountId).get();
    if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
      throw new HttpsError("permission-denied", "Not your card.");
    }
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
  
  // FIX: Personal (free-tier) cards have account_id === uid but NO accounts/{uid} doc.
  const otpAccountId = cardSnap.data().account_id;
  if (otpAccountId !== uid) {
    const accountSnap = await db.collection("accounts").doc(otpAccountId).get();
    if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
      throw new HttpsError("permission-denied", "Not your card.");
    }
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
