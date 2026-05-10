const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const SUDO_API_KEY = defineSecret("SUDO_API_KEY");
const BASE_URL = process.env.SUDO_BASE_URL || "https://api.sudo.africa"; // production default


function sudoClient() {
  return axios.create({
    baseURL: BASE_URL,
    headers: {
      Authorization: `Bearer ${SUDO_API_KEY.value()}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
  });
}

function sudoVaultClient() {
  const VAULT_BASE_URL = BASE_URL.replace("api", "vault");
  return axios.create({
    baseURL: VAULT_BASE_URL,
    headers: {
      Authorization: `Bearer ${SUDO_API_KEY.value()}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
  });
}

/**
 * Ensures a user is registered as a Sudo customer.
 * Uses existing profile data. If not found, registers and saves customer ID.
 */
async function ensureSudoCustomer(uid, userData) {
  if (userData.sudo_customer_id) {
    return userData.sudo_customer_id;
  }

  logger.info(`[Sudo] Registering new customer for UID ${uid}`);
  
  const client = sudoClient();
  const firstName = userData.firstName || "Gatekipa";
  const lastName = userData.lastName || "User";
  const name = `${firstName} ${lastName}`.trim();

  let phone = userData.phoneNumber || "";
  if (phone && !phone.startsWith('+')) {
    phone = phone.startsWith('0') ? `+234${phone.substring(1)}` : `+234${phone}`;
  }

  if (!userData.address || !userData.city || !userData.state) {
    throw new HttpsError("failed-precondition", "Incomplete KYC data: missing billing address, city, or state. Please update your profile.");
  }

  const dob = userData.dob || "1990/01/01";
  const identity = userData.bvn ? { type: "BVN", number: userData.bvn } : undefined;

  const payload = {
    type: "individual",
    name: name,
    status: "active",
    individual: {
      firstName: firstName,
      lastName: lastName,
      dob: dob,
      ...(identity && { identity })
    },
    billingAddress: {
      line1: userData.address,
      city: userData.city,
      state: userData.state,
      country: "NG",
      postalCode: userData.postalCode || "100001"
    },
    phoneNumber: phone,
    emailAddress: userData.email || `${uid}@gatekipa.ng`
  };

  try {
    const res = await client.post("/customers", payload);
    const customerId = res.data?.data?._id; // Adjust based on actual sudo response structure

    if (!customerId) {
      throw new Error("Missing customer ID in Sudo response");
    }

    await db.collection("users").doc(uid).update({ sudo_customer_id: customerId });
    return customerId;
  } catch (err) {
    const errorMsg = err.response?.data?.message || err.message;
    logger.error(`[Sudo] Failed to register customer: ${errorMsg}`, err.response?.data);
    throw new HttpsError("internal", `Failed to register Sudo customer: ${errorMsg}`);
  }
}

/**
 * Ensures a user has a dedicated Sudo sub-account (Account Funding Source).
 */
async function ensureSudoAccount(uid, customerId, userData) {
  if (userData.sudo_account_id) {
    return userData.sudo_account_id;
  }

  logger.info(`[Sudo] Creating dedicated sub-account for UID ${uid}`);
  const client = sudoClient();
  const payload = {
    type: "wallet",
    currency: "NGN",
    customerId: customerId
  };

  try {
    const res = await client.post("/accounts", payload);
    const accountId = res.data?.data?._id;

    if (!accountId) {
      throw new Error("Missing account ID in Sudo response");
    }

    await db.collection("users").doc(uid).update({ sudo_account_id: accountId });
    return accountId;
  } catch (err) {
    const errorMsg = err.response?.data?.message || err.message;
    logger.error(`[Sudo] Failed to create Sudo account: ${errorMsg}`, err.response?.data);
    throw new HttpsError("internal", `Failed to create Sudo account: ${errorMsg}`);
  }
}

/**
 * Gets the main company default Sudo account to use as the funding source.
 */
async function getSudoDefaultAccount() {
  const client = sudoClient();
  try {
    const res = await client.get("/accounts");
    const accounts = res.data?.data || [];
    const defaultAccount = accounts.find(a => a.isDefault === true);
    if (!defaultAccount) {
      throw new Error("No default account found in Sudo workspace");
    }
    return defaultAccount._id;
  } catch (err) {
    const errorMsg = err.response?.data?.message || err.message;
    logger.error(`[Sudo] Failed to fetch default account: ${errorMsg}`, err.response?.data);
    throw new HttpsError("internal", `Failed to fetch main Sudo account: ${errorMsg}`);
  }
}

/**
 * Creates an NGN Virtual Card via Sudo Africa using Gateway (Pool) Funding.
 * This avoids the requirement for per-user sub-accounts.
 * @param {string} uid - User ID
 * @param {object} userData - User Document Data
 * @param {string} cardId - Internal Gatekipa Card ID
 */
async function createSudoCardInternal(uid, userData, cardId) {
  const customerId = await ensureSudoCustomer(uid, userData);
  // NOTE: ensureSudoAccount (Sub-account creation) is bypassed for Gateway Funding

  const client = sudoClient();

  // Sudo Create Card payload using Gateway (Pool) Funding
  const payload = {
    customerId: customerId,
    cardProgramId: "69fca220d8e6bc0c0b02ff56",
    type: "virtual",
    currency: "NGN",
    brand: "Verve",
    issuer: "Sudo",
    status: "active",
    // We omit debitAccountId to trigger Gateway/Pool funding logic at Sudo
  };

  if (process.env.SUDO_CARD_PROGRAM_ID) {
    payload.cardProgramId = process.env.SUDO_CARD_PROGRAM_ID;
  }

  logger.info(`[Sudo] Issuing NGN Gateway card for customer ${customerId}, internal cardId: ${cardId}`);

  try {
    const res = await client.post("/cards", payload);
    const cardData = res.data?.data;
    
    if (!cardData || !cardData._id) {
      throw new Error("Missing card ID in Sudo response");
    }

    const sudoCardId = cardData._id;
    
    // FETCH FULL DETAILS FROM VAULT
    logger.info(`[Sudo] Fetching vault details for card ${sudoCardId}`);
    const vaultClient = sudoVaultClient();
    const vaultRes = await vaultClient.get(`/cards/${sudoCardId}?reveal=true`);
    const vaultData = vaultRes.data?.data;

    if (!vaultData) {
      throw new Error("Vault response missing card data");
    }

    const pan = vaultData.pan || vaultData.number || "";
    const cvv = vaultData.cvv || "";
    const expiryMonth = vaultData.expiryMonth || "";
    const expiryYear = vaultData.expiryYear || "";
    
    const last4 = pan ? pan.slice(-4) : "0000";
    const masked_number = pan ? `**** **** **** ${last4}` : "Card Issued";
    
    // Format expiry as MM/YY if year is 4 digits
    const formattedYear = expiryYear.toString().length === 4 ? expiryYear.toString().slice(-2) : expiryYear;
    const expiry = (expiryMonth && formattedYear) ? `${expiryMonth}/${formattedYear}` : "";

    logger.info(`[Sudo] Successfully issued and revealed Gateway card ${sudoCardId} for UID ${uid}`);

    return {
      sudo_card_id: sudoCardId,
      last4,
      masked_number,
      cvv,
      expiry,
      pan // Securely retrieved from Vault
    };

  } catch (err) {
    const errorMsg = err.response?.data?.message || err.message;
    logger.error(`[Sudo] Failed to issue card: ${errorMsg}`, err.response?.data);
    throw new HttpsError("internal", `Failed to issue Sudo NGN card: ${errorMsg}`);
  }
}

const { onRequest } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

/**
 * Records a declined JIT authorization attempt and notifies the user.
 * 
 * @param {string} sudoCardId - The Sudo card ID involved
 * @param {number} amountKobo - The transaction amount in kobo
 * @param {string} merchant - The merchant name
 * @param {string} reason - The specific reason for decline
 * @param {string} eventId - Sudo event ID
 */
async function recordJitDecline(sudoCardId, amountKobo, merchant, reason, eventId) {
  logger.warn(`[Sudo JIT] Recording decline for card ${sudoCardId}: ${reason}`);

  try {
    // 1. Find the card and owner
    const cardsSnap = await db.collection("cards").where("sudo_card_id", "==", sudoCardId).limit(1).get();
    if (cardsSnap.empty) return;
    
    const cardDoc = cardsSnap.docs[0];
    const card = cardDoc.data();
    const uid = card.account_id || card.created_by;

    // 2. O(1) idempotent write — deterministic document ID prevents duplicate
    //    alerts without requiring a collection scan on every declined webhook.
    const declineRef = db.collection("transactions").doc(`declined_${eventId}`);
    const existingDecline = await declineRef.get();
    if (existingDecline.exists) return;

    await declineRef.set({
      user_id: uid,
      card_id: cardDoc.id,
      account_id: card.account_id || uid,
      type: "card_charge",
      status: "DECLINED",
      amount: amountKobo / 100,
      currency: "NGN",
      merchant_name: merchant,
      decline_reason: reason,
      source: "sudo_jit_auth",
      sudo_event_id: eventId,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. In-app notification + FCM
    const title = `Transaction Declined at ${merchant}`;
    const body = reason || "Your Gatekipa card transaction was declined.";
    
    await db.collection("users").doc(uid).collection("notifications").add({
      title,
      body,
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    const userSnap = await db.collection("users").doc(uid).get();
    const fcmToken = userSnap.data()?.fcm_token;
    if (fcmToken) {
      const { getMessaging } = require("firebase-admin/messaging");
      await getMessaging().send({
        token: fcmToken,
        notification: { title, body },
        data: { type: "transaction_declined", merchant, amount: String(amountKobo / 100) },
      }).catch(e => logger.warn("[FCM] JIT decline notification failed", e.message));
    }
  } catch (err) {
    logger.error("[Sudo JIT] Failed to record decline:", err.message);
  }
}

exports.sudoWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // Webhook Security Authorization
  const webhookSecret = process.env.SUDO_WEBHOOK_SECRET;
  if (webhookSecret) {
    const authHeader = req.headers['authorization'] || req.headers['x-sudo-signature'];
    if (!authHeader || (authHeader !== `Bearer ${webhookSecret}` && authHeader !== webhookSecret)) {
      logger.error("[Sudo Webhook] Unauthorized request. Missing or invalid Authorization token.");
      return res.status(401).json({ error: "Unauthorized" });
    }
  }

  try {
    const payload = req.body;
    logger.info("[Sudo Webhook] Received event:", { type: payload.type || payload.event, eventId: payload._id });
    
    const eventType = payload.type || payload.event;
    const eventObject = payload.data?.object || payload.data;
    
    // Log raw webhook
    const eventId = payload._id || eventObject?._id || `sudo_${Date.now()}`;
    await db.collection("webhook_events").doc(eventId).set({
      ...payload,
      source: "sudo_webhook",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      status: "Received"
    }, { merge: true });

    // ── HANDLE JIT BALANCE INQUIRY ───────────────────────────────────────────
    if (eventType === "card.balance") {
      const sudoCardId = eventObject.card?._id || eventObject.cardId || eventObject.card;
      logger.info(`[Sudo JIT] Balance inquiry for card ${sudoCardId}`);

      if (!sudoCardId) return res.status(200).json({ statusCode: 200, responseCode: "00", data: { balance: 0 } });

      const cardsSnap = await db.collection("cards").where("sudo_card_id", "==", sudoCardId).limit(1).get();
      if (cardsSnap.empty) {
        return res.status(200).json({ statusCode: 200, responseCode: "00", data: { balance: 0 } });
      }

      const card = cardsSnap.docs[0].data();
      const uid = card.account_id || card.created_by;

      const walletDoc = await db.collection("users").doc(uid).collection("wallet").doc("balance").get();
      const walletData = walletDoc.exists ? walletDoc.data() : {};
      const balanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

      return res.status(200).json({
        statusCode: 200,
        responseCode: "00",
        data: { balance: balanceKobo }
      });
    }

    // ── HANDLE JIT AUTHORIZATION REQUEST ────────────────────────────────────
    if (eventType === "authorization.request" || eventType === "transaction.authorization") {
      const eventId = payload._id || `jit_${Date.now()}`;
      const sudoCardId = eventObject.card?._id || eventObject.cardId || eventObject.card;
      const amountKobo = Math.round(Number(eventObject.amount || 0)); 
      const merchant = eventObject.merchant?.name || "Unknown Merchant";

      logger.info(`[Sudo JIT] Auth request start. Event: ${eventId}, Card: ${sudoCardId}, Amount: ${amountKobo}`);

      if (!sudoCardId) return res.status(200).json({ statusCode: 200, data: { responseCode: "05" } });

      // 1. FAST IDEMPOTENCY CHECK
      const { checkIdempotency } = require("../core/idempotency");
      const existingTxnId = await checkIdempotency(`sudo_jit_auth:${eventId}`);
      if (existingTxnId) {
        logger.info(`[Sudo JIT] Idempotent hit for event ${eventId}. Already approved.`);
        return res.status(200).json({ statusCode: 200, data: { responseCode: "00" } });
      }

      // 2. RULE EVALUATION (PRE-TRANSACTION)
      const { evaluateTransaction } = require("../engines/ruleEngine");
      const ruleResult = await evaluateTransaction(sudoCardId, amountKobo / 100, merchant);
      if (!ruleResult.approved) {
        logger.warn(`[Sudo JIT] Rule violation for card ${sudoCardId}: ${ruleResult.reason}`);
        // Record the decline and notify the user asynchronously
        recordJitDecline(sudoCardId, amountKobo, merchant, ruleResult.reason, eventId);
        return res.status(200).json({ statusCode: 200, data: { responseCode: "51", message: ruleResult.reason } });
      }

      // 3. ATOMIC BALANCE LOCK & LEDGER RECORDING
      try {
        const result = await db.runTransaction(async (t) => {
          // Double-check idempotency inside transaction
          const idempotencyRef = db.collection("idempotency_keys").doc(`sudo_jit_auth:${eventId}`);
          const idempotencySnap = await t.get(idempotencyRef);
          if (idempotencySnap.exists) return { approved: true, code: "00" };

          const cardsSnap = await db.collection("cards").where("sudo_card_id", "==", sudoCardId).limit(1).get();
          if (cardsSnap.empty) throw new Error("Card not found");
          
          const cardDoc = cardsSnap.docs[0];
          const card = cardDoc.data();
          const uid = card.account_id || card.created_by;

          const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
          const walletDoc = await t.get(walletRef);
          if (!walletDoc.exists) throw new Error("Wallet not found");
          
          const cardSnap = await t.get(cardDoc.ref);
          const cardData = cardSnap.data();
          const allocatedAmountKobo = Math.round((cardData.allocated_amount ?? 0) * 100);

          const walletData = walletDoc.data();
          const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

          // Final balance check inside transaction
          if (currentBalanceKobo < amountKobo) {
            const reason = "Insufficient wallet balance";
            recordJitDecline(sudoCardId, amountKobo, merchant, reason, eventId);
            return { approved: false, code: "51", reason };
          }
          if (allocatedAmountKobo < amountKobo) {
            const reason = "Insufficient card limit";
            recordJitDecline(sudoCardId, amountKobo, merchant, reason, eventId);
            return { approved: false, code: "51", reason };
          }

          // Atomic deduction (Reservation)
          t.update(walletRef, {
            balance_kobo: FieldValue.increment(-amountKobo),
            cached_balance: FieldValue.increment(-(amountKobo / 100)),
            balance: FieldValue.increment(-(amountKobo / 100))
          });

          t.update(cardDoc.ref, {
            allocated_amount: FieldValue.increment(-(amountKobo / 100)),
            balance_limit: FieldValue.increment(-(amountKobo / 100)),
            spent_amount_kobo: FieldValue.increment(amountKobo),
            spent_amount: FieldValue.increment(amountKobo / 100),
            charge_count: FieldValue.increment(1)
          });

          // Record Idempotency Key
          t.set(idempotencyRef, {
            user_id: uid,
            result_txn_id: eventId,
            status: "SUCCESS",
            created_at: FieldValue.serverTimestamp()
          });

          // Ledger Recording (Reserved Funds)
          const ledgerRef = db.collection("wallet_ledger").doc(`jit_auth_${eventId}`);
          t.set(ledgerRef, {
            user_id: uid,
            type: "debit",
            amount_kobo: amountKobo,
            amount: amountKobo / 100,
            reference: eventId,
            source: "sudo_jit_auth",
            status: "reserved",
            merchant_name: merchant,
            created_at: FieldValue.serverTimestamp()
          });

          return { approved: true, code: "00" };
        });

        logger.info(`[Sudo JIT] ${result.approved ? "Approved" : "Declined"} transaction. Code: ${result.code} ${result.reason || ""}`);
        return res.status(200).json({
          statusCode: 200,
          data: { responseCode: result.code }
        });
      } catch (err) {
        logger.error(`[Sudo JIT] Transaction error:`, err);
        return res.status(200).json({ statusCode: 200, data: { responseCode: "05" } });
      }
    }

    // Handle card termination
    if (eventType === "card.terminated" || eventType === "card.termination") {
      const sudoCardId = eventObject._id;
      if (sudoCardId) {
        logger.info(`[Sudo Webhook] Processing card termination for ${sudoCardId}`);
        const cardsSnap = await db.collection("cards").where("sudo_card_id", "==", sudoCardId).limit(1).get();
        if (!cardsSnap.empty) {
          await cardsSnap.docs[0].ref.update({ 
            is_active: false, 
            status: "canceled", 
            updated_at: admin.firestore.FieldValue.serverTimestamp() 
          });
        } else {
          logger.warn(`[Sudo Webhook] Terminated card ${sudoCardId} not found in Firestore.`);
        }
      }
      return res.status(200).send("OK");
    }

    // Handle transaction events
    // Sudo events might be "transaction.successful", "successful.transaction", "authorization.closed", "transaction.refund"
    if (eventType && eventType.includes("transaction") && eventObject && eventObject.amount) {
      const isRefund = eventType === "transaction.refund" || eventObject.type === "refund";

      // Only process successful/closed transactions OR refunds
      if (!isRefund && eventObject.status !== "success" && eventObject.status !== "closed" && eventObject.status !== "approved") {
        logger.info(`[Sudo Webhook] Ignoring transaction ${eventId} with status: ${eventObject.status}`);
        return res.status(200).send("OK");
      }

      const sudoCardId = eventObject.card?._id || eventObject.cardId || eventObject.card;
      if (!sudoCardId) {
        logger.warn(`[Sudo Webhook] Could not find card ID in transaction ${eventId}`);
        return res.status(200).send("OK");
      }

      const rawAmount = Number(eventObject.amount);
      const merchant = eventObject.merchant?.name || "Unknown Merchant";
      const transactionCurrency = eventObject.currency || "NGN";
      const authEventId = eventId;
      const compositeHash = require("crypto")
          .createHash("sha256")
          .update(`${sudoCardId}:${rawAmount}:${merchant}:${authEventId}`)
          .digest("hex");
      const compositeIdempotencyKey = `sudo_charge:${compositeHash}`;

      // Deduplication check
      const hashRef = db.collection("webhook_events").doc(compositeIdempotencyKey);
      const existingHash = await hashRef.get();
      if (existingHash.exists) {
        logger.info(`[Sudo Webhook] Duplicate transaction (composite hash ${compositeHash.slice(0,12)}) — skipping.`);
        return res.status(200).send("OK");
      }

      await hashRef.set({ event: eventType, received_at: admin.firestore.FieldValue.serverTimestamp(), status: "processing", authEventId });

      // Find the card in Gatekipa
      const cardsSnap = await db.collection("cards")
        .where("sudo_card_id", "==", sudoCardId)
        .limit(1)
        .get();

      if (cardsSnap.empty) {
        logger.warn(`[Sudo Webhook] Card ${sudoCardId} not found in Firestore. Skipping.`);
        await hashRef.set({ status: "failed", error: "Card not found" }, { merge: true });
        return res.status(200).send("OK");
      }

      const cardDoc = cardsSnap.docs[0];
      const card = cardDoc.data();
      
      let ownerUid = null;
      if (card.account_id) {
        const accountSnap = await db.collection("accounts").doc(card.account_id).get();
        if (accountSnap.exists) {
          ownerUid = accountSnap.data().owner_user_id;
        } else {
          ownerUid = card.account_id; // Personal card fallback
        }
      }

      if (!ownerUid) {
        logger.error(`[Sudo Webhook] Owner UID missing for card ${cardDoc.id}.`);
        await hashRef.set({ status: "failed", error: "missing_owner" }, { merge: true });
        return res.status(200).send("OK");
      }

      // Invoke Orchestrator to record the card charge or refund
      let processTransactionInternal;
      try {
        processTransactionInternal = require("./transactionService").processTransactionInternal;
      } catch (e) {
        logger.error("[Sudo Webhook] Failed to load transactionService", e);
        throw e;
      }

      try {
        if (isRefund) {
          await processTransactionInternal({
            type: "wallet_funding", // Refund acts as a wallet credit
            userId: ownerUid,
            amount: rawAmount,
            idempotencyKey: compositeIdempotencyKey,
            metadata: {
              cardId: cardDoc.id,
              accountId: card.account_id,
              merchantName: merchant,
              bridgecardRef: authEventId, 
              compositeHash,
              currency: transactionCurrency,
              source: "sudo_refund", // Distinct source to track correctly
              paystackRef: `refund_${authEventId}` // Used as reference for wallet ledger
            },
            correlationId: `sudoRefundWebhook:${authEventId}`,
          });
        } else {
          await processTransactionInternal({
            type: "card_charge",
            userId: ownerUid,
            amount: rawAmount,
            idempotencyKey: compositeIdempotencyKey,
            metadata: {
              cardId: cardDoc.id,
              accountId: card.account_id,
              merchantName: merchant,
              bridgecardRef: authEventId,
              compositeHash,
              currency: transactionCurrency,
              source: "sudo"
            },
            correlationId: `sudoChargeWebhook:${authEventId}`,
          });

          // ── SETTLEMENT RECONCILIATION ─────────────────────────────────────
          // The JIT auth created a wallet_ledger entry with status: "reserved".
          // Now that the charge is confirmed and settled, update its status to
          // "settled" so reconciliation reports reflect accurate fund states.
          // The doc ID is deterministic: jit_auth_{authEventId}
          const reservationRef = db.collection("wallet_ledger").doc(`jit_auth_${authEventId}`);
          reservationRef.update({
            status: "settled",
            settled_at: admin.firestore.FieldValue.serverTimestamp(),
            settlement_txn_id: compositeIdempotencyKey,
          }).catch(e =>
            // Non-critical: reservation may not exist (pre-hardening card swipes)
            logger.warn(`[Sudo Webhook] Could not settle reservation jit_auth_${authEventId}: ${e.message}`)
          );
        }
        await hashRef.set({ status: "completed" }, { merge: true });
      } catch (orchErr) {
        logger.error(`[Sudo Webhook] Orchestrator failed for ${authEventId}:`, orchErr);
        await hashRef.set({ status: "failed", error: orchErr.message }, { merge: true });
        return res.status(200).send("OK"); // Avoid retries if orchestrator rejects
      }
      
      // Notify owner
      try {
        const currSymbol = transactionCurrency === "USD" ? "$" : "₦";
        const title = isRefund 
          ? `${currSymbol}${rawAmount.toLocaleString()} Refunded from ${merchant}`
          : `${currSymbol}${rawAmount.toLocaleString()} spent at ${merchant}`;
        const body = isRefund
          ? `Your card ending in ${card.last4 || "****"} was refunded.`
          : `Your card ending in ${card.last4 || "****"} was charged.`;

        await db.collection("users").doc(ownerUid)
          .collection("notifications").add({
            title,
            body,
            timestamp: new Date(),
            isRead: false,
            type: isRefund ? "refund" : "transaction",
          });
        
        const { getMessaging } = require("firebase-admin/messaging");
        const uDoc = await db.collection("users").doc(ownerUid).get();
        const fcmToken = uDoc.data()?.fcm_token;
        if (fcmToken) {
          await getMessaging().send({
            token: fcmToken,
            notification: { title, body },
            data: { type: isRefund ? "transaction_refund" : "transaction_approved", amount: String(rawAmount), merchant },
          });
        }
      } catch (notifyErr) {
        logger.warn(`[Sudo Webhook] Notification failed:`, notifyErr);
      }
    } else {
      // Ignored event
      logger.info(`[Sudo Webhook] Unhandled event type: ${eventType}`);
    }
    
    res.status(200).send("OK");
  } catch (error) {
    logger.error("[Sudo Webhook] Error processing event:", error);
    res.status(500).send("Error");
  }
});

/**
 * 'Funds' a Sudo Virtual Card by updating its local allocated_amount in Firestore.
 * With Gateway (Pool) Funding, funds remain in the Gatekipa main wallet and are 
 * authorized via JIT up to the allocated_amount limit.
 * @param {string} uid User ID
 * @param {object} userData User Document Data
 * @param {number} amountNGN Amount to transfer in NGN
 * @param {string} transactionReference Internal reference ID
 */
async function fundSudoCardInternal(uid, userData, amountNGN, transactionReference) {
  // Find the card associated with this reference or context
  // NOTE: In the calling context of bridgecardService, we already have the card_id.
  // However, this function is designed to be a generic funder.
  
  // We'll rely on the orchestrator or the caller to provide the cardId in the future,
  // but for now, we'll look it up from the transactionReference or metadata if needed.
  // Actually, bridgecardService passes 'transaction_reference' which contains the card_id.
  
  const cardIdMatch = transactionReference.match(/gk_(.*)_/);
  const cardId = cardIdMatch ? cardIdMatch[1] : null;

  if (!cardId) {
    logger.error(`[Sudo] Could not extract cardId from reference: ${transactionReference}`);
    throw new HttpsError("invalid-argument", "Missing card identifier in funding reference.");
  }

  logger.info(`[Sudo] Funding Gateway Card ${cardId}. Allocating NGN ${amountNGN}`);

  try {
    await db.collection("cards").doc(cardId).update({
      allocated_amount: FieldValue.increment(amountNGN),
      balance_limit: FieldValue.increment(amountNGN), // migration compat
      last_funded_at: Date.now(),
      last_funding_ref: transactionReference
    });

    return {
      success: true,
      message: "Card limit updated successfully.",
      transaction_reference: transactionReference,
      sudo_transfer_id: "gateway_allocated"
    };
  } catch (err) {
    logger.error(`[Sudo] Failed to update card allocation: ${err.message}`);
    throw new HttpsError("internal", `Sudo Card Allocation failed: ${err.message}`);
  }
}

/**
 * Migration Endpoint: Finds all pending NGN cards (originally meant for Bridgecard)
 * and successfully provisions them via Sudo, deducting the fee if necessary.
 */
exports.migratePendingSudoCards = onRequest({ region: "us-central1", secrets: ["SUDO_API_KEY"] }, async (req, res) => {
  // Simple auth for the administrative script
  if (req.query.secret !== "GAT2026MIGRATE") {
    return res.status(403).send("Forbidden");
  }
  
  try {
    const cardsQuery = await db.collection("cards")
      .where("currency", "==", "NGN")
      .where("status", "in", ["pending", "pending_issuance"])
      .get();
      
    if (cardsQuery.empty) {
      return res.status(200).json({ success: true, message: "No pending NGN cards found." });
    }
    
    let processed = 0;
    let failed = 0;
    const errors = [];
    
    for (const cardDoc of cardsQuery.docs) {
      const cardData = cardDoc.data();
      const cardId = cardDoc.id;
      const uid = cardData.created_by || cardData.account_id;
      
      try {
        await db.runTransaction(async (t) => {
          const userRef = db.collection("users").doc(uid);
          const userDoc = await t.get(userRef);
          if (!userDoc.exists) throw new Error(`User ${uid} not found`);
          const userData = userDoc.data();
          
          let feeToDeductNGN = 0;
          
          const cardsIncluded = userData.cardsIncluded || 0;
          if (cardsIncluded > 0) {
            feeToDeductNGN = 0;
            t.update(userRef, { cardsIncluded: FieldValue.increment(-1) });
          } else {
            feeToDeductNGN = 700; // Hardcoded default for NGN cards in Bridgecard Logic
            const planTier = userData.planTier || "none";
            if (planTier === "none") {
               throw new Error("User has no active plan to create cards.");
            }
          }
          
          if (feeToDeductNGN > 0) {
            const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
            const walletDoc = await t.get(walletRef);
            if (!walletDoc.exists) throw new Error("Wallet not found.");
            
            const walletData = walletDoc.data() || {};
            const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
            const currentBalanceNgn = currentBalanceKobo / 100;

            if (currentBalanceNgn < feeToDeductNGN) {
              throw new Error(`Insufficient funds. Needed: ${feeToDeductNGN} NGN.`);
            }
            
            const feeToDeductKobo = Math.round(feeToDeductNGN * 100);
            t.update(walletRef, { 
              balance_kobo: FieldValue.increment(-feeToDeductKobo),
              cached_balance: FieldValue.increment(-feeToDeductNGN),
              balance: FieldValue.increment(-feeToDeductNGN) 
            });
            
            const transaction_reference = `gk_migration_fee_${cardId}_${Date.now()}`;
            const ledgerRef = db.collection("wallet_ledger").doc(transaction_reference);
            t.set(ledgerRef, {
              type: "debit",
              amount: feeToDeductNGN,
              status: "successful",
              context: "ngn_card_creation_migration",
              user_id: uid,
              card_id: cardId,
              created_at: Date.now()
            });
          }
        });
        
        // Fee is atomically deducted successfully, now issue Sudo card!
        const userDocRef = await db.collection("users").doc(uid).get();
        const freshUserData = userDocRef.data();
        
        const sudoRes = await createSudoCardInternal(uid, freshUserData, cardId);
        
        await db.collection("cards").doc(cardId).update({
          sudo_card_id: sudoRes.sudo_card_id,
          bridgecard_card_id: sudoRes.sudo_card_id, // Maintained for backwards UI compat
          bridgecard_currency: "NGN",
          bridgecard_status: "active",
          local_status: "active",
          status: "active",
          last4: sudoRes.last4,
          masked_number: sudoRes.masked_number,
          cvv: sudoRes.cvv,
          expiry: sudoRes.expiry
        });
        
        processed++;
      } catch (err) {
        logger.error(`[Sudo Migration] Error for card ${cardId} (UID: ${uid}):`, err.message);
        errors.push({ cardId, uid, error: err.message });
        failed++;
      }
    }
    
    return res.status(200).json({ success: true, processed, failed, errors });
    
  } catch (err) {
    logger.error("[Sudo Migration] Global error", err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = {
  sudoClient,
  ensureSudoCustomer,
  ensureSudoAccount,
  createSudoCardInternal,
  fundSudoCardInternal,
  sudoWebhook: exports.sudoWebhook,
  migratePendingSudoCards: exports.migratePendingSudoCards
};
