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
         
      // Group by merchant and amount
      const groups = {};
      for (const txn of transactions) {
         const key = `${txn.merchant_name}_${txn.amount}`;
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
                 const amount = groupTxns[0].amount;
                 
                 // Check if it's already detected
                 const existingSnap = await db.collection("users").doc(uid).collection("detected_subscriptions")
                    .where("name", "==", merchantName)
                    .where("amount", "==", Math.round(amount * 100))
                    .limit(1).get();
                    
                 if (existingSnap.empty) {
                     const subDoc = {
                       name: merchantName,
                       amount: Math.round(amount * 100),
                       currency: "NGN",
                       category: 'Service',
                       cycle: 'monthly',
                       color_hex: '#1E40AF',
                       icon: 'receipt_long_rounded',
                       raw_message: `Auto-detected from ${groupTxns.length} identical card charges`,
                       detectedAt: new Date().toISOString()
                     };
                     
                     await db.collection("users").doc(uid).collection("detected_subscriptions").add(subDoc);
                     totalDetected++;
                 }
             }
         }
      }
    }
  }

  console.info(`[SubscriptionCron] Finished scan. Detected ${totalDetected} new subscriptions.`);
  return { success: true, detected: totalDetected };
});
