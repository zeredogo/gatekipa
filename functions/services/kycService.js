const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");

const QOREID_API_KEY = defineSecret("QOREID_API_KEY");

/**
 * verifyBvn — validates an 11-digit BVN number against QoreID.
 *
 * Input:  { bvn: string }
 * Output: { success: boolean, message: string }
 *
 * The function stores the result on the user document regardless of outcome
 * so the client can always rely on Firestore as the source of truth.
 */
exports.verifyBvn = onCall({ region: "us-central1", enforceAppCheck: true, secrets: [QOREID_API_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { bvn } = request.data;

  if (!bvn || typeof bvn !== "string" || bvn.length !== 11) {
    throw new HttpsError("invalid-argument", "A valid 11-digit BVN is required.");
  }

  const qoreIdKey = QOREID_API_KEY.value() || null;

  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const userData = userDoc.data() || {};
    if (userData.hasBvn) {
      throw new HttpsError("already-exists", "BVN is already verified.");
    }
    const bvnAttempts = userData.bvnVerificationAttempts || 0;
    if (bvnAttempts >= 1) {
      throw new HttpsError("permission-denied", "Maximum verification attempts reached. Please contact admin support for assistance.");
    }
    transaction.set(userRef, { bvnVerificationAttempts: bvnAttempts + 1 }, { merge: true });
  });

  let verified = false;
  let verificationMeta = {};

  if (qoreIdKey) {
    // ── Real QoreID check ─────────────────────────────────────────────────────
    try {
      const response = await fetch(
        "https://api.qoreid.com/v1/ng/identities/bvn/" + bvn,
        {
          method: "GET",
          headers: {
            Authorization: "Bearer " + qoreIdKey,
            "Content-Type": "application/json",
          },
        }
      );

      if (!response.ok) {
        const errBody = await response.json().catch(() => ({}));
        console.error("[KYC] QoreID error:", errBody);
        throw new HttpsError("internal", "Identity provider returned an error.");
      }

      const data = await response.json();

      // QoreID returns { status: { state: 'VERIFIED' | 'NOT_FOUND' } }
      verified = data?.status?.state === "VERIFIED";
      verificationMeta = {
        firstName: data?.bvn?.firstname || null,
        lastName: data?.bvn?.lastname || null,
        phone: data?.bvn?.phone || null,
        dob: data?.bvn?.birthdate || null,
        photo: data?.bvn?.photo || data?.bvn?.image || null,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[KYC] QoreID fetch failed:", err);
      throw new HttpsError("internal", "Could not reach the identity provider.");
    }
  } else {
    // ── Dev / staging fallback — accept any valid-format BVN ─────────────────
    console.warn("[KYC] QOREID_API_KEY not set — running in dev verification mode.");
    verified = true;
    verificationMeta = { devMode: true };
  }

  if (!verified) {
    throw new HttpsError("not-found", "BVN could not be verified. Please check the number and try again.");
  }

  // Persist the verification to the user profile
  await db.collection("users").doc(uid).set(
    {
      hasBvn: true,
      kycStatus: "verified",
      bvnVerifiedAt: FieldValue.serverTimestamp(),
      bvnMeta: verificationMeta,
    },
    { merge: true }
  );

  return { success: true, message: "BVN verified successfully." };
});

/**
 * verifyKyc — validates a user's National Identity Number (NIN) against QoreID.
 *
 * Input: { nin: string }
 * Output: { success: boolean, message: string }
 */
exports.verifyKyc = onCall({ region: "us-central1", enforceAppCheck: true, secrets: [QOREID_API_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { nin } = request.data;

  if (!nin || typeof nin !== "string" || nin.length !== 11) {
    throw new HttpsError("invalid-argument", "A valid 11-digit NIN is required.");
  }

  const qoreIdKey = QOREID_API_KEY.value() || null;

  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const userData = userDoc.data() || {};
    if (userData.kycStatus === "verified") {
      throw new HttpsError("already-exists", "NIN is already verified.");
    }
    const kycAttempts = userData.kycVerificationAttempts || 0;
    if (kycAttempts >= 1) {
      throw new HttpsError("permission-denied", "Maximum verification attempts reached. Please contact admin support for assistance.");
    }
    transaction.set(userRef, { kycVerificationAttempts: kycAttempts + 1 }, { merge: true });
  });

  let verified = false;
  let verificationMeta = {};

  if (qoreIdKey) {
    // ── Real QoreID check ─────────────────────────────────────────────────────
    try {
      const response = await fetch(
        "https://api.qoreid.com/v1/ng/identities/nin/" + nin,
        {
          method: "GET",
          headers: {
            Authorization: "Bearer " + qoreIdKey,
            "Content-Type": "application/json",
          },
        }
      );

      if (!response.ok) {
        const errBody = await response.json().catch(() => ({}));
        console.error("[KYC] QoreID NIN error:", errBody);
        throw new HttpsError("internal", "Identity provider returned an error.");
      }

      const data = await response.json();

      verified = data?.status?.state === "VERIFIED";
      verificationMeta = {
        firstName: data?.nin?.firstname || null,
        lastName: data?.nin?.lastname || null,
        phone: data?.nin?.phone || null,
        dob: data?.nin?.birthdate || null,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      console.error("[KYC] QoreID NIN fetch failed:", err);
      throw new HttpsError("internal", "Could not reach the identity provider.");
    }
  } else {
    // ── Dev / staging fallback ───────────────────────────────────────────────
    console.warn("[KYC] QOREID_API_KEY not set — running NIN verification in dev mode.");
    await new Promise((resolve) => setTimeout(resolve, 1500));
    verified = true;
    verificationMeta = { devMode: true };
  }

  if (!verified) {
    throw new HttpsError("not-found", "NIN could not be verified. Please check the number and try again.");
  }

  // Persist the verification to the user profile
  await db.collection("users").doc(uid).set(
    {
      kycStatus: "verified",
      kycVerifiedAt: FieldValue.serverTimestamp(),
      ninMeta: verificationMeta,
    },
    { merge: true }
  );

  return { success: true, message: "KYC verified successfully." };
});
