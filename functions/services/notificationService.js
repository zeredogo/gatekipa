const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");

/**
 * Write a notification under /users/{userId}/notifications/{docId}.
 * The Admin SDK bypasses Firestore rules so this always succeeds.
 *
 * @param {string} accountId  - The account that triggered the event
 * @param {string} message    - Human-readable message body
 * @param {object} opts       - Optional overrides: { type, title, metadata }
 */
async function sendNotification(accountId, message, opts = {}) {
  let userId = null;

  try {
    const accSnap = await db.collection("accounts").doc(accountId).get();
    if (accSnap.exists) {
      userId = accSnap.data().owner_user_id || null;
    }
  } catch (_) {
    // Non-critical — skip if account lookup fails
  }

  if (!userId) {
    console.warn("[Notification] Could not resolve userId for account:", accountId);
    return;
  }

  // Derive a sensible type and title from the message if not provided
  const type = opts.type || deriveType(message);
  const title = opts.title || deriveTitle(type);

  await db
    .collection("users")
    .doc(userId)
    .collection("notifications")
    .add({
      user_id: userId,
      account_id: accountId,
      type,
      title,
      body: message,
      isRead: false,
      timestamp: FieldValue.serverTimestamp(),
      metadata: opts.metadata || null,
    });
}

/** Infer notification type from message content */
function deriveType(message) {
  const lower = message.toLowerCase();
  if (lower.includes("block") || lower.includes("decline") || lower.includes("denied")) {
    return "blocked";
  }
  if (lower.includes("scan") || lower.includes("subscri")) {
    return "system";
  }
  if (lower.includes("trial") || lower.includes("disabled")) {
    return "system";
  }
  return "transaction";
}

/** Map a type to a UI-friendly title */
function deriveTitle(type) {
  switch (type) {
    case "blocked":   return "Transaction Blocked";
    case "upcoming":  return "Upcoming Charge";
    case "system":    return "System Alert";
    default:          return "Transaction Update";
  }
}

module.exports = { sendNotification };
