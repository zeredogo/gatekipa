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

let cachedQoreIdToken = null;
let qoreIdTokenExpiry = 0;

async function getQoreIdToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedQoreIdToken && qoreIdTokenExpiry > now + 60) {
    return cachedQoreIdToken;
  }

  const clientId = process.env.QOREID_CLIENT_ID;
  const clientSecret = process.env.QOREID_CLIENT_SECRET || process.env.QOREID_API_KEY;

  if (!clientId || !clientSecret) {
    logger.error("[QoreID] QOREID_CLIENT_ID or QOREID_CLIENT_SECRET/QOREID_API_KEY is not configured.");
    throw new HttpsError("internal", "Identity verification service credentials are not configured.");
  }

  try {
    logger.info(`[QoreID] Requesting access token using clientId=${clientId}`);
    const res = await axios.post("https://api.qoreid.com/token", {
      clientId: clientId,
      secret: clientSecret
    }, {
      headers: {
        "Content-Type": "application/json"
      }
    });

    cachedQoreIdToken = res.data.accessToken;
    qoreIdTokenExpiry = now + (res.data.expiresIn || 7200);
    return cachedQoreIdToken;
  } catch (err) {
    const errorBody = err.response?.data;
    const errorStatus = err.response?.status;
    logger.error(`[QoreID] Auth Token Retrieval Failed. Status: ${errorStatus}. Body:`, JSON.stringify(errorBody));
    throw new HttpsError("internal", "Failed to authenticate with identity verification service.");
  }
}

async function performGeminiFaceMatch(documentUrl, selfieBase64) {
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!geminiKey) {
    logger.error("[AI Match] GEMINI_API_KEY is not configured. Fallback matching cannot run.");
    throw new HttpsError("internal", "Identity verification service is temporarily unavailable.");
  }

  logger.info(`[AI Match] Fetching document image from ${documentUrl}`);
  let docBase64;
  try {
    const docRes = await axios.get(documentUrl, { responseType: 'arraybuffer' });
    docBase64 = Buffer.from(docRes.data, 'binary').toString('base64');
  } catch (docErr) {
    logger.error(`[AI Match] Failed to download document image: ${docErr.message}`);
    throw new HttpsError("internal", "Could not retrieve the registered ID document image for verification.");
  }

  let cleanSelfie = selfieBase64;
  if (cleanSelfie.includes(";base64,")) {
    cleanSelfie = cleanSelfie.split(";base64,").pop();
  }

  logger.info("[AI Match] Sending comparison request to Gemini 2.5 Flash");
  try {
    const geminiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`;
    const payload = {
      contents: [
        {
          parts: [
            {
              text: "You are a secure compliance and identity verification assistant. Analyze the two provided images. Image 1 is either an official government ID card or slip (like a NIN card, NIN slip, BVN document, voter's card, driver's license, or international passport) or a previously verified registered selfie photo of the user. Image 2 is a new live captured selfie of the user. Perform two checks: 1) If Image 1 is an ID document, verify that it is a valid, authentic-looking government-issued ID document containing a clear passport photo. If Image 1 is a selfie, verify it is a valid face photo. 2) Compare the face on the reference photo (Image 1) with the face in the live selfie (Image 2) and verify if they belong to the exact same person. Respond ONLY with a valid JSON object matching this schema: {\"match\": boolean, \"confidence\": number (0.0 to 1.0), \"reason\": string}. If reference image is not valid, or if the faces do not match, set \"match\" to false. IMPORTANT: Be highly lenient and accommodating of lighting differences, camera noise, minor angle variations, and low resolution. Focus strictly on core skeletal facial structure (nose, eyes, mouth shape, jawline) rather than image illumination or quality."
            },
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: docBase64
              }
            },
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: cleanSelfie
              }
            }
          ]
        }
      ],
      generationConfig: {
        responseMimeType: "application/json"
      }
    };

    const res = await axios.post(geminiEndpoint, payload, {
      headers: { "Content-Type": "application/json" }
    });

    const responseText = res.data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!responseText) {
      logger.error("[AI Match] Empty response from Gemini API.");
      throw new Error("Empty response from AI comparison model.");
    }

    const result = JSON.parse(responseText.trim());
    logger.info("[AI Match] Gemini comparison result:", JSON.stringify(result));

    return {
      success: result.match === true,
      confidence: parseFloat(result.confidence) || 0,
      reason: result.reason || "Verification comparison completed."
    };
  } catch (err) {
    logger.error(`[AI Match] Gemini API call or parse failed: ${err.message}`);
    throw new HttpsError("internal", "Identity verification process failed.");
  }
}

/**
 * Step 1: Initiates SafeHaven Identity Verification.
 * This triggers an OTP to the user's phone number registered with their BVN.
 */
async function initiateSafeHavenVerification(uid, userData, faceImageBase64 = null) {
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
    async: false
  };

  if (faceImageBase64) {
    payload.faceImageBase64 = faceImageBase64;

    // ── QoreID Face Verification Check ────────────────────────────────────────
    logger.info(`[QoreID] Verifying selfie for UID ${uid} against ${idType} database`);
    
    let cleanBase64 = faceImageBase64;
    if (cleanBase64.includes(";base64,")) {
      cleanBase64 = cleanBase64.split(";base64,").pop();
    }

    const qoreToken = await getQoreIdToken();

    try {
      const qoreEndpoint = `https://api.qoreid.com/v1/ng/identities/face-verification/${idType.toLowerCase()}`;
      const qoreRes = await axios.post(qoreEndpoint, {
        idNumber: idNumber,
        photoBase64: cleanBase64
      }, {
        headers: {
          "Authorization": `Bearer ${qoreToken}`,
          "Content-Type": "application/json",
          "Accept": "application/json"
        }
      });

      const qoreData = qoreRes.data;
      logger.info(`[QoreID] Response for UID ${uid}:`, JSON.stringify(qoreData));

      const isVerified = (qoreData.status?.status === "verified" || qoreData.status?.state === "complete") && 
                         (qoreData.summary?.status === "EXACT_MATCH" || qoreData.summary?.status === "MATCH");

      if (!isVerified) {
        throw new Error(`Face verification failed: match status is ${qoreData.summary?.status || "NO_MATCH"}.`);
      }
    } catch (qoreErr) {
      if (qoreErr instanceof HttpsError) throw qoreErr;

      const errorBody = qoreErr.response?.data;
      const errorStatus = qoreErr.response?.status;
      logger.warn(`[QoreID] Primary Face Match Failed/Error. Status: ${errorStatus}. Body:`, JSON.stringify(errorBody));

      const documentUrl = userData.kycMeta?.documentUrl || userData.kycMeta?.selfie || userData.kycMeta?.photo;
      const geminiKey = process.env.GEMINI_API_KEY;

      if (geminiKey && documentUrl) {
        logger.info(`[AI Fallback] Initiating AI Face Match fallback for UID ${uid}`);
        try {
          const aiResult = await performGeminiFaceMatch(documentUrl, faceImageBase64);
          
          if (aiResult.confidence >= 0.70) {
            logger.info(`[AI Fallback] Success! AI Face Match verified for UID ${uid} with confidence ${aiResult.confidence}`);
            // Let the flow continue
          } else if (aiResult.confidence >= 0.45) {
            logger.warn(`[AI Fallback] Low confidence match (${aiResult.confidence}) for UID ${uid}. Changing status to pending_review.`);
            
            // Save pending selfie to user document for admin review
            await db.collection("users").doc(uid).update({
              kycStatus: "pending_review",
              pendingSelfieBase64: faceImageBase64,
              kycSubmittedAt: FieldValue.serverTimestamp(),
              verificationFailReason: `Low confidence match (${aiResult.confidence}): ${aiResult.reason}`
            });

            throw new HttpsError(
              "failed-precondition",
              "We are reviewing your selfie to complete your verification. Your account will be ready shortly."
            );
          } else {
            logger.error(`[AI Fallback] Failed. AI Face Match rejected for UID ${uid} with confidence ${aiResult.confidence}. Reason: ${aiResult.reason}`);
            throw new HttpsError(
              "failed-precondition",
              `Face verification failed: captured selfie does not match the photo on your NIN/BVN document.`
            );
          }
        } catch (aiErr) {
          if (aiErr instanceof HttpsError) throw aiErr;
          logger.error(`[AI Fallback] Error during AI comparison for UID ${uid}: ${aiErr.message}`);
          throw new HttpsError(
            "failed-precondition",
            "Identity verification failed: please try again or ensure your selfie is captured in a well-lit area."
          );
        }
      } else {
        logger.error(`[QoreID] No AI Fallback possible. geminiKeyConfigured=${!!geminiKey}, hasDocumentUrl=${!!documentUrl}`);
        if (!documentUrl && geminiKey) {
          throw new HttpsError(
            "failed-precondition",
            "Identity verification failed. Please upload a clear photo of your ID document (NIN/BVN) in the KYC tab and try again."
          );
        }
        throw new HttpsError(
          "failed-precondition",
          errorBody?.message || "Identity face match verification failed."
        );
      }
    }
  }

  try {
    logger.info(`[SafeHaven] Initiating verification for UID ${uid}. idType=${idType}, ibs_client_id=${ibs_client_id}, hasFaceImage=${!!faceImageBase64}`);
    
    const res = await axios.post(`${BASE_URL}/identity/v2`, payload, {
      headers: {
        "Authorization": `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "ClientID": SAFEHAVEN_CLIENT_ID.value()
      }
    });

    logger.info("[SafeHaven] Identity initiation response:", JSON.stringify(res.data));
    const identityId = res.data?.data?._id || res.data?._id || res.data?.data?.id || res.data?.id;

    if (faceImageBase64) {
      // Automatically complete KYC verified state for vID flow
      await db.collection("users").doc(uid).update({
        safehaven_identity_id: identityId,
        safehaven_identity_type: "vID",
        kycStatus: "verified",
        kycVerifiedAt: FieldValue.serverTimestamp()
      });
    }

    return { success: true, identityId: identityId };

  } catch (err) {
    const errorBody = err.response?.data;
    const errorStatus = err.response?.status;
    logger.error(`[SafeHaven] Verification Initiation Failed for ${uid}. Status: ${errorStatus}. Error: ${err.message}. Stack: ${err.stack}. Body:`, JSON.stringify(errorBody));
    throw new HttpsError("internal", errorBody?.message || `Failed to initiate SafeHaven Verification. Status: ${errorStatus}. Error: ${err.message}`);
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
async function generateSafeHavenDva(uid, userData, identityId, otp, isVid = false) {
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

  if (!isVid && !idNumber) {
    throw new HttpsError(
      "failed-precondition", 
      "BVN/NIN is required to generate the account. Please complete your KYC verification."
    );
  }

  if (!identityId) {
    throw new HttpsError(
      "failed-precondition", 
      "Identity ID is required to generate the account. Please complete your KYC verification."
    );
  }

  // Per SafeHaven docs: sub-account creation takes the otp directly.
  const payload = {
    phoneNumber: phone,
    emailAddress: email,
    firstName: firstName,
    lastName: lastName,
    externalReference: `gatekipa_${uid}_${Date.now()}`,
    autoSweep: false
  };

  if (isVid) {
    payload.identityType = "vID";
    payload.identityId = identityId;
  } else {
    payload.identityType = idType;
    payload.identityNumber = idNumber;
    payload.identityId = identityId;
    payload.otp = otp;
  }

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
const safehavenWebhook = onRequest({ region: "us-central1", cpu: 0.5, memory: "512MiB", maxInstances: 10 }, async (req, res) => {
  // Webhook Security Authorization
  const webhookSecret = process.env.SAFEHAVEN_WEBHOOK_SECRET;
  if (!webhookSecret) {
    logger.error("[SafeHaven Webhook] Webhook Secret is not configured. Rejecting request to prevent bypass.");
    return res.status(500).json({ error: "Webhook configuration error" });
  }

  const signature = req.headers['x-signature'] || req.headers['x-safehaven-signature'];
  if (!signature) {
    logger.error("[SafeHaven Webhook] Unauthorized request. Missing signature header.");
    return res.status(401).json({ error: "Unauthorized" });
  }

  const crypto = require("crypto");
  const rawBody = req.rawBody;
  if (!rawBody) {
    logger.error("[SafeHaven Webhook] Raw request body missing for verification.");
    return res.status(400).json({ error: "Bad Request" });
  }

  const computedSignature = crypto
    .createHmac("sha256", webhookSecret)
    .update(rawBody)
    .digest("hex");

  try {
    const signatureBuffer = Buffer.from(signature, 'utf8');
    const computedBuffer = Buffer.from(computedSignature, 'utf8');
    if (signatureBuffer.length !== computedBuffer.length || !crypto.timingSafeEqual(signatureBuffer, computedBuffer)) {
      logger.error("[SafeHaven Webhook] Unauthorized request. Signature mismatch.");
      return res.status(401).json({ error: "Unauthorized" });
    }
  } catch (err) {
    logger.error("[SafeHaven Webhook] Signature comparison failed:", err);
    return res.status(401).json({ error: "Unauthorized" });
  }

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
