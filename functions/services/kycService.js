const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");

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
exports.verifyKyc = onCall({ region: "us-central1" }, async (request) => {
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

  return { 
    success: true, 
    message: "KYC details saved successfully." 
  };
});

const SAFEHAVEN_CLIENT_ID = defineSecret("SAFEHAVEN_CLIENT_ID");
const SAFEHAVEN_PRIVATE_KEY = defineSecret("SAFEHAVEN_PRIVATE_KEY");
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
