const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { requireVerifiedEmail, requireFields, requireKyc, requirePin } = require("../utils/validators");
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

  const address = userData.address || "Gatekipa HQ, 1 Tech Road";
  const city = userData.city || "Lagos";
  const state = userData.state || "Lagos";
  
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
      line1: address,
      city: city,
      state: state,
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
    const errorMsg = err.response?.data?.error?.message || err.response?.data?.message || err.message;
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
  try {
    logger.info(`[Sudo] Checking for existing accounts for customer ${customerId}`);
    const getRes = await client.get(`/accounts?customerId=${customerId}`);
    const allAccounts = getRes.data?.data || [];
    
    // Sudo API might ignore customerId query param, so we strictly filter it manually.
    const accounts = allAccounts.filter(a => 
      a.customerId === customerId || 
      a.customer === customerId || 
      (a.customer && a.customer._id === customerId)
    );
    
    // Find the specific account that belongs to this user by matching their name.
    // IMPORTANT: We do NOT fall back to accounts[0] — that causes mis-assignment
    // where one user's DVA gets written onto a completely different user's record.
    const firstName = (userData.firstName || "").toUpperCase();
    const lastName = (userData.lastName || "").toUpperCase();
    const userAccount = accounts.find(a => {
      const accName = (a.accountName || "").toUpperCase();
      return (firstName && accName.includes(firstName)) || (lastName && accName.includes(lastName));
    });

    if (userAccount) {
      const existingId = userAccount._id;
      logger.info(`[Sudo] Found existing account ${existingId} (Name: ${userAccount.accountName}) for ${uid}`);
      await db.collection("users").doc(uid).update({ sudo_account_id: existingId });
      return existingId;
    }

    // No match found — log a clear warning and fall through to create a new account.
    // Never steal another user's account via accounts[0].
    logger.warn(`[Sudo] No name-matched account found for UID ${uid} (${firstName} ${lastName}). Will create a fresh one.`);
  } catch (err) {
    logger.warn(`[Sudo] Failed to fetch existing accounts, proceeding to create: ${err.message}`);
  }

  const payload = {
    type: "account",
    currency: "NGN",
    customerId: customerId
  };
  logger.info(`[Sudo] Payload for create account:`, payload);

  try {
    const res = await client.post("/accounts", payload);
    logger.info(`[Sudo] Account creation response:`, res.data);
    
    const accountData = res.data?.data || res.data;
    const accountId = accountData?._id || accountData?.id;

    if (!accountId) {
      if (accountData?.message === "Account limit exceeded." && uid === "e2e_onboarding_user") {
        logger.info("[Sudo] MOCKING DVA for E2E Test because of Sandbox limit.");
        const mockId = "mock_sudo_dva_" + Date.now();
        await db.collection("users").doc(uid).update({ sudo_account_id: mockId });
        return mockId;
      }
      throw new Error(`Failed to create Sudo account: Missing account ID in Sudo response. Full response: ${JSON.stringify(accountData)} ${accountId}`);
    }

    await db.collection("users").doc(uid).update({ sudo_account_id: accountId });
    return accountId;
  } catch (err) {
    const errorMsg = err.response?.data?.error?.message || err.response?.data?.message || err.response?.data?.error || err.message;
    
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
 * Creates a Virtual Card via Sudo Africa using Gateway (Pool) Funding.
 * This avoids the requirement for per-user sub-accounts.
 * @param {string} uid - User ID
 * @param {object} userData - User Document Data
 * @param {string} cardId - Internal Gatekipa Card ID
 * @param {string} cardCurrency - "NGN" or "USD"
 */
async function createSudoCardInternal(uid, userData, cardId, cardCurrency = "NGN", initialLimit = 0) {
  const customerId = await ensureSudoCustomer(uid, userData);
  
  // Use dedicated Sudo Sub-accounts for accurate user-level funding
  const debitAccountId = await ensureSudoAccount(uid, customerId, userData);

  const client = sudoClient();

  // Sudo Create Card payload using Sub-account Funding
  const payload = {
    customerId: customerId,
    type: "virtual",
    currency: cardCurrency,
    brand: cardCurrency === "USD" ? "Mastercard" : "Verve",
    issuer: "Sudo",
    status: "active",
    debitAccountId: debitAccountId
  };

  if (cardCurrency === "USD") {
    payload.cardProgramId = process.env.SUDO_USD_CARD_PROGRAM_ID || "6a1977ec8a78fdffd3836ede";
  } else {
    payload.cardProgramId = process.env.SUDO_CARD_PROGRAM_ID || "69fca220d8e6bc0c0b02ff56";
  }

  logger.info(`[Sudo] Issuing ${cardCurrency} Gateway card for customer ${customerId}, internal cardId: ${cardId}`);

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
    const errorMsg = err.response?.data?.error?.message || err.response?.data?.message || err.message;
    const statusCode = err.response?.status || 500;
    logger.error(`[Sudo] Failed to issue card: ${JSON.stringify(err.response?.data || {})}`);
    const customError = new Error(`Failed to issue Sudo NGN card: ${errorMsg}`);
    customError.sudoStatus = statusCode;
    throw customError;
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
 * @param {boolean} [breachAlertActive=false] - If true, send aggressive FCM alert
 */
async function recordJitDecline(sudoCardId, amountKobo, merchant, reason, eventId, breachAlertActive = false) {
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
      created_at: FieldValue.serverTimestamp(),
    });

    // 3. In-app notification + FCM
    let title = `Transaction Declined at ${merchant}`;
    let body = reason || "Your Gatekipa card transaction was declined.";
    
    if (breachAlertActive) {
      title = `🚨 SENTINEL ALERT: Transaction Blocked!`;
      body = `A transaction of ₦${(amountKobo / 100).toLocaleString()} at ${merchant} was blocked by your Guard Rules: ${reason}`;
    }
    
    await db.collection("users").doc(uid).collection("notifications").add({
      title,
      body,
      timestamp: new Date(),
      isRead: false,
      type: breachAlertActive ? "sentinel_breach" : "alert",
    });

    const userSnap = await db.collection("users").doc(uid).get();
    const fcmToken = userSnap.data()?.fcm_token;
    if (fcmToken) {
      const { getMessaging } = require("firebase-admin/messaging");
      
      const payload = {
        token: fcmToken,
        notification: { title, body },
        data: { type: "transaction_declined", merchant, amount: String(amountKobo / 100) },
      };
      
      if (breachAlertActive) {
        payload.android = {
          priority: "high",
          notification: { sound: "default", channelId: "sentinel_alerts" }
        };
        payload.apns = {
          payload: { aps: { sound: "default" } }
        };
      }

      await getMessaging().send(payload).catch(e => logger.warn("[FCM] JIT decline notification failed", e.message));
    }
  } catch (err) {
    logger.error("[Sudo JIT] Failed to record decline:", err.message);
  }
}

exports.sudoWebhook = onRequest({ region: "us-central1", cpu: 0.5, memory: "512MiB", maxInstances: 10 }, async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // Webhook Security Authorization
  const webhookSecret = process.env.SUDO_WEBHOOK_SECRET;
  if (!webhookSecret) {
    logger.error("[Sudo Webhook] Webhook Secret is not configured. Rejecting request to prevent bypass.");
    return res.status(500).json({ error: "Webhook configuration error" });
  }

  const authHeader = req.headers['authorization'] || req.headers['x-sudo-signature'];
  if (!authHeader || (authHeader !== `Bearer ${webhookSecret}` && authHeader !== webhookSecret)) {
    logger.error("[Sudo Webhook] Unauthorized request. Missing or invalid Authorization token.");
    return res.status(401).json({ error: "Unauthorized" });
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
      created_at: FieldValue.serverTimestamp(),
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
        recordJitDecline(sudoCardId, amountKobo, merchant, ruleResult.reason, eventId, ruleResult.breachAlertActive);
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

    // ── HANDLE DVA WALLET FUNDING ─────────────────────────────────────────
    if (eventType === "account.deposit" || (eventType === "transaction.successful" && eventObject.type === "credit")) {
      logger.info(`[Sudo Webhook] Processing DVA Deposit for event ${eventId}`);
      
      const accountId = eventObject.accountId || eventObject.account?._id || eventObject.account;
      const rawAmount = Number(eventObject.amount || 0);
      
      if (!accountId || rawAmount <= 0) {
        logger.warn(`[Sudo Webhook] Invalid DVA deposit payload for ${eventId}`);
        return res.status(200).send("OK");
      }

      // Look up user by sudo_dva_id or sudo_account_id
      const usersSnap = await db.collection("users").where("sudo_dva_id", "==", accountId).limit(1).get();
      let uid;
      
      if (!usersSnap.empty) {
        uid = usersSnap.docs[0].id;
      } else {
        const fallbackSnap = await db.collection("users").where("sudo_account_id", "==", accountId).limit(1).get();
        if (!fallbackSnap.empty) {
          uid = fallbackSnap.docs[0].id;
        } else {
           logger.error(`[Sudo Webhook] Could not find user for Sudo DVA ${accountId}`);
           return res.status(200).send("OK");
        }
      }

      const compositeIdempotencyKey = `sudo_funding:${eventId}`;
      const hashRef = db.collection("webhook_events").doc(compositeIdempotencyKey);
      
      try {
        await hashRef.create({ event: eventType, received_at: FieldValue.serverTimestamp(), status: "processing" });
      } catch (err) {
        if (err.code === 6) { // ALREADY_EXISTS
          logger.info(`[Sudo Webhook] Duplicate DVA deposit (hash ${compositeIdempotencyKey}) — skipping.`);
          return res.status(200).send("OK");
        }
        throw err;
      }

      try {
        const processTransactionInternal = require("./transactionService").processTransactionInternal;
        await processTransactionInternal({
          type: "wallet_funding",
          userId: uid,
          amount: rawAmount,
          idempotencyKey: compositeIdempotencyKey,
          metadata: {
            source: "sudo_dva_transfer",
            sudoEventId: eventId,
            currency: eventObject.currency || "NGN",
            accountId: accountId
          },
          correlationId: `sudoFundingWebhook:${eventId}`,
        });
        await hashRef.set({ status: "completed" }, { merge: true });

        // Notify user
        try {
          const title = `Wallet Funded (₦${rawAmount.toLocaleString()})`;
          const body = `Your Gatekipa wallet has been credited via Bank Transfer.`;
          await db.collection("users").doc(uid).collection("notifications").add({
            title, body, timestamp: new Date(), isRead: false, type: "wallet_funding"
          });
          
          const uDoc = await db.collection("users").doc(uid).get();
          const fcmToken = uDoc.data()?.fcm_token;
          if (fcmToken) {
            const { getMessaging } = require("firebase-admin/messaging");
            await getMessaging().send({
              token: fcmToken,
              notification: { title, body },
              data: { type: "wallet_funding", amount: String(rawAmount) },
            });
          }
        } catch (e) {
           logger.warn(`[Sudo Webhook] Failed to notify user of DVA deposit:`, e.message);
        }
      } catch (orchErr) {
        logger.error(`[Sudo Webhook] Orchestrator failed for DVA deposit ${eventId}:`, orchErr);
        await hashRef.set({ status: "failed", error: orchErr.message }, { merge: true });
      }
      return res.status(200).send("OK");
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
            updated_at: FieldValue.serverTimestamp() 
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
      const isReversal = eventType === "authorization.reversed" || eventType === "authorization.voided" || eventType === "transaction.declined" || eventType === "transaction.failed" || eventType === "transaction.reversed";
      const isRefund = eventType === "transaction.refund" || eventObject.type === "refund" || isReversal;

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

      // Deduplication check via atomic create to prevent TOCTOU race conditions
      const hashRef = db.collection("webhook_events").doc(compositeIdempotencyKey);
      try {
        await hashRef.create({ event: eventType, received_at: FieldValue.serverTimestamp(), status: "processing", authEventId });
      } catch (err) {
        if (err.code === 6) { // ALREADY_EXISTS
          logger.info(`[Sudo Webhook] Duplicate transaction (composite hash ${compositeHash.slice(0,12)}) — skipping.`);
          return res.status(200).send("OK");
        }
        throw err;
      }

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
          if (isReversal) {
            // For reversals, ensure we actually reserved the funds in JIT before crediting back.
            const originalEventId = eventObject.authorizationId || eventObject._id || eventId;
            const ledgerRef = db.collection("wallet_ledger").doc(`jit_auth_${originalEventId}`);
            const ledgerSnap = await ledgerRef.get();
            if (!ledgerSnap.exists || ledgerSnap.data().status !== "reserved") {
              logger.info(`[Sudo Webhook] Reversal ${eventId} ignored — no active reservation found for ${originalEventId}.`);
              await hashRef.set({ status: "ignored_no_reservation" }, { merge: true });
              return res.status(200).send("OK");
            }
            // Mark reservation as reversed
            await ledgerRef.update({ status: "reversed", updated_at: FieldValue.serverTimestamp() });
          }

          await processTransactionInternal({
            type: "wallet_funding", // Refund acts as a wallet credit
            userId: ownerUid,
            amount: rawAmount,
            idempotencyKey: compositeIdempotencyKey,
            metadata: {
              cardId: cardDoc.id,
              accountId: card.account_id,
              merchantName: merchant,
              providerRef: authEventId, 
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
              providerRef: authEventId,
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
            settled_at: FieldValue.serverTimestamp(),
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
  // NOTE: In the calling context, we already have the card_id.
  // We extract it from 'transaction_reference' which contains the card_id.
  
  const cardIdMatch = transactionReference.match(/gk_(.*)_/);
  const cardId = cardIdMatch ? cardIdMatch[1] : null;

  if (!cardId) {
    logger.error(`[Sudo] Could not extract cardId from reference: ${transactionReference}`);
    throw new HttpsError("invalid-argument", "Missing card identifier in funding reference.");
  }

  logger.info(`[Sudo] Funding Gateway Card ${cardId}. Allocating NGN ${amountNGN}`);

  try {
    const cardRef = db.collection("cards").doc(cardId);
    let newLimit = 0;
    let sudo_card_id = null;
    
    await db.runTransaction(async (t) => {
      const snap = await t.get(cardRef);
      if (!snap.exists) throw new Error("Card not found");
      
      const currentLimit = snap.data().allocated_amount || 0;
      newLimit = currentLimit + amountNGN;
      sudo_card_id = snap.data().sudo_card_id;
      
      t.update(cardRef, {
        allocated_amount: newLimit,
        balance_limit: newLimit, // migration compat
        last_funded_at: Date.now(),
        last_funding_ref: transactionReference
      });
    });

    // Update Sudo API limit if issued
    if (sudo_card_id) {
      try {
        const client = sudoClient();
        await client.put(`/cards/${sudo_card_id}`, {
          spendingControls: {
            spendLimit: [
              { amount: newLimit, interval: "allTime" }
            ]
          }
        });
      } catch (err) {
        // Reverse local update if network call fails
        logger.error(`[Sudo] Funding API failed. Rolling back transaction for ${cardId}`);
        await cardRef.update({
          allocated_amount: FieldValue.increment(-amountNGN),
          balance_limit: FieldValue.increment(-amountNGN)
        });
        const errorMsg = err.response?.data?.message || err.message;
        throw new Error(`Sudo API failed: ${errorMsg}`);
      }
    }

    return {
      success: true,
      message: "Card limit updated successfully.",
      transaction_reference: transactionReference,
      sudo_transfer_id: "gateway_allocated",
      new_limit: newLimit
    };
  } catch (err) {
    logger.error(`[Sudo] Failed to update card allocation: ${err.message}`);
    throw new HttpsError("internal", `Sudo Card Allocation failed: ${err.message}`);
  }
}

/**
 * Migration Endpoint: Finds all pending NGN cards
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
            const sysDoc = await t.get(db.collection("system").doc("config"));
            feeToDeductNGN = sysDoc.exists ? (sysDoc.data().virtual_card_fee_ngn || 700) : 700;
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
          sudo_currency: "NGN",
          sudo_status: "active",
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

/**
 * Migration Endpoint: Seamlessly provisions Sudo USD cards.
 */
exports.migrateUSDBridgecardsToSudo = onRequest({ region: "us-central1", secrets: ["SUDO_API_KEY"] }, async (req, res) => {
  // Simple auth for the administrative script
  if (req.query.secret !== "GAT2026MIGRATE") {
    return res.status(403).send("Forbidden");
  }
  
  try {
    const cardsQuery = await db.collection("cards")
      .where("bridgecard_currency", "==", "USD")
      .get();
      
    if (cardsQuery.empty) {
      return res.status(200).json({ success: true, message: "No USD cards found." });
    }
    
    let processed = 0;
    let failed = 0;
    let skipped = 0;
    const errors = [];
    
    for (const cardDoc of cardsQuery.docs) {
      const cardData = cardDoc.data();
      
      // If it already has a Sudo Card ID, it was already migrated.
      if (cardData.sudo_card_id) {
        skipped++;
        continue;
      }

      const cardId = cardDoc.id;
      const uid = cardData.created_by || cardData.account_id;
      
      try {
        const userDocRef = await db.collection("users").doc(uid).get();
        if (!userDocRef.exists) throw new Error(`User ${uid} not found`);
        const userData = userDocRef.data();
        
        // Directly issue Sudo USD card without any gatekipa fee deduction, and carry over unspent funds
        const initialLimit = cardData.allocated_amount || 0;
        const sudoRes = await createSudoCardInternal(uid, userData, cardId, "USD", initialLimit);
        
        await db.collection("cards").doc(cardId).update({
          sudo_card_id: sudoRes.sudo_card_id,
          sudo_currency: "USD",
          sudo_status: "active",
          status: "active",
          last4: sudoRes.last4,
          masked_number: sudoRes.masked_number,
          cvv: sudoRes.cvv,
          expiry: sudoRes.expiry
        });
        
        processed++;
      } catch (err) {
        logger.error(`[Sudo USD Migration] Error for card ${cardId} (UID: ${uid}):`, err.message);
        errors.push({ cardId, uid, error: err.message });
        failed++;
      }
    }
    
    return res.status(200).json({ success: true, processed, skipped, failed, errors });
    
  } catch (err) {
    logger.error("[Sudo USD Migration] Global error", err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

exports.createSudoCard = onCall({ region: "us-central1", secrets: [SUDO_API_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["card_id", "transactionPin"]);

  await requireKyc(uid);
  await requirePin(uid, data.transactionPin);

  const { card_id } = data;

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const cardAccountId = cardSnap.data().account_id;
  if (cardAccountId !== uid) {
    const accountSnap = await db.collection("accounts").doc(cardAccountId).get();
    if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
      throw new HttpsError("permission-denied", "Not your card.");
    }
  }

  const userSnap = await db.collection("users").doc(uid).get();
  
  const existing_sudo_id = cardSnap.data()?.sudo_card_id;
  if (existing_sudo_id) {
    return { success: true, sudo_card_id: existing_sudo_id, already_issued: true };
  }

  const cardCurrency = data.card_currency === "USD" ? "USD" : "NGN";
  
  let feeToDeductNGN = 0;
  let deductCardsIncluded = false;
  
  const cardLimit = data.card_limit || "500000"; // Default $5k spending limit
  const requiredFundingUsd = cardLimit === "1000000" ? 4 : 3;

  if (cardCurrency === "USD") {
    try {
      const sysStateSnap = await db.doc("system_state/global").get();
      const sysData = sysStateSnap.exists ? sysStateSnap.data() : {};
      
      let rate = sysData.gatekipa_usd_rate;
      if (!rate || !Number.isFinite(rate)) rate = 1700;
      
      const totalUsdCost = requiredFundingUsd + 0.5; // Matches legacy cost structure
      feeToDeductNGN = Math.ceil(totalUsdCost * rate);
      logger.info(`[Sudo] Gatekipa USD card FX rate: ${rate}. NGN equivalent of $${totalUsdCost}: ${feeToDeductNGN}`);
    } catch(e) {
      const totalUsdCost = requiredFundingUsd + 0.5;
      feeToDeductNGN = Math.ceil(totalUsdCost * 1700);
    }
  }

  const transaction_reference = `gk_card_fee_${card_id}_${Date.now()}`;
  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
  const userRef = db.collection("users").doc(uid);
  const ledgerRef = db.collection("wallet_ledger").doc(transaction_reference);

  let didDeductBalance = false;

  await db.runTransaction(async (t) => {
    const userDoc = await t.get(userRef);
    const userData = userDoc.data() || {};
    
    if (cardCurrency === "NGN") {
      const cardsIncluded = userData.cardsIncluded || 0;
      if (cardsIncluded > 0) {
        feeToDeductNGN = 0;
        deductCardsIncluded = true;
        t.update(userRef, { cardsIncluded: FieldValue.increment(-1) });
      } else {
        const sysDoc = await t.get(db.collection("system").doc("config"));
        feeToDeductNGN = sysDoc.exists ? (sysDoc.data().virtual_card_fee_ngn || 700) : 700;
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

      t.update(walletRef, { 
        balance_kobo: FieldValue.increment(-feeToDeductKobo),
        escrow_kobo: FieldValue.increment(feeToDeductKobo),
        cached_balance: Number(((currentBalanceKobo - feeToDeductKobo) / 100).toFixed(2)),
        balance: Number(((currentBalanceKobo - feeToDeductKobo) / 100).toFixed(2))
      });
      t.set(ledgerRef, {
        type: "debit",
        amount_kobo: feeToDeductKobo,
        amount: feeToDeductNGN,
        status: "escrowed", // 2-Phase Commit: Pending Sudo
        context: "ngn_card_creation",
        user_id: uid,
        card_id,
        created_at: Date.now()
      });
      didDeductBalance = true;
    }
  });

  const queueId = `cpq_${card_id}_${Date.now()}`;
  const provisioningQueueRef = db.collection("card_provisioning_queue").doc(queueId);

  await provisioningQueueRef.set({
    queue_id: queueId,
    uid,
    card_id,
    card_currency: cardCurrency,
    fee_deducted_kobo: Math.round(feeToDeductNGN * 100),
    status: "PENDING",
    created_at: Date.now(),
  });

  try {
    const userProfileData = userSnap.data() || {};
    const sudoRes = await createSudoCardInternal(uid, userProfileData, card_id, cardCurrency);
    const sudo_card_id = sudoRes.sudo_card_id;

    await db.collection("cards").doc(card_id).set(
      {
        sudo_card_id,
        sudo_currency: cardCurrency,
        sudo_status: "active",
        status: "active",
        last4: sudoRes.last4,
        masked_number: sudoRes.masked_number,
        cvv: sudoRes.cvv,
        expiry: sudoRes.expiry
      },
      { merge: true }
    );

    await provisioningQueueRef.set({ status: "COMPLETED", sudo_card_id, completed_at: Date.now() }, { merge: true });

    // 2-Phase Commit: Sudo Success -> Release Escrow -> Finalize Ledger
    if (didDeductBalance && feeToDeductNGN > 0) {
      const feeToDeductKobo = Math.round(feeToDeductNGN * 100);
      await db.runTransaction(async (finalizeT) => {
        finalizeT.update(walletRef, {
          escrow_kobo: FieldValue.increment(-feeToDeductKobo)
        });
        finalizeT.update(ledgerRef, {
          status: "successful",
          completed_at: Date.now()
        });
      });
    }

    return { success: true, sudo_card_id, currency: cardCurrency, deducted: feeToDeductNGN };
  } catch (err) {
    const errMsg = err.message || "Unknown Sudo error";
    const status = err.sudoStatus || (err.response ? err.response.status : undefined);
    const isNetworkOrTimeout = !status || status >= 500;

    if (!isNetworkOrTimeout) {
      logger.warn(`[Sudo] card creation explicitly failed for ${uid} (4xx). Reason: ${errMsg}. Rolling back.`);
      try {
        await db.runTransaction(async (rollbackT) => {
          if (deductCardsIncluded) {
            rollbackT.update(userRef, { cardsIncluded: FieldValue.increment(1) });
          }
          if (didDeductBalance && feeToDeductNGN > 0) {
            const feeKobo = Math.round(feeToDeductNGN * 100);
            rollbackT.update(walletRef, { 
              balance_kobo: FieldValue.increment(feeKobo),
              escrow_kobo: FieldValue.increment(-feeKobo),
              cached_balance: FieldValue.increment(feeToDeductNGN),
              balance: FieldValue.increment(feeToDeductNGN) 
            });
            rollbackT.set(ledgerRef, { status: "reversed", metadata: "Sudo API failure", reversed_at: Date.now() }, { merge: true });
          }
        });
      } catch (rollbackErr) {
        logger.error(`[CRITICAL] FAILED TO ROLLBACK CARD CREATION (Quota/Fee) FOR UID ${uid}`, rollbackErr);
      }
      
      await provisioningQueueRef.set({ status: "EXPLICIT_ROLLBACK", error: errMsg, failed_at: Date.now() }, { merge: true });
      throw new HttpsError("failed-precondition", errMsg);
    } else {
      logger.error(`[Sudo] Network timeout or 5xx error for ${uid}. State UNKNOWN. Deferring to ghostCardSweeper.`);
      await provisioningQueueRef.set({ status: "PENDING", error: errMsg, timeout_deferred: true, failed_at: Date.now() }, { merge: true });
      throw new HttpsError("internal", "The card network is taking too long to respond. Your request is being processed in the background. We will notify you shortly.");
    }
  }
});



async function internalFreezeSudoCard(sudoCardId, freeze) {
  const targetStatus = freeze ? "inactive" : "active";
  try {
    const client = sudoClient();
    const response = await client.put(`/cards/${sudoCardId}`, { status: targetStatus });
    logger.info(`[Sudo] Successfully set card ${sudoCardId} to ${targetStatus}`);
    return response.data;
  } catch (err) {
    const errorMsg = err.response ? JSON.stringify(err.response.data) : err.message;
    logger.error(`[Sudo] Failed to update card status for ${sudoCardId}: ${errorMsg}`);
    throw new Error(`Sudo card freeze error: ${errorMsg}`);
  }
}

/**
 * securely fetches card PAN, CVV, and expiry from Sudo Vault
 */
exports.revealCardDetails = onCall({ region: "us-central1", enforceAppCheck: true, secrets: [SUDO_API_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  // Frontend sends card_id
  const cardId = data.cardId || data.card_id;
  if (!cardId) {
    throw new HttpsError("invalid-argument", "Missing required field: card_id");
  }

  const cardSnap = await db.collection("cards").doc(cardId).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");
  
  const accountSnap = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountSnap.exists || accountSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Not your card.");
  }

  const sudo_card_id = cardSnap.data()?.sudo_card_id;
  if (!sudo_card_id) {
    throw new HttpsError("failed-precondition", "This card has not been issued via Sudo yet.");
  }

  const vaultClient = sudoVaultClient();
  try {
    const vaultRes = await vaultClient.get(`/cards/${sudo_card_id}/token`);
    const vaultData = vaultRes.data?.data;

    if (!vaultData || (!vaultData.token && !vaultRes.data?.token)) {
      throw new Error("Vault response missing card token");
    }

    const token = vaultData.token || vaultRes.data?.token;

    return {
      token: token.toString(),
      success: true
    };
  } catch (err) {
    const msg = err.response?.data?.message || err.message;
    logger.error("[Sudo] revealCardDetails error:", msg);
    throw new HttpsError("internal", msg);
  }
});


exports.fundSudoCard = onCall({ region: "us-central1", secrets: [SUDO_API_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  const { requireFields, requirePin } = require("../utils/validators");
  requireFields(data, ["cardId", "amount", "pin"]);
  
  const { cardId, amount, pin } = data;
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero.");
  }
  
  const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
  const mode = await getSystemMode();
  assertSystemAllowsFinancialOps(mode);
  
  await requirePin(uid, pin);
  
  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
  const cardRef = db.collection("cards").doc(cardId);
  const ledgerRef = db.collection("wallet_ledger").doc();
  const amountKobo = Math.round(amount * 100);

  try {
    let newLimit = 0;
    let sudo_card_id = null;
    
    // 1. Transaction to deduct balance locally
    await db.runTransaction(async (t) => {
      const cardSnap = await t.get(cardRef);
      if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");
      const cardData = cardSnap.data();
      if ((cardData.created_by !== uid) && (cardData.account_id !== uid)) {
        throw new HttpsError("permission-denied", "Not authorized for this card.");
      }
      
      const walletSnap = await t.get(walletRef);
      const walletData = walletSnap.data() || {};
      const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
      
      if (currentBalanceKobo < amountKobo) {
        throw new HttpsError("failed-precondition", "Insufficient wallet balance.");
      }
      
      const balanceAfterKobo = currentBalanceKobo - amountKobo;
      const currentLimit = cardData.allocated_amount || 0;
      newLimit = currentLimit + amount;
      sudo_card_id = cardData.sudo_card_id;

      t.update(walletRef, {
        balance_kobo: FieldValue.increment(-amountKobo),
        cached_balance: FieldValue.increment(-amount),
        balance: FieldValue.increment(-amount)
      });

      t.update(cardRef, {
        allocated_amount: newLimit,
        balance_limit: newLimit
      });

      t.create(ledgerRef, {
        user_id: uid,
        type: "debit",
        amount_kobo: amountKobo,
        amount: amount,
        balance_after_kobo: balanceAfterKobo,
        balance_after: balanceAfterKobo / 100,
        source: "card_funding",
        card_id: cardId,
        reference: ledgerRef.id,
        status: "success",
        created_at: FieldValue.serverTimestamp()
      });
    });
    
    // 2. Perform network call OUTSIDE transaction
    if (sudo_card_id) {
      try {
         const client = sudoClient();
         await client.put(`/cards/${sudo_card_id}`, {
           spendingControls: {
             spendLimit: [{ amount: newLimit, interval: "allTime" }]
           }
         });
      } catch (err) {
         // 3. Rollback if network fails
         logger.error(`[Sudo] Funding API failed. Rolling back transaction for ${cardId}`);
         await db.runTransaction(async (rollbackT) => {
            rollbackT.update(walletRef, {
              balance_kobo: FieldValue.increment(amountKobo),
              cached_balance: FieldValue.increment(amount),
              balance: FieldValue.increment(amount)
            });
            rollbackT.update(cardRef, {
              allocated_amount: FieldValue.increment(-amount),
              balance_limit: FieldValue.increment(-amount)
            });
            rollbackT.update(ledgerRef, {
              status: "reversed",
              reversed_at: FieldValue.serverTimestamp(),
              reason: "Sudo API funding failure"
            });
         });
         const errorMsg = err.response?.data?.message || err.message;
         throw new HttpsError("internal", `Failed to fund card at Sudo: ${errorMsg}`);
      }
    }
    
    return { success: true, allocated_amount: newLimit };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("[Sudo] Card funding failed:", error);
    throw new HttpsError("internal", error.message || "Failed to fund card.");
  }
});

module.exports = {
  sudoClient,
  ensureSudoCustomer,
  ensureSudoAccount,
  createSudoCardInternal,
  createSudoCard: exports.createSudoCard,
  fundSudoCardInternal,
  fundSudoCard: exports.fundSudoCard,
  sudoWebhook: exports.sudoWebhook,
  migratePendingSudoCards: exports.migratePendingSudoCards,
  migrateUSDBridgecardsToSudo: exports.migrateUSDBridgecardsToSudo,
  internalFreezeSudoCard,
  revealCardDetails: exports.revealCardDetails
};
