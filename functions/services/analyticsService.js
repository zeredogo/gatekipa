const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth } = require("../utils/validators");
const { AggregateField } = require("firebase-admin/firestore");

exports.getUserAnalytics = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { accountIds } = request.data;

  // We fall back to querying transactions for just the user's uid if no accountIds are provided
  const queryAccountIds = Array.isArray(accountIds) && accountIds.length > 0 
    ? accountIds 
    : [uid];

  if (queryAccountIds.length > 30) {
    throw new HttpsError("invalid-argument", "Cannot aggregate more than 30 accounts at once.");
  }

  try {
    // 1. Fire up a Firebase AggregateQuery for high-performance, low-memory summation
    const txQuery = db.collection("transactions").where("account_id", "in", queryAccountIds);
    
    // We get the raw counts and sums directly from the Google servers
    const snapshot = await txQuery.aggregate({
      totalCount: AggregateField.count(),
      totalSpend: AggregateField.sum('amount')
    }).get();
    
    // Fallbacks if snapshot.data() behaves differently in this admin SDK version
    const data = snapshot.data();
    let totalSpend = data.totalSpend || 0;
    let txCount = data.totalCount || 0;
    let chargesBlocked = 0;
    let recoveredCapital = 0;

    // 2. Fetch declined transactions specifically for "Recovered Capital"
    // Since we can only do one `in` array query, and Firebase aggregate queries
    // don't easily support multi-conditional sums in one pass, we will do a targeted query
    // for just the declined ones. Since declined txns are rare, this is cheap.
    const declinedSnap = await txQuery.where("status", "==", "DECLINED").get();
    
    for (const doc of declinedSnap.docs) {
      chargesBlocked++;
      recoveredCapital += doc.data().amount || 0;
    }
    
    // If the above aggregate didn't filter out declined transactions from totalSpend, 
    // we need to subtract it, assuming totalSpend = ALL amounts regardless of status.
    // Actually, usually users only want "Total Spend" to be successful charges.
    // Since Firebase Aggregate `sum()` sums everything, we subtract the declined amount.
    totalSpend -= recoveredCapital;
    if (totalSpend < 0) totalSpend = 0;

    return {
      success: true,
      data: {
        totalSpend,
        recoveredCapital,
        chargesBlocked,
        txCount
      }
    };

  } catch (error) {
    console.error("[AnalyticsService] Error computing aggregates:", error);
    throw new HttpsError("internal", "Failed to compute user analytics.");
  }
});
