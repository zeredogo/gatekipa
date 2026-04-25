const { onSchedule } = require("firebase-functions/v2/scheduler");
const { db } = require("../utils/firebase");
const { getMessaging } = require("firebase-admin/messaging");

// All plan tiers that can expire and need monitoring
const EXPIRABLE_PLANS = ["free", "activation", "premium", "business"];

exports.expirationCron = onSchedule("0 0 * * *", async (event) => { // Runs daily at Midnight
  const now = Date.now();

  // ── 1. Send Reminders — subscription_expiry_date (3 days out) ──────────────
  const threeDaysFromNow = now + (3 * 24 * 60 * 60 * 1000);
  const threeDaysOutLower = threeDaysFromNow - (12 * 60 * 60 * 1000); // 12 hr window
  const threeDaysOutUpper = threeDaysFromNow + (12 * 60 * 60 * 1000);

  const expiringSoonSnap = await db.collection("users")
    .where("planTier", "in", EXPIRABLE_PLANS)
    .where("subscription_expiry_date", ">=", threeDaysOutLower)
    .where("subscription_expiry_date", "<=", threeDaysOutUpper)
    .get();

  let remindersSent = 0;
  for (const doc of expiringSoonSnap.docs) {
    const data = doc.data();

    // In-app Notification
    await doc.ref.collection("notifications").add({
      title: "Subscription Expiring Soon!",
      body: `Your ${data.planTier} plan will expire in 3 days. Please manually renew your plan from your Vault to avoid losing features.`,
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

  // ── 2. Send Reminders — sentinel_trial_expiry_date (1 day out for trial) ───
  // Instant & Activation users get a shorter 1-day warning since trial is only 5 days
  const oneDayFromNow = now + (1 * 24 * 60 * 60 * 1000);
  const oneDayOutLower = oneDayFromNow - (12 * 60 * 60 * 1000);
  const oneDayOutUpper = oneDayFromNow + (12 * 60 * 60 * 1000);

  const trialExpiringSoonSnap = await db.collection("users")
    .where("planTier", "in", ["free", "activation"])
    .where("sentinel_trial_expiry_date", ">=", oneDayOutLower)
    .where("sentinel_trial_expiry_date", "<=", oneDayOutUpper)
    .get();

  for (const doc of trialExpiringSoonSnap.docs) {
    const data = doc.data();

    await doc.ref.collection("notifications").add({
      title: "Sentinel Trial Expiring Tomorrow!",
      body: "Your 5-day Sentinel Prime trial ends in 1 day. Upgrade to Sentinel or Business to keep advanced features.",
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    if (data.fcm_token) {
      try {
        await getMessaging().send({
          token: data.fcm_token,
          notification: {
            title: "Sentinel Trial Ending Soon",
            body: "Upgrade to Sentinel Prime to keep Night Lockdown, Breach Alerts, and more."
          }
        });
        remindersSent++;
      } catch (err) {
        console.error(`Failed to send trial reminder to ${doc.id}:`, err);
      }
    }
  }

  // ── 3. Downgrade Expired Main Plans ────────────────────────────────────────
  const expiredSnap = await db.collection("users")
    .where("planTier", "in", EXPIRABLE_PLANS)
    .where("subscription_expiry_date", "<", now)
    .get();

  let downgraded = 0;

  const batchArray = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const doc of expiredSnap.docs) {
    const data = doc.data();

    // Clear both expiry fields on full downgrade
    currentBatch.update(doc.ref, {
      planTier: "none",
      subscription_expiry_date: null,
      sentinel_trial_expiry_date: null, // FIX #8: always clear trial field on downgrade
    });

    // Send downgrade notification
    const notifRef = doc.ref.collection("notifications").doc();
    currentBatch.set(notifRef, {
      title: "Subscription Expired",
      body: `Your ${data.planTier} plan has expired. Premium features are now locked. Renew from your Vault.`,
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    operationCount += 2;

    // Downgrade all active/pending cards to trial mode
    const cardsSnap = await db.collection("cards").where("created_by", "==", doc.id).get();
    for (const cardDoc of cardsSnap.docs) {
      currentBatch.update(cardDoc.ref, { is_trial: true });
      operationCount += 1;

      if (operationCount >= 450) {
        batchArray.push(currentBatch);
        currentBatch = db.batch();
        operationCount = 0;
      }
    }

    downgraded++;

    if (operationCount >= 450) {
      batchArray.push(currentBatch);
      currentBatch = db.batch();
      operationCount = 0;
    }
  }

  // ── 4. Expire Sentinel Trials (without downgrading the base plan) ──────────
  // These users keep their Instant/Activation plan but lose Sentinel features
  const trialExpiredSnap = await db.collection("users")
    .where("planTier", "in", ["free", "activation"])
    .where("sentinel_trial_expiry_date", "<", now)
    .get();

  let trialsExpired = 0;

  for (const doc of trialExpiredSnap.docs) {
    currentBatch.update(doc.ref, {
      sentinel_trial_expiry_date: null, // FIX #2: clear stale trial field
    });

    const notifRef = doc.ref.collection("notifications").doc();
    currentBatch.set(notifRef, {
      title: "Sentinel Trial Ended",
      body: "Your 5-day Sentinel Prime trial has ended. Upgrade to Sentinel or Business to regain Night Lockdown, Breach Alerts, and advanced rules.",
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    operationCount += 2;
    trialsExpired++;

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

  console.info(`[ExpirationCron] Reminders Sent: ${remindersSent}, Plans Downgraded: ${downgraded}, Trials Expired: ${trialsExpired}`);
  return { success: true, remindersSent, downgraded, trialsExpired };
});
