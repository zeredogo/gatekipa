// functions/services/reconciliationCron.js
//
// HARDENED integrity sweep — now reads from wallet_ledger (the authoritative
// append-only ledger) instead of the legacy wallet_transactions sub-collection.
//
// Also sweeps for UNKNOWN-status transactions (those where the network dropped
// mid-write) and raises critical alerts for manual reconciliation.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

/**
 * integritySweep
 *
 * Runs every 12 hours.
 * Checks two invariants:
 *   1. sum(wallet_ledger credits) - sum(wallet_ledger debits) == users/{uid}/wallet/balance.cached_balance
 *   2. No transactions are stuck in PENDING or PROCESSING status for > 10 minutes.
 */
exports.integritySweep = onSchedule("every 12 hours", async () => {
  logger.info("[IntegritySweep] Starting bi-daily global ledger reconciliation...");

  const usersSnap = await db.collection("users").get();
  let totalAudited = 0;
  let totalDesync = 0;
  let totalUnknown = 0;

  // ── 1. Wallet balance integrity ─────────────────────────────────────────────
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    totalAudited++;

    try {
      // a. Cached balance from wallet doc
      const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
      if (!walletSnap.exists) continue;

      const cachedBalance = walletSnap.data().cached_balance
        ?? walletSnap.data().balance
        ?? 0;

      // b. Authoritative sum from wallet_ledger
      const ledgerSnap = await db.collection("wallet_ledger")
        .where("user_id", "==", uid)
        .get();

      let ledgerSum = 0;
      for (const entry of ledgerSnap.docs) {
        const d = entry.data();
        // Skip in-flight entries (they'll resolve or fail within seconds)
        if (d.status === "processing" || d.status === "PENDING") continue;
        if (d.type === "credit") ledgerSum += (d.amount || 0);
        else if (d.type === "debit") ledgerSum -= (d.amount || 0);
      }

      // c. Tolerance: allow ≤ ₦0.01 floating-point drift
      const drift = Math.abs(cachedBalance - ledgerSum);
      if (drift > 0.01) {
        totalDesync++;
        const message = `DESYNC: UID ${uid} cached_balance=₦${cachedBalance} but ledger_sum=₦${ledgerSum} (drift=₦${drift.toFixed(4)})`;
        logger.error(`[IntegritySweep] ${message}`);

        await db.collection("health_logs").add({
          timestamp: FieldValue.serverTimestamp(),
          level: "CRITICAL",
          source: "integritySweep",
          check: "wallet_balance_integrity",
          message,
          uid,
          cached_balance: cachedBalance,
          ledger_sum: ledgerSum,
          drift,
        });
      }
    } catch (e) {
      logger.warn(`[IntegritySweep] Skipped UID ${uid}: ${e.message}`);
    }
  }

  // ── 2. Stuck transaction sweep ──────────────────────────────────────────────
  const tenMinsAgo = new Date(Date.now() - 10 * 60 * 1000);

  const stuckSnap = await db.collection("transactions")
    .where("status", "in", ["PENDING", "PROCESSING"])
    .where("created_at", "<=", tenMinsAgo)
    .get();

  for (const txDoc of stuckSnap.docs) {
    const d = txDoc.data();
    totalUnknown++;

    logger.error(`[IntegritySweep] Stuck txn ${txDoc.id}: status=${d.status}, type=${d.type}, uid=${d.user_id}`);

    // Transition stuck txns to UNKNOWN for manual review
    await txDoc.ref.update({
      status: "UNKNOWN",
      error_message: "Automatically transitioned from stuck state by integritySweep",
      updated_at: FieldValue.serverTimestamp(),
    });

    await db.collection("health_logs").add({
      timestamp: FieldValue.serverTimestamp(),
      level: "CRITICAL",
      source: "integritySweep",
      check: "stuck_transaction",
      message: `Stuck txn ${txDoc.id} auto-flagged as UNKNOWN`,
      txn_id: txDoc.id,
      uid: d.user_id,
      type: d.type,
      amount: d.amount,
    });
  }

  // ── 3. UNKNOWN transaction alert ────────────────────────────────────────────
  const unknownSnap = await db.collection("transactions")
    .where("status", "==", "UNKNOWN")
    .get();

  if (unknownSnap.size > 0) {
    logger.error(`[IntegritySweep] ${unknownSnap.size} UNKNOWN transactions require manual reconciliation.`);
    await db.collection("health_logs").add({
      timestamp: FieldValue.serverTimestamp(),
      level: "WARNING",
      source: "integritySweep",
      check: "unknown_transactions_count",
      message: `${unknownSnap.size} UNKNOWN transactions exist. Manual review required.`,
      count: unknownSnap.size,
    });
  }

  logger.info(
    `[IntegritySweep] Done. Audited: ${totalAudited} users, ` +
    `Desync: ${totalDesync}, Stuck→UNKNOWN: ${totalUnknown}`
  );
});
