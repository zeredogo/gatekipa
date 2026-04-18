const { onSchedule } = require("firebase-functions/v2/scheduler");
const { db } = require("../utils/firebase");
const logger = require("firebase-functions/logger");

/**
 * integritySweep
 * 
 * Runs every 12 hours automatically via Cloud Scheduler Pub/Sub.
 * Scans all active users and verifies perfectly that sum(wallet_transactions) == wallet.balance.
 * If there is any fractional desync, it logs the failure and writes a CRITICAL health_log.
 */
exports.integritySweep = onSchedule("every 12 hours", async (event) => {
  logger.info("[IntegritySweep] Commencing bi-daily global ledger reconciliation...");
  
  const usersSnap = await db.collection("users").get();
  let totalAudited = 0;
  let totalCompromised = 0;

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    totalAudited++;

    // 1. Fetch expected balance
    const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
    const balance = walletSnap.exists ? (walletSnap.data().balance || 0) : 0;

    // 2. Fetch full historical ledger
    const txSnap = await db.collection(`users/${uid}/wallet_transactions`).get();
    let calculatedLedger = 0;

    txSnap.docs.forEach((txDoc) => {
      const tx = txDoc.data();
      // 'processing' entries are in-flight withdrawals that haven't been
      // confirmed or rolled back yet. Ignore them to prevent false CRITICAL alerts.
      if (tx.status === "processing") return;
      if (tx.type === "credit") {
        calculatedLedger += (tx.amount || 0);
      } else if (tx.type === "debit") {
        calculatedLedger -= (tx.amount || 0);
      }
    });

    const isConsistent = balance === calculatedLedger;

    if (!isConsistent) {
      totalCompromised++;
      const message = `CRITICAL DESYNC: User ${uid} wallet claims ${balance} but ledger mathematics sum to ${calculatedLedger}.`;
      logger.error(message);
      
      // Auto-dump into a health_logs collection for the Admin Dashboard to flag immediately
      await db.collection("health_logs").add({
        timestamp: new Date().toISOString(),
        level: "CRITICAL",
        source: "integritySweep",
        message,
        uid,
        balance,
        calculatedLedger
      });
    }
  }

  logger.info(`[IntegritySweep] Concluded. Audited: ${totalAudited}, Compromised: ${totalCompromised}`);
});
