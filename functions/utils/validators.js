const { HttpsError } = require("firebase-functions/v2/https");

function requireAuth(auth) {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }
}

function requireFields(data, fields) {
  for (const field of fields) {
    if (data[field] === undefined || data[field] === null) {
      throw new HttpsError("invalid-argument", `Missing required field: ${field}`);
    }
  }
}

module.exports = {
  requireAuth,
  requireFields
};
