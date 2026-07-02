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

  let totalAudited = 0;
  let totalDesync = 0;
  let totalUnknown = 0;
  let lastDoc = null;
  const batchSize = 500;
  let hasMore = true;

  // ── 1. Wallet balance integrity (Incremental active users audit) ───────────
  const sweepWindowLimit = new Date(Date.now() - 13 * 60 * 60 * 1000); // 13 hours ago (12h sweep + 1h buffer)
  try {
    const activeEntriesSnap = await db.collection("wallet_ledger")
      .where("created_at", ">=", sweepWindowLimit)
      .get();

    const activeUserIds = new Set();
    for (const doc of activeEntriesSnap.docs) {
      const data = doc.data();
      if (data.user_id) {
        activeUserIds.add(data.user_id);
      }
    }

    logger.info(`[IntegritySweep] Found ${activeUserIds.size} active users in the sweep window.`);

    for (const uid of activeUserIds) {
      totalAudited++;

      try {
        // a. Cached balance from wallet doc
        const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
        if (!walletSnap.exists) continue;

        const cachedBalance = walletSnap.data().cached_balance
          ?? walletSnap.data().balance
          ?? 0;

        // b. Authoritative sum from wallet_ledger
        const ledgerSnap = await db.collection("wallet_ledger").where("user_id", "==", uid).get();

        let ledgerSum = 0;
        for (const entry of ledgerSnap.docs) {
          const d = entry.data();
          // Skip in-flight entries (they'll resolve or fail within seconds)
          if (d.status === "processing" || d.status === "PENDING" || d.status === "reversed") continue;
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

        // d. Provider balance drift check (Sudo Africa balance cross-reference)
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.data() || {};
        const sudoAccountId = userData.sudo_account_id;
        
        if (sudoAccountId) {
          try {
            const { sudoClient } = require("./sudoService");
            const client = sudoClient();
            const sudoRes = await client.get(`/accounts/${sudoAccountId}/balance`);
            const providerBalanceKobo = sudoRes.data?.data?.availableBalance || sudoRes.data?.data?.balance || 0;
            const providerBalance = providerBalanceKobo / 100;
            
            // Compare provider balance with local cached balance
            const balanceDiff = Math.abs(cachedBalance - providerBalance);
            if (balanceDiff > 1.0) { // drift threshold of ₦1.00
              const driftMsg = `PROVIDER DRIFT: UID ${uid} has local cached balance of ₦${cachedBalance} but Sudo provider account balance is ₦${providerBalance} (diff=₦${balanceDiff.toFixed(2)})`;
              logger.warn(`[IntegritySweep] ${driftMsg}`);
              
              await db.collection("health_logs").add({
                timestamp: FieldValue.serverTimestamp(),
                level: "WARNING",
                source: "integritySweep",
                check: "provider_balance_drift",
                message: driftMsg,
                uid,
                cached_balance: cachedBalance,
                provider_balance: providerBalance,
                diff: balanceDiff,
              });
            }
          } catch (sudoErr) {
            logger.error(`[IntegritySweep] Failed to query Sudo balance for UID ${uid}:`, sudoErr.message);
          }
        }
      } catch (e) {
        logger.warn(`[IntegritySweep] Skipped UID ${uid}: ${e.message}`);
      }
    }
  } catch (err) {
    logger.error(`[IntegritySweep] Failed to query active ledger entries: ${err.message}`);
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

  // ── 2.5. Stuck funding requests ───────────────────────────────────────────
  const fifteenMinsAgo = Date.now() - 15 * 60 * 1000;
  
  const stuckFundingSnap = await db.collection("card_funding_requests")
    .where("status", "==", "processing")
    .where("created_at", "<=", fifteenMinsAgo)
    .get();

  for (const fundDoc of stuckFundingSnap.docs) {
    const d = fundDoc.data();
    logger.error(`[IntegritySweep] Stuck funding req ${fundDoc.id}: status=${d.status}, uid=${d.uid}`);

    // Transition stuck funding to UNKNOWN for manual review
    await fundDoc.ref.update({
      status: "UNKNOWN",
      error_message: "Automatically transitioned from stuck state by integritySweep",
      updated_at: Date.now(),
    });

    await db.collection("health_logs").add({
      timestamp: FieldValue.serverTimestamp(),
      level: "CRITICAL",
      source: "integritySweep",
      check: "stuck_funding_request",
      message: `Stuck funding req ${fundDoc.id} auto-flagged as UNKNOWN`,
      req_id: fundDoc.id,
      uid: d.uid,
      amount: d.amount_ngn,
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

  // ── 4. Webhook & Idempotency Pruning (Retention Cleanup) ───────────────────
  try {
    const pruneThreshold = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000); // 30 days
    
    // Prune webhook_events
    const oldEventsSnap = await db.collection("webhook_events")
      .where("received_at", "<", pruneThreshold)
      .limit(100)
      .get();
    
    if (!oldEventsSnap.empty) {
      const batch = db.batch();
      oldEventsSnap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      logger.info(`[IntegritySweep] Pruned ${oldEventsSnap.size} stale webhook events.`);
    }

    // Prune idempotency_keys
    const oldIdempotencySnap = await db.collection("idempotency_keys")
      .where("created_at", "<", pruneThreshold)
      .limit(100)
      .get();
    
    if (!oldIdempotencySnap.empty) {
      const batch = db.batch();
      oldIdempotencySnap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      logger.info(`[IntegritySweep] Pruned ${oldIdempotencySnap.size} stale idempotency keys.`);
    }
  } catch (pruneErr) {
    logger.error("[IntegritySweep] Error pruning stale data:", pruneErr);
  }

  logger.info(
    `[IntegritySweep] Done. Audited: ${totalAudited} users, ` +
    `Desync: ${totalDesync}, Stuck→UNKNOWN: ${totalUnknown}`
  );
});

// ── 4. Webhook Drift Synchronization (Active Polling) ─────────────────────────
// This actively queries for missing transactions to ensure 
// Night Lockdown and Sentinel security engines never go blind due to dropped webhooks.
exports.pollMissingWebhooks = onSchedule({ schedule: "every 1 hours", secrets: ["SUDO_API_KEY"] }, async () => {
  logger.info("[PollMissingWebhooks] Starting active Sudo synchronization...");
  try {
    const { sudoClient } = require("./sudoService");
    const client = sudoClient();
    
    // Query last 50 transactions across the platform from Sudo
    const response = await client.get("/cards/transactions", { params: { limit: 50 } });
    const sudoTransactions = response.data?.data || [];
    logger.info(`[PollMissingWebhooks] Fetched ${sudoTransactions.length} transactions from Sudo API.`);

    const { processTransactionInternal } = require("./transactionService");

    for (const tx of sudoTransactions) {
      const txId = tx._id || tx.id;
      if (!txId) continue;

      // Check if this transaction exists in our db
      const txDoc = await db.collection("transactions").doc(txId).get();
      if (!txDoc.exists) {
        logger.warn(`[PollMissingWebhooks] Found missing transaction: ${txId}. Re-processing now.`);
        
        const cardId = tx.card?._id || tx.card;
        const amount = tx.amount;
        const merchantName = tx.merchant?.name || "Unknown Merchant";
        
        const options = {
          merchantCountry: tx.merchant?.country || "US",
          transactionCurrency: tx.currency || "USD",
          sudoTransactionId: txId,
          dryRun: false
        };

        try {
          const result = await processTransactionInternal(cardId, amount, merchantName, options);
          logger.info(`[PollMissingWebhooks] Automatically processed transaction ${txId}. Approved: ${result.approved}`);
        } catch (err) {
          logger.error(`[PollMissingWebhooks] Error processing transaction ${txId}:`, err);
        }
      }
    }
  } catch (err) {
    logger.error("[PollMissingWebhooks] Reconciliation poll failed:", err);
  }
  logger.info("[PollMissingWebhooks] Done.");
});

// ── 5. System Stats Aggregation ──────────────────────────────────────────────
exports.aggregateSystemStats = onSchedule("every 1 hours", async () => {
  logger.info("[AggregateSystemStats] Starting periodic stats aggregation...");
  
  let lastDoc = null;
  const batchSize = 500;
  let hasMore = true;
  let totalBalance = 0;
  
  while (hasMore) {
    let query = db.collection("users").orderBy("__name__").limit(batchSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    
    const usersSnap = await query.get();
    if (usersSnap.empty) {
      hasMore = false;
      break;
    }
    
    lastDoc = usersSnap.docs[usersSnap.docs.length - 1];

    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      try {
        const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
        if (!walletSnap.exists) continue;
        
        const cachedBalance = walletSnap.data().cached_balance
          ?? walletSnap.data().balance
          ?? 0;
        
        totalBalance += cachedBalance;
      } catch (e) {
        logger.warn(`[AggregateSystemStats] Skipped UID ${uid}: ${e.message}`);
      }
    }
  }
  
  await db.doc("system_stats/summary").set({
    total_balance: totalBalance,
    updated_at: FieldValue.serverTimestamp()
  }, { merge: true });
  
  logger.info(`[AggregateSystemStats] Done. Total balance: ₦${totalBalance}`);
});
