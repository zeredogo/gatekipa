const { onSchedule } = require("firebase-functions/v2/scheduler");
const { db } = require("../utils/firebase");
const { getMessaging } = require("firebase-admin/messaging");

exports.expirationCron = onSchedule("0 0 * * *", async (event) => { // Runs daily at Midnight
  const now = Date.now();
  
  // 1. Send Reminders (3 days out)
  const threeDaysFromNow = now + (3 * 24 * 60 * 60 * 1000);
  const threeDaysOutLower = threeDaysFromNow - (12 * 60 * 60 * 1000); // 12 hr window
  const threeDaysOutUpper = threeDaysFromNow + (12 * 60 * 60 * 1000);

  const expiringSoonSnap = await db.collection("users")
    .where("planTier", "in", ["premium", "business", "activation"])
    .where("subscription_expiry_date", ">=", threeDaysOutLower)
    .where("subscription_expiry_date", "<=", threeDaysOutUpper)
    .get();

  let remindersSent = 0;
  for (const doc of expiringSoonSnap.docs) {
    const data = doc.data();
    
    // In-app Notification
    await doc.ref.collection("notifications").add({
      title: "Subscription Expiring Soon!",
      body: `Your ${data.planTier} plan will expire in 3 days. Please manually renew your plan from your Vault to avoid losing premium features.`,
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    // FCM Notification
    if (data.fcm_token) {
      try {
        await getMessaging().send({
          token: data.fcm_token,
          notification: {
            title: "Plan Expiring Soon",
            body: "Renew your plan in the app to keep your cards active."
          }
        });
        remindersSent++;
      } catch (err) {
        console.error(`Failed to send expiration reminder to ${doc.id}:`, err);
      }
    }
  }

  // 2. Downgrade Expired Plans
  const expiredSnap = await db.collection("users")
    .where("planTier", "in", ["premium", "business", "activation"])
    .where("subscription_expiry_date", "<", now)
    .get();

  let downgraded = 0;
  
  // We can use batched writes for performance
  const batchArray = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const doc of expiredSnap.docs) {
    const data = doc.data();
    currentBatch.update(doc.ref, {
      planTier: "none",
      subscription_expiry_date: null // clear it out
    });
    
    // Send downgrade notification
    const notifRef = doc.ref.collection("notifications").doc();
    currentBatch.set(notifRef, {
      title: "Subscription Expired",
      body: `Your ${data.planTier} plan has expired. Premium features are now locked.`,
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    operationCount += 2;
    downgraded++;

    if (operationCount >= 450) {
      batchArray.push(currentBatch);
      currentBatch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    batchArray.push(currentBatch);
  }

  for (const batch of batchArray) {
    await batch.commit();
  }

  console.info(`[ExpirationCron] Reminders Sent: ${remindersSent}, Plans Downgraded: ${downgraded}`);
  return { success: true, remindersSent, downgraded };
});
