const { HttpsError } = require("firebase-functions/v2/https");
const { db } = require("./firebase");

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

module.exports = {
  requireAuth,
  requireVerifiedEmail,
  requireKyc,
  requireFields,
  requireAdmin
};
