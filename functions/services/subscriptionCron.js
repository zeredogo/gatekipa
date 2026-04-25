const { onSchedule } = require("firebase-functions/v2/scheduler");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");

exports.scanSubscriptionPatterns = onSchedule("0 0 * * 0", async (event) => { // Runs every Sunday at Midnight
  const now = Date.now();
  // Look back 60 days
  const sixtyDaysAgo = now - (60 * 24 * 60 * 60 * 1000);
  
  // To avoid massive memory spikes, we'll process users in batches
  // But for Gatekeeper MVP, we'll query all transactions from the last 60 days.
  // We need to find users with Sentinel Prime plan to respect tiers.
  const premiumUsersSnap = await db.collection("users")
    .where("planTier", "in", ["premium", "business"])
    .get();
    
  if (premiumUsersSnap.empty) return { success: true, message: "No premium users found" };
  
  const premiumUids = premiumUsersSnap.docs.map(doc => doc.id);

  console.info(`[SubscriptionCron] Scanning patterns for ${premiumUids.length} premium users.`);

  let totalDetected = 0;

  // We should process user by user to stay within bounds
  for (const uid of premiumUids) {
    
    // Fetch user's cards first
    const cardsSnap = await db.collection("cards")
       .where("created_by", "==", uid)
       .get();
       
    if (cardsSnap.empty) continue;
    const cardIds = cardsSnap.docs.map(d => d.id);
    
    for (const cardId of cardIds) {
      // Find all approved transactions for this card in the last 60 days
      const txnsSnap = await db.collection("transactions")
        .where("card_id", "==", cardId)
        .where("status", "==", "approved")
        .get();
        
      if (txnsSnap.empty) continue;
      
      const transactions = txnsSnap.docs
         .map(d => Object.assign(d.data(), { _docId: d.id }))
         .filter(t => {
            const time = t.timestamp && t.timestamp.toDate ? t.timestamp.toDate().getTime() : new Date(t.timestamp).getTime();
            return time >= sixtyDaysAgo;
         });
         
      // Group ONLY by merchant
      const groups = {};
      for (const txn of transactions) {
         const key = txn.merchant_name;
         if (!key) continue;
         if (!groups[key]) {
             groups[key] = [];
         }
         groups[key].push(txn);
      }
      
      // Analyze groups
      for (const [key, groupTxns] of Object.entries(groups)) {
         if (groupTxns.length >= 2) {
             // Sort by time
             groupTxns.sort((a, b) => {
                const aT = a.timestamp && a.timestamp.toDate ? a.timestamp.toDate().getTime() : new Date(a.timestamp).getTime();
                const bT = b.timestamp && b.timestamp.toDate ? b.timestamp.toDate().getTime() : new Date(b.timestamp).getTime();
                return aT - bT;
             });
             
             // Check if earliest and latest are at least 25 days apart
             const earliest = groupTxns[0].timestamp && groupTxns[0].timestamp.toDate ? groupTxns[0].timestamp.toDate().getTime() : new Date(groupTxns[0].timestamp).getTime();
             const latest = groupTxns[groupTxns.length - 1].timestamp && groupTxns[groupTxns.length - 1].timestamp.toDate ? groupTxns[groupTxns.length - 1].timestamp.toDate().getTime() : new Date(groupTxns[groupTxns.length - 1].timestamp).getTime();
             
             if (latest - earliest >= 25 * 24 * 60 * 60 * 1000) {
                 // Solid chance this is a subscription!
                 const merchantName = groupTxns[0].merchant_name;
                 const oldestAmount = groupTxns[0].amount;
                 const latestAmount = groupTxns[groupTxns.length - 1].amount;
                 
                 // PRICE HIKE DETECTION
                 let isPriceHike = false;
                 if (latestAmount > oldestAmount) {
                     isPriceHike = true;
                 }
                 
                 // Check if it's already detected for this specific EXACT merchant
                 const existingSnap = await db.collection("users").doc(uid).collection("detected_subscriptions")
                    .where("name", "==", merchantName)
                    .limit(1).get();
                    
                 if (existingSnap.empty) {
                     const subDoc = {
                       name: merchantName,
                       amount: Math.round(latestAmount * 100),
                       currency: "NGN",
                       category: 'Service',
                       cycle: 'monthly',
                       color_hex: isPriceHike ? '#DC2626' : '#1E40AF',
                       icon: 'receipt_long_rounded',
                       raw_message: isPriceHike ? `PRICE HIKE! Increased from ₦${oldestAmount}` : `Auto-detected from ${groupTxns.length} card charges`,
                       detectedAt: new Date().toISOString(),
                       next_billing_date: latest + (30 * 24 * 60 * 60 * 1000)
                     };
                     
                     await db.collection("users").doc(uid).collection("detected_subscriptions").add(subDoc);
                     totalDetected++;
                     
                     if (isPriceHike) {
                        try {
                           const uDoc = await db.collection("users").doc(uid).get();
                           const fcmToken = uDoc.data()?.fcm_token;
                           if (fcmToken) {
                               const { getMessaging } = require("firebase-admin/messaging");
                               await getMessaging().send({
                                  token: fcmToken,
                                  notification: {
                                    title: "Price Hike Alert!",
                                    body: `${merchantName} just increased your bill from ₦${oldestAmount} to ₦${latestAmount}.`
                                  }
                               });
                           }
                           
                           // In app notification
                           await uDoc.ref.collection("notifications").add({
                             title: "Price Hike Detected",
                             body: `${merchantName} increased their standard price. Do you want to freeze the card?`,
                             timestamp: new Date(),
                             isRead: false,
                             type: "alert",
                           });
                        } catch (err) {
                           console.error("FCM dispatch failed", err);
                        }
                     }
                 } else if (isPriceHike && existingSnap.docs[0].data().amount < Math.round(latestAmount * 100)) {
                     // Upgrade existing record
                     await existingSnap.docs[0].ref.update({
                        amount: Math.round(latestAmount * 100),
                        raw_message: `PRICE HIKE! Increased from ₦${oldestAmount}`,
                        color_hex: '#DC2626',
                        next_billing_date: latest + (30 * 24 * 60 * 60 * 1000)
                     });
                     
                     try {
                           const uDoc = await db.collection("users").doc(uid).get();
                           const fcmToken = uDoc.data()?.fcm_token;
                           if (fcmToken) {
                               const { getMessaging } = require("firebase-admin/messaging");
                               await getMessaging().send({
                                  token: fcmToken,
                                  notification: {
                                    title: "Price Hike Alert!",
                                    body: `${merchantName} just increased your bill from ₦${oldestAmount} to ₦${latestAmount}.`
                                  }
                               });
                           }
                     } catch (err) { }
                 }
             }
         }
      }
    }
  }

  console.info(`[SubscriptionCron] Finished scan. Detected ${totalDetected} new subscriptions.`);
  return { success: true, detected: totalDetected };
});

exports.sendRenewalReminders = onSchedule("0 9 * * *", async (event) => { // Runs daily at 9:00 AM
  const { getMessaging } = require("firebase-admin/messaging");
  
  // Find all users
  const usersSnap = await db.collection("users").get();
  if (usersSnap.empty) return;
  
  let remindersSent = 0;
  const now = Date.now();
  
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const userData = userDoc.data();
    
    const subsSnap = await db.collection("users").doc(uid).collection("detected_subscriptions").get();
    if (subsSnap.empty) continue;
    
    for (const subDoc of subsSnap.docs) {
      const sub = subDoc.data();
      if (!sub.next_billing_date) continue;
      
      const diffMs = sub.next_billing_date - now;
      const daysRemaining = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
      
      if ([5, 3, 1].includes(daysRemaining)) {
         try {
           const timeText = daysRemaining === 1 ? '24 hours' : `${daysRemaining} days`;
           const fcmToken = userData.fcm_token;
           if (fcmToken) {
               await getMessaging().send({
                  token: fcmToken,
                  notification: {
                    title: "Upcoming Subscription 🔔",
                    body: `${sub.name} (₦${sub.amount/100}) is due in ${timeText}. Gatekipa allows you to freeze your card if you want to cancel it!`
                  }
               });
           }
           
           await userDoc.ref.collection("notifications").add({
             title: "Upcoming Subscription",
             body: `${sub.name} is due in ${timeText}. Gatekipa allows you to freeze your card to cancel it.`,
             timestamp: new Date(),
             isRead: false,
             type: "alert",
           });
           remindersSent++;
         } catch (err) { }
      }
    }
  }
  
  console.info(`[SubscriptionCron] Sent ${remindersSent} 5-day/3-day/24-hour renewal reminders.`);
});
