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

  let userDoc = null;

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

  // 1. Write to in-app notification center
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

  // 2. Dispatch FCM Push Notification if token exists
  try {
    userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists) {
      const fcmToken = userDoc.data().fcm_token;
      if (fcmToken) {
        const { getMessaging } = require("firebase-admin/messaging");
        await getMessaging().send({
          token: fcmToken,
          notification: {
            title: title,
            body: message,
          },
          data: {
            type: type,
            account_id: accountId,
          },
        });
        console.info(`[Notification] FCM sent successfully to ${userId}`);
      }
    }
  } catch (err) {
    console.warn(`[Notification] FCM dispatch failed for ${userId}:`, err.message);
  }
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

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { requireAdmin } = require("../utils/validators");

/**
 * Cloud Function: adminBroadcastMessage
 * Allows Admins to broadcast messages via In-App, Push, and WhatsApp.
 */
exports.adminBroadcastMessage = onCall({ region: "us-central1" }, async (request) => {
  requireAdmin(request.auth);

  const { userIds, title, message, channels } = request.data;
  if (!Array.isArray(userIds) || !title || !message || !channels) {
    throw new HttpsError("invalid-argument", "Missing required broadcast parameters.");
  }

  let successCount = 0;
  const { getMessaging } = require("firebase-admin/messaging");

  // Dynamically require fetch if needed for older Node versions, though Node 18+ has native fetch.
  // We'll use native fetch for the Tabi API.

  for (const userId of userIds) {
    try {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data();

      // 1. In-App Notification
      if (channels.inApp) {
        await db.collection("users").doc(userId).collection("notifications").add({
          user_id: userId,
          type: "system",
          title: title,
          body: message,
          isRead: false,
          timestamp: FieldValue.serverTimestamp(),
        });
      }

      // 2. Push Notification
      if (channels.push && userData.fcm_token) {
        try {
          await getMessaging().send({
            token: userData.fcm_token,
            notification: { title, body: message },
            data: { type: "broadcast" },
          });
        } catch (pushErr) {
          console.warn(`[Broadcast] FCM failed for ${userId}:`, pushErr.message);
        }
      }

      // 3. WhatsApp Integration via Tabi.Africa
      if (channels.whatsapp && userData.phone_number) {
        const tabiKey = process.env.TABI_API_KEY;
        const tabiChannelId = process.env.TABI_CHANNEL_ID;
        
        if (tabiKey && tabiChannelId) {
          try {
            await fetch(`https://api.tabi.africa/api/v1/channels/${tabiChannelId}/send`, {
              method: "POST",
              headers: { 
                "Authorization": `Bearer ${tabiKey}`, 
                "Content-Type": "application/json" 
              },
              body: JSON.stringify({ 
                recipient: userData.phone_number, 
                type: "text",
                message: { text: message } 
              })
            });
          } catch (waErr) {
            console.error(`[Broadcast] Tabi.Africa failed for ${userId}:`, waErr.message);
          }
        } else {
          console.warn("[Broadcast] Skipping WhatsApp: TABI_API_KEY or TABI_CHANNEL_ID environment variable is missing.");
        }
      }

      successCount++;
    } catch (err) {
      console.error(`[Broadcast] Failed to process user ${userId}:`, err.message);
    }
  }

  return { success: true, count: successCount };
});

/**
 * Cloud Function: adminSendInAppNotification
 * Used specifically for the 1-on-1 notification modal in the Users tab.
 */
exports.adminSendInAppNotification = onCall({ region: "us-central1" }, async (request) => {
  requireAdmin(request.auth);

  const { userId, title, message } = request.data;
  if (!userId || !title || !message) {
    throw new HttpsError("invalid-argument", "Missing required parameters.");
  }

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new HttpsError("not-found", "User not found.");
  }

  // Write to in-app notifications
  await db.collection("users").doc(userId).collection("notifications").add({
    user_id: userId,
    type: "system",
    title: title,
    body: message,
    isRead: false,
    timestamp: FieldValue.serverTimestamp(),
  });

  // Push Notification
  const fcmToken = userDoc.data().fcm_token;
  if (fcmToken) {
    const { getMessaging } = require("firebase-admin/messaging");
    try {
      await getMessaging().send({
        token: fcmToken,
        notification: { title, body: message },
        data: { type: "system" },
      });
    } catch (e) {
      console.warn(`[SendInApp] FCM failed for ${userId}:`, e.message);
    }
  }

  return { success: true };
});
