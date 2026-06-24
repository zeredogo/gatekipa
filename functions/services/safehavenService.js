const { db } = require("../utils/firebase");
const { HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");
const forge = require("node-forge");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const SAFEHAVEN_CLIENT_ID = defineSecret("SAFEHAVEN_CLIENT_ID");
const SAFEHAVEN_PRIVATE_KEY = defineSecret("SAFEHAVEN_PRIVATE_KEY");

// Use sandbox or production URL
const BASE_URL = process.env.SAFEHAVEN_BASE_URL || "https://api.safehavenmfb.com"; 

/**
 * Generates an OAuth2 Access Token for SafeHaven using the Client Credentials + JWT Assertion flow.
 */
async function getSafeHavenToken() {
  let clientId = SAFEHAVEN_CLIENT_ID.value().trim();
  let privateKey = SAFEHAVEN_PRIVATE_KEY.value().replace(/\\n/g, '\n');

  if (!clientId || !privateKey) {
    throw new Error("SafeHaven credentials not configured in Secret Manager.");
  }

  // Attempt to normalize the key if it was pasted as a single line without newlines
  if (!privateKey.includes('\n') && privateKey.includes('-----BEGIN')) {
    const headerMatch = privateKey.match(/-----BEGIN.*?-----/);
    const footerMatch = privateKey.match(/-----END.*?-----/);
    if (headerMatch && footerMatch) {
      const header = headerMatch[0];
      const footer = footerMatch[0];
      let body = privateKey.replace(header, '').replace(footer, '').replace(/\s+/g, '');
      const chunks = body.match(/.{1,64}/g) || [];
      privateKey = `${header}\n${chunks.join('\n')}\n${footer}`;
    }
  }

  // Generate the JWT Client Assertion using Node.js crypto with explicit PKCS1 padding
  function base64url(buf) {
    return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  const header = { alg: "RS256", typ: "JWT" };
  const payloadData = {
    iss: "https://gatekipa.com",   // Company URL - required by SafeHaven docs
    sub: clientId,                  // OAuth Client ID
    aud: BASE_URL,                  // Base URL only, NOT /oauth2/token - confirmed by local testing
    jti: crypto.randomUUID(),
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 300 // 5m
  };

  const encodedHeader = base64url(Buffer.from(JSON.stringify(header)));
  const encodedPayload = base64url(Buffer.from(JSON.stringify(payloadData)));
  const signInput = `${encodedHeader}.${encodedPayload}`;

  let clientAssertion;
  try {
    // Use Node.js crypto.createSign - it supports 1024-bit keys when called directly
    const signer = crypto.createSign('RSA-SHA256');
    signer.update(signInput);
    signer.end();
    const signatureBuffer = signer.sign({
      key: privateKey,
      padding: crypto.constants.RSA_PKCS1_PADDING
    });
    clientAssertion = `${signInput}.${base64url(signatureBuffer)}`;
  } catch (err) {
    logger.error(`[SafeHaven] crypto.createSign failed (${err.message}), falling back to node-forge...`);
    // Fallback: use node-forge which bypasses OpenSSL min-key enforcement
    try {
      const pki = forge.pki;
      const privateKeyObj = pki.privateKeyFromPem(privateKey);
      const md = forge.md.sha256.create();
      md.update(signInput, 'utf8');
      const sigBytes = privateKeyObj.sign(md);
      // Convert forge binary string to Buffer correctly
      const sigBuf = Buffer.from(sigBytes, 'binary');
      clientAssertion = `${signInput}.${base64url(sigBuf)}`;
    } catch (forgeErr) {
      throw new Error(`Failed to sign JWT: ${forgeErr.message}`);
    }
  }

  const payload = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: clientId,
    client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion: clientAssertion,
  });

  try {
    logger.info(`[SafeHaven] Requesting token from ${BASE_URL}/oauth2/token with clientId=${clientId}`);
    const res = await axios.post(`${BASE_URL}/oauth2/token`, payload.toString(), {
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
        "ClientID": clientId
      }
    });
    
    logger.info(`[SafeHaven] Token obtained successfully. Response keys: ${Object.keys(res.data).join(', ')}`);
    logger.info(`[SafeHaven] Full token response: ${JSON.stringify(res.data)}`);
    
    if (res.data.error || !res.data.access_token) {
      throw new Error(`Failed to obtain SafeHaven Token: ${res.data.error_description || res.data.error || 'Missing access_token'}`);
    }

    return {
      access_token: res.data.access_token,
      ibs_client_id: res.data.ibs_client_id || res.data.clientId || res.data.client_id || res.data.ibsClientId
    };
  } catch (err) {
    const errorData = err.response?.data;
    logger.error("[SafeHaven] Failed to generate access token. Status:", err.response?.status, "Body:", JSON.stringify(errorData));
    throw new Error(`Failed to authenticate with SafeHaven MFB: ${JSON.stringify(errorData) || err.message}`);
  }
}

/**
 * Step 1: Initiates SafeHaven Identity Verification.
 * This triggers an OTP to the user's phone number registered with their BVN.
 */
async function initiateSafeHavenVerification(uid, userData) {
  const { access_token, ibs_client_id } = await getSafeHavenToken();
  const idNumber = userData.bvn || userData.kycMeta?.idNumber || "";
  const idType = userData.bvn ? "BVN" : "NIN";

  if (!idNumber) {
    throw new HttpsError(
      "failed-precondition", 
      "BVN or NIN is required to generate a SafeHaven account. Please complete your KYC verification."
    );
  }

  const payload = {
    type: idType,
    number: idNumber,
    debitAccountNumber: "0115459874",  // Westgate Stratagem master account - pays the ₦50 KYC fee
    async: true
  };

  try {
    logger.info(`[SafeHaven] Initiating verification for UID ${uid}. idType=${idType}, ibs_client_id=${ibs_client_id}`);
    
    const res = await axios.post(`${BASE_URL}/identity/v2`, payload, {
      headers: {
        "Authorization": `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "ClientID": SAFEHAVEN_CLIENT_ID.value()
      }
    });

    const identityId = res.data.data._id;
    return { success: true, identityId: identityId };

  } catch (err) {
    const errorBody = err.response?.data;
    const errorStatus = err.response?.status;
    logger.error(`[SafeHaven] Verification Initiation Failed for ${uid}. Status: ${errorStatus}. Body:`, JSON.stringify(errorBody));
    throw new HttpsError("internal", errorBody?.message || `Failed to initiate SafeHaven Verification. Status: ${errorStatus}`);
  }
}

/**
 * Validates the Identity Verification OTP and saves the identity ID to the user's profile.
 * This marks the user as KYC verified via SafeHaven.
 */
async function validateSafeHavenIdentity(uid, identityId, otp, idType = "NIN") {
  if (otp === "000000" && (process.env.FUNCTIONS_EMULATOR === "true" || process.env.USE_LOCAL === "true")) {
    logger.info(`[SafeHaven MOCK] Bypassing OTP validation for test OTP.`);
    await db.collection("users").doc(uid).update({
      kycStatus: "verified",
      safehaven_identity_id: identityId,
      kycVerifiedAt: FieldValue.serverTimestamp()
    });
    return { success: true };
  }

  const { access_token, ibs_client_id } = await getSafeHavenToken();

  try {
    // Per SafeHaven docs: identityId, type, otp, and ibs_client_id are all required
    const validatePayload = {
      identityId: identityId,
      type: idType,
      otp: otp,
      ibs_client_id: ibs_client_id
    };
    
    logger.info(`[SafeHaven] Validating OTP for UID ${uid}. Payload:`, JSON.stringify(validatePayload));

    await axios.post(`${BASE_URL}/identity/v2/validate`, validatePayload, {
      headers: {
        "Authorization": `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "ClientID": SAFEHAVEN_CLIENT_ID.value()
      }
    });
    
    logger.info(`[SafeHaven] OTP Validated for UID ${uid}`);
    
    // Save to user profile — identityId now confirmed as validated
    await db.collection("users").doc(uid).update({
      kycStatus: "verified",
      safehaven_identity_id: identityId,
      kycVerifiedAt: FieldValue.serverTimestamp()
    });

    return { success: true };
  } catch (err) {
    const errorBody = err.response?.data;
    const errorStatus = err.response?.status;
    logger.error(`[SafeHaven] OTP Validation Failed for ${uid}. Status: ${errorStatus}. Body:`, JSON.stringify(errorBody));
    throw new HttpsError("invalid-argument", errorBody?.message || "Invalid OTP or Verification Failed.");
  }
}

/**
 * Step 2: Creates a SafeHaven Dedicated Virtual Account (Sub-Account) for a user
 * using the captured identityId from KYC.
 */
async function generateSafeHavenDva(uid, userData, identityId, otp) {
  const { access_token, ibs_client_id } = await getSafeHavenToken();

  const firstName = userData.firstName || userData.first_name || "Gatekipa";
  const lastName = userData.lastName || userData.last_name || "User";
  let phone = userData.phoneNumber || userData.phone || "";
  
  if (phone && !phone.startsWith('+')) {
    phone = phone.startsWith('0') ? `+234${phone.substring(1)}` : `+234${phone}`;
  }

  const email = userData.email || "support@gatekipa.com";
  const idNumber = userData.bvn || userData.kycMeta?.idNumber || "";
  const idType = userData.bvn ? "BVN" : "NIN";

  if (!idNumber || !identityId) {
    throw new HttpsError(
      "failed-precondition", 
      "BVN/NIN and Identity ID are required to generate the account. Please complete your KYC verification."
    );
  }

  // Per SafeHaven docs: sub-account creation takes the otp directly.
  const payload = {
    phoneNumber: phone,
    emailAddress: email,
    firstName: firstName,
    lastName: lastName,
    externalReference: `gatekipa_${uid}_${Date.now()}`,
    identityType: idType,
    identityNumber: idNumber,
    identityId: identityId,
    otp: otp,
    autoSweep: false
  };

  try {
    logger.info(`[SafeHaven] Creating DVA for UID ${uid}. Payload:`, JSON.stringify(payload));
    
    const res = await axios.post(`${BASE_URL}/accounts/v2/subaccount`, payload, {
      headers: {
        "Authorization": `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "ClientID": SAFEHAVEN_CLIENT_ID.value()
      }
    });

    const accountData = res.data.data;
    const nuban = accountData.accountNumber;
    const bankName = "SafeHaven Microfinance Bank";
    const accountName = accountData.accountName || `${firstName} ${lastName}`;

    const updateObj = {
      safehaven_subaccount_id: accountData._id,
      vaultNuban: nuban,
      vaultBankName: bankName,
      vaultAccountName: accountName,
      safehaven_dva_account_number: nuban,
      safehaven_identity_id: identityId,
      kycStatus: "verified",
      kycVerifiedAt: FieldValue.serverTimestamp()
    };

    await db.collection("users").doc(uid).update(updateObj);

    return { success: true, nuban, bankName, accountName };

  } catch (err) {
    const errorBody = err.response?.data;
    const errorStatus = err.response?.status;
    logger.error(`[SafeHaven] DVA Creation Failed for ${uid}. Status: ${errorStatus}. Body:`, JSON.stringify(errorBody));
    throw new HttpsError("internal", errorBody?.message || `Failed to generate SafeHaven Vault Account. Status: ${errorStatus}`);
  }
}

/**
 * Webhook listener for SafeHaven events (Inward Transfers).
 * This endpoint processes incoming deposits and credits the corresponding Gatekipa user's wallet.
 */
const safehavenWebhook = onRequest({ region: "us-central1" }, async (req, res) => {
  // SafeHaven requires webhooks to return a quick 200 OK
  res.status(200).send("OK");

  try {
    const payload = req.body;
    logger.info("[SafeHaven Webhook] Received payload:", JSON.stringify(payload));

    // Handle inbound fund transfers
    if (payload.type === "AccountTransfer" || payload.type === "InwardFundTransfer" || (payload.data && payload.data.amount)) {
      const data = payload.data || payload;
      const amount = parseFloat(data.amount);
      const accountNumber = data.accountNumber || data.creditAccountNumber;
      const sessionId = data.sessionId || data.reference || data.transactionReference;

      if (!accountNumber || !amount || amount <= 0) {
        logger.warn("[SafeHaven Webhook] Missing amount or account number", data);
        return;
      }

      // 1. Find the user who owns this SafeHaven Sub-Account
      const usersRef = db.collection("users");
      const userQuery = await usersRef.where("vaultNuban", "==", accountNumber).limit(1).get();

      if (userQuery.empty) {
        logger.warn(`[SafeHaven Webhook] No user found for account number: ${accountNumber}`);
        return;
      }

      const userDoc = userQuery.docs[0];
      const uid = userDoc.id;

      // 2. We use atomic transaction create() on txRef below to prevent duplicates.
      const txRef = db.collection("wallet_ledger").doc(sessionId);

      // 3. Atomically credit the wallet
      const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
      const amountKobo = Math.round(amount * 100);

      try {
        await db.runTransaction(async (t) => {
          const wDoc = await t.get(walletRef);
          const wData = wDoc.data() || {};
          const currentBalanceKobo = wData.balance_kobo ?? Math.round((wData.cached_balance ?? wData.balance ?? 0) * 100);
          const balanceAfterKobo = currentBalanceKobo + amountKobo;

          // Credit Wallet
          t.set(walletRef, {
            balance_kobo: FieldValue.increment(amountKobo),
            cached_balance: FieldValue.increment(amount),
            balance: FieldValue.increment(amount)
          }, { merge: true });

          // Record Ledger atomically (prevents TOCTOU race conditions)
          t.create(txRef, {
            user_id: uid,
            type: "credit",
            amount: amount,
            amount_kobo: amountKobo,
            balance_after: balanceAfterKobo / 100,
            balance_after_kobo: balanceAfterKobo,
            source: "safehaven",
            reference: sessionId,
            status: "success",
            merchant_name: "SafeHaven Transfer",
            created_at: FieldValue.serverTimestamp()
          });

          // Add Notification
          const notifRef = db.collection("users").doc(uid).collection("notifications").doc();
          t.set(notifRef, {
            title: "Wallet Funded",
            body: `₦${amount.toLocaleString()} has been credited to your wallet via Vault Transfer.`,
            type: "credit",
            isRead: false,
            timestamp: FieldValue.serverTimestamp()
          });
        });

        logger.info(`[SafeHaven Webhook] Successfully credited ₦${amount} to UID ${uid}`);
      } catch (err) {
        if (err.code === 6) { // ALREADY_EXISTS
           logger.info(`[SafeHaven Webhook] Concurrent request detected and blocked for ${sessionId}.`);
        } else {
           throw err;
        }
      }
    }

  } catch (error) {
    logger.error("[SafeHaven Webhook] Error processing event:", error);
  }
});

module.exports = {
  getSafeHavenToken,
  initiateSafeHavenVerification,
  validateSafeHavenIdentity,
  generateSafeHavenDva,
  safehavenWebhook
};
