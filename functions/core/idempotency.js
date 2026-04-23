// functions/core/idempotency.js
//
// Centralized idempotency management for all financial operations.
// Keys are stored in the top-level `idempotency_keys` collection (NOT per-user
// sub-collections, so the backend can query across all users for audit).
//
// Key format (recommended): "{userId}:{operation}:{nonce}"
//   e.g. "uid123:wallet_funding:paystack_ref_abc"
//
// TTL: 24 hours. A scheduled cron can clean up expired keys.

const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");

/**
 * Checks if an idempotency key has already been processed.
 * Returns the result transaction ID if found, null otherwise.
 *
 * @param {string} key - The idempotency key to check.
 * @returns {Promise<string|null>} Existing txn ID or null.
 */
async function checkIdempotency(key) {
  const snap = await db.collection("idempotency_keys").doc(key).get();
  if (snap.exists) {
    return snap.data().result_txn_id || null;
  }
  return null;
}

/**
 * Records the result of a completed operation against an idempotency key.
 *
 * @param {string} key - The idempotency key.
 * @param {string} userId - UID of the user who initiated the operation.
 * @param {string} resultTxnId - The Firestore document ID of the resulting transaction.
 * @param {string} status - 'SUCCESS' | 'FAILED' | 'UNKNOWN'
 */
async function storeIdempotencyResult(key, userId, resultTxnId, status) {
  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + 24);

  await db.collection("idempotency_keys").doc(key).set({
    user_id: userId,
    result_txn_id: resultTxnId,
    status,
    created_at: FieldValue.serverTimestamp(),
    expires_at: expiresAt,
  });
}

module.exports = { checkIdempotency, storeIdempotencyResult };
