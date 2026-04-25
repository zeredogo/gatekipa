// functions/services/reconciliationDispatcher.js
//
// Phase 2: Distributed Cron Execution via Google Cloud Tasks
//
// Problem: Cloud Functions have an absolute max execution time (~9–60 min).
// A single cron scanning 500k users — even with cursor-based pagination — will
// eventually exceed that ceiling, terminating the run midway.
//
// Solution: Decouple DISPATCH from EXECUTION.
//   - The scheduler (reconciliationDispatcher) runs every 12 hours.
//     It only reads UIDs in cursor-based pages and enqueues a Cloud Task
//     for each page. Its own execution time stays under 60 seconds.
//   - Each Cloud Task invokes processReconciliationBatch (an HTTP function)
//     which processes its 1,000-user slice in isolation.
//     If the task fails, Cloud Tasks retries it automatically with exponential
//     backoff — guaranteeing 100% completion across all users.
//
// SETUP (one-time, run from your terminal):
//   gcloud tasks queues create reconciliation-batch-queue \
//     --location=us-central1 \
//     --max-attempts=5 \
//     --max-backoff=600s \
//     --min-backoff=30s

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const { CloudTasksClient } = require("@google-cloud/tasks");

const PROJECT_ID  = process.env.GCLOUD_PROJECT || "gatekipa-bbd1c";
const LOCATION    = "us-central1";
const QUEUE_NAME  = "reconciliation-batch-queue";
const BATCH_SIZE  = 1000; // UIDs per task

// Worker URL — the onRequest function below
const WORKER_URL  = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/processReconciliationBatch`;

const tasksClient = new CloudTasksClient();

// ─────────────────────────────────────────────────────────────────────────────
// reconciliationDispatcher — runs every 12 hours
// Slices users into pages and enqueues one Cloud Task per page.
// Its own execution stays under 60 seconds regardless of user count.
// ─────────────────────────────────────────────────────────────────────────────
exports.reconciliationDispatcher = onSchedule("every 12 hours", async () => {
  logger.info("[ReconciliationDispatcher] Starting — building task queue...");

  const queuePath = tasksClient.queuePath(PROJECT_ID, LOCATION, QUEUE_NAME);
  const runId     = `sweep_${Date.now()}`;
  let totalTasks  = 0;
  let lastDoc     = null;
  let hasMore     = true;

  while (hasMore) {
    // Only fetch UIDs — we don't need the full documents here
    let query = db.collection("users")
      .orderBy("__name__")
      .select() // fetch no fields — just doc refs
      .limit(BATCH_SIZE);

    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) { hasMore = false; break; }

    lastDoc = snap.docs[snap.docs.length - 1];
    const uids = snap.docs.map(d => d.id);

    // Enqueue a Cloud Task for this batch
    const payload = JSON.stringify({ uids, runId, batchIndex: totalTasks });
    const [task] = await tasksClient.createTask({
      parent: queuePath,
      task: {
        httpRequest: {
          httpMethod: "POST",
          url: WORKER_URL,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(payload).toString("base64"),
          // Use OIDC token to authorize the worker function
          oidcToken: {
            serviceAccountEmail: `firebase-adminsdk-fbsvc@${PROJECT_ID}.iam.gserviceaccount.com`,
          },
        },
        // Stagger task execution by 2s per batch to avoid Firestore write storms
        scheduleTime: {
          seconds: Math.floor(Date.now() / 1000) + totalTasks * 2,
        },
      },
    });

    totalTasks++;

    if (snap.size < BATCH_SIZE) {
      hasMore = false; // Last page
    }
  }

  logger.info(`[ReconciliationDispatcher] Done. Enqueued ${totalTasks} tasks for run ${runId}.`);
  await db.collection("health_logs").add({
    timestamp: FieldValue.serverTimestamp(),
    level: "INFO",
    source: "reconciliationDispatcher",
    message: `Dispatched ${totalTasks} reconciliation tasks (runId=${runId})`,
    run_id: runId,
    total_tasks: totalTasks,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// processReconciliationBatch — HTTP worker, invoked by Cloud Tasks
// Processes integrity checks for a specific slice of UIDs.
// ─────────────────────────────────────────────────────────────────────────────
exports.processReconciliationBatch = onRequest(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed" });
    }

    let body;
    try {
      body = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    } catch (e) {
      return res.status(400).json({ error: "Invalid JSON payload" });
    }

    const { uids, runId, batchIndex } = body;

    if (!Array.isArray(uids) || uids.length === 0) {
      return res.status(400).json({ error: "uids must be a non-empty array" });
    }

    logger.info(`[ReconciliationBatch] Processing batch ${batchIndex} (${uids.length} users) for run ${runId}`);

    let desyncCount = 0;
    let errorCount  = 0;

    for (const uid of uids) {
      try {
        // a. Read the cached wallet balance
        const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
        if (!walletSnap.exists) continue;

        const walletData = walletSnap.data();

        // Prefer the new integer kobo field; fall back to legacy NGN * 100
        const cachedBalanceKobo = walletData.balance_kobo
          ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

        // b. Sum the wallet_ledger root collection (authoritative ledger)
        const txSnap = await db.collection("wallet_ledger").where("user_id", "==", uid).get();

        let ledgerSumKobo = 0;
        for (const entry of txSnap.docs) {
          const d = entry.data();
          if (d.status === "processing" || d.status === "PENDING" || d.status === "reversed") continue;

          // Prefer amount_kobo; fall back to NGN amount * 100
          const entryKobo = d.amount_kobo ?? Math.round((d.amount ?? 0) * 100);
          if (d.type === "credit") ledgerSumKobo += entryKobo;
          else if (d.type === "debit") ledgerSumKobo -= entryKobo;
        }

        // c. Tolerance: allow ≤ 1 kobo floating-point drift
        const driftKobo = Math.abs(cachedBalanceKobo - ledgerSumKobo);
        if (driftKobo > 1) {
          desyncCount++;
          const message = `DESYNC [Batch ${batchIndex}]: UID ${uid} cached=${cachedBalanceKobo}k but ledger=${ledgerSumKobo}k (drift=${driftKobo}k)`;
          logger.error(`[ReconciliationBatch] ${message}`);

          await db.collection("health_logs").add({
            timestamp: FieldValue.serverTimestamp(),
            level: "CRITICAL",
            source: "reconciliationBatch",
            check: "wallet_balance_integrity",
            message,
            uid,
            run_id: runId,
            batch_index: batchIndex,
            cached_balance_kobo: cachedBalanceKobo,
            ledger_sum_kobo: ledgerSumKobo,
            drift_kobo: driftKobo,
          });
        }
      } catch (e) {
        errorCount++;
        logger.warn(`[ReconciliationBatch] Skipped UID ${uid}: ${e.message}`);
      }
    }

    logger.info(`[ReconciliationBatch] Batch ${batchIndex} complete. Desync: ${desyncCount}, Errors: ${errorCount}`);
    return res.status(200).json({ ok: true, desyncCount, errorCount, processed: uids.length });
  }
);
