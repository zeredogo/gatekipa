const { HttpsError } = require("firebase-functions/v2/https");
const { db } = require("./firebase");
const crypto = require("crypto");

function requireAuth(auth) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }
}

function requireVerifiedEmail(auth) {
  requireAuth(auth);
  if (!auth.token.email_verified) {
    throw new HttpsError("permission-denied", "You must verify your email address before performing this action.");
  }
}

async function requireKyc(uid) {
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists || (userDoc.data().kycStatus !== "verified" && userDoc.data().bridgecard_status !== "verified")) {
    throw new HttpsError("permission-denied", "You must complete identity verification (KYC/BVN) to perform this action.");
  }
}

function requireFields(data, fields) {
  for (const field of fields) {
    if (data[field] === undefined || data[field] === null) {
      throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
    }
  }
}

function requireAdmin(auth) {
  requireAuth(auth);
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Privileged Administrative access required.");
  }
}

async function requirePin(uid, pin) {
  if (!pin) {
    throw new HttpsError("unauthenticated", "Transaction PIN is required to authorize this action.");
  }
  const userDoc = await db.collection("users").doc(uid).get();
  const security = userDoc.data()?.security || {};
  
  if (!security.pinHash) {
    throw new HttpsError("failed-precondition", "No Transaction PIN is configured on your account. Please set up a PIN in your Profile settings first.");
  }
  
  const [salt, storedHash] = security.pinHash.split(":");
  const hash = crypto.scryptSync(pin, salt, 64).toString("hex");
  
  if (hash !== storedHash) {
    throw new HttpsError("unauthenticated", "Invalid Transaction PIN.");
  }
}

module.exports = {
  requireAuth,
  requireVerifiedEmail,
  requireKyc,
  requireFields,
  requireAdmin,
  requirePin
};
