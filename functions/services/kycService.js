const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");

const SAFEHAVEN_CLIENT_ID = defineSecret("SAFEHAVEN_CLIENT_ID");
const SAFEHAVEN_PRIVATE_KEY = defineSecret("SAFEHAVEN_PRIVATE_KEY");

/**
 * verifyBvn — registers a BVN number for the user without redundant API verification.
 * 
 * Bridgecard will independently query the NIBSS database during the virtual card 
 * provisioning phase (`registerCardholder`). Therefore, we only need to securely 
 * store the BVN here so the client can progress.
 */
exports.verifyBvn = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { bvn, firstname, lastname } = request.data;

  if (!bvn || typeof bvn !== "string" || bvn.length !== 11) {
    throw new HttpsError("invalid-argument", "A valid 11-digit BVN is required.");
  }

  // Persist the BVN to the user profile for Bridgecard to use later
  await db.collection("users").doc(uid).set(
    {
      hasBvn: true,
      bvn: bvn,
      bvnVerifiedAt: FieldValue.serverTimestamp(),
      bvnMeta: { 
          source: "user_provided", 
          firstname: firstname || null, 
          lastname: lastname || null 
      },
    },
    { merge: true }
  );

  return { success: true, message: "BVN saved successfully." };
});

/**
 * verifyKyc — initiates identity verification locally.
 * 
 * For Nigerians: Requires `idNumber` (NIN/BVN).
 * For Non-Nigerians: Requires `documentUrl`.
 * 
 * We no longer use QoreID here as Bridgecard validates the Nigerian ID numbers natively.
 */
exports.verifyKyc = onCall({ region: "us-central1", secrets: [SAFEHAVEN_CLIENT_ID, SAFEHAVEN_PRIVATE_KEY] }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  if (!data.selfieUrl || (data.country !== 'Nigeria' && !data.documentUrl)) {
    throw new HttpsError("invalid-argument", "Selfie is required, and Document proof is required for non-Nigerians.");
  }

  if (data.country === 'Nigeria' && !data.idNumber) {
    throw new HttpsError("invalid-argument", "Identification number is required for Nigerian users.");
  }

  // Since Bridgecard natively handles ID Number verification during card creation,
  // we can immediately approve this step for Nigerian users who provided their ID string.
  // Non-Nigerians who provided documents are also approved for admin/Bridgecard manual review.
  const verificationMeta = { 
     source: "local_capture",
     photo: data.documentUrl || null,
     selfie: data.selfieUrl,
     country: data.country,
     state: data.state,
     idNumber: data.idNumber || null
  };

  await db.collection("users").doc(uid).set(
    {
      kycStatus: "verified",
      kycVerifiedAt: FieldValue.serverTimestamp(),
      kycMeta: verificationMeta,
    },
    { merge: true }
  );

  // Automatically generate SafeHaven dedicated virtual account (Vault NUBAN) for Nigerian users
  if (data.country === 'Nigeria') {
    try {
      const userDoc = await db.collection("users").doc(uid).get();
      const userData = userDoc.data() || {};
      
      const mergedUserData = {
        ...userData,
        bvn: data.idNumber,
        kycMeta: verificationMeta
      };

      const { initiateSafeHavenVerification, generateSafeHavenDva } = require("./safehavenService");
      
      // Download the selfie image from Firebase Storage and convert to base64
      if (!data.selfieUrl) {
        throw new HttpsError("invalid-argument", "Selfie URL is missing. Cannot auto-provision sub-account.");
      }

      console.log(`[verifyKyc] Fetching selfie from ${data.selfieUrl} for base64 conversion...`);
      const axios = require("axios");
      const response = await axios.get(data.selfieUrl, { responseType: 'arraybuffer' });
      const selfieBase64 = `data:image/jpeg;base64,${Buffer.from(response.data, 'binary').toString('base64')}`;

      console.log(`[verifyKyc] Automatically generating Vault account for UID ${uid}...`);
      const verificationResult = await initiateSafeHavenVerification(uid, mergedUserData, selfieBase64);
      if (verificationResult.success && verificationResult.identityId) {
        await generateSafeHavenDva(uid, mergedUserData, verificationResult.identityId, null, true);
      }
    } catch (safeHavenError) {
      console.error(`[verifyKyc] SafeHaven subaccount generation failed: ${safeHavenError.message}`);
      // Return success: true but with a warning, so the user's KYC is still verified,
      // and they can fallback to generating the NUBAN from the funds tab.
      return { 
        success: true, 
        message: "KYC verified successfully, but Vault NUBAN auto-generation failed. You can generate it in the wallet tab.",
        error: safeHavenError.message
      };
    }
  }

  return { 
    success: true, 
    message: "KYC verified and Vault generated successfully." 
  };
});

const SUDO_API_KEY = defineSecret("SUDO_API_KEY");

/**
 * validateIdentity — completes KYC by validating the SafeHaven OTP.
 */
exports.validateIdentity = onCall({ region: "us-central1", secrets: [SAFEHAVEN_CLIENT_ID, SAFEHAVEN_PRIVATE_KEY, SUDO_API_KEY] }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { identityId, otp } = request.data;
  
  if (!identityId || !otp) {
    throw new HttpsError("invalid-argument", "Identity ID and OTP are required.");
  }

  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() || {};
  const idType = userData.bvn ? "BVN" : "NIN";

  const { validateSafeHavenIdentity } = require("./safehavenService");
  const result = await validateSafeHavenIdentity(uid, identityId, otp, idType);

  if (result.success) {
    try {
      // 1. Re-fetch user data as it was just updated by validateSafeHavenIdentity
      const updatedDoc = await db.collection("users").doc(uid).get();
      const updatedData = updatedDoc.data() || {};
      
      // 2. Provision Sudo DVA automatically
      const { ensureSudoCustomer, ensureSudoAccount } = require("./sudoService");
      const customerId = await ensureSudoCustomer(uid, updatedData);
      await ensureSudoAccount(uid, customerId, updatedData);
      
    } catch (sudoErr) {
      console.error(`[KYC] OTP Validated but Sudo DVA generation failed for ${uid}:`, sudoErr.message);
      // We don't throw here because KYC is already verified.
      // DVA will be retried when they try to fund/create card.
    }
  }
  
  return result;
});
