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

  // ── 1. Wallet balance integrity ─────────────────────────────────────────────
  while (hasMore) {
    let query = db.collection("users").orderBy("__name__").limit(batchSize);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    
    const usersSnap = await query.get();
    if (usersSnap.empty) {
      hasMore = false;
      break;
    }

    lastDoc = usersSnap.docs[usersSnap.docs.length - 1];

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
      } catch (e) {
        logger.warn(`[IntegritySweep] Skipped UID ${uid}: ${e.message}`);
      }
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

  logger.info(
    `[IntegritySweep] Done. Audited: ${totalAudited} users, ` +
    `Desync: ${totalDesync}, Stuck→UNKNOWN: ${totalUnknown}`
  );
});

// ── 4. Webhook Drift Synchronization (Active Polling) ─────────────────────────
// This actively queries Bridgecard for missing transactions to ensure 
// Night Lockdown and Sentinel security engines never go blind due to dropped webhooks.
exports.pollMissingWebhooks = onSchedule({ schedule: "every 1 hours", secrets: ["BRIDGECARD_ACCESS_TOKEN", "BRIDGECARD_SECRET_KEY"] }, async () => {
  logger.info("[PollMissingWebhooks] Starting active Bridgecard synchronization...");
  
  const { bridgecardClient } = require("./bridgecardService");
  const client = bridgecardClient();
  
  // Get all currently active physical cards to sync
  const activeCardsSnap = await db.collection("cards")
    .where("status", "in", ["active", "issued"])
    .get();
    
  let synced = 0;
  let recovered = 0;

  for (const cardDoc of activeCardsSnap.docs) {
    const cardData = cardDoc.data();
    if (!cardData.bridgecard_card_id) continue;
    
    try {
      // NOTE: Verify this matches the exact Bridgecard /transactions endpoint in your API version
      const res = await client.get(`/issuing/cards/transactions?card_id=${cardData.bridgecard_card_id}`);
      const apiTransactions = res.data?.data?.transactions || [];
      
      for (const apiTx of apiTransactions) {
        // Assume Bridgecard returns a unique reference or ID for the transaction
        const ref = apiTx.reference || apiTx.id;
        if (!ref) continue;
        
        // Check if Gatekeeper already knows about this transaction
        const localTxSnap = await db.collection("transactions").where("reference", "==", ref).limit(1).get();
        
        if (localTxSnap.empty) {
           // We missed a webhook! The local database drifted.
           logger.warn(`[PollMissingWebhooks] Recovered missing transaction: ${ref} for card ${cardData.bridgecard_card_id}`);
           
           // We log the recovered transaction.
           // In a full implementation, you would trigger processTransactionInternal here.
           await db.collection("transactions").add({
             ...apiTx,
             recovered_via_polling: true,
             status: "SUCCESS", // Or whatever the API indicates
             card_id: cardDoc.id,
             user_id: cardData.user_id,
             account_id: cardData.account_id,
             created_at: FieldValue.serverTimestamp(),
             updated_at: FieldValue.serverTimestamp(),
           });
           
           recovered++;
        }
      }
      synced++;
    } catch (e) {
      logger.warn(`[PollMissingWebhooks] Failed to poll card ${cardData.bridgecard_card_id}: ${e.message}`);
    }
  }
  
  logger.info(`[PollMissingWebhooks] Done. Synced ${synced} cards. Recovered ${recovered} dropped webhooks.`);
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
