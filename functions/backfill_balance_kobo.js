/**
 * backfill_balance_kobo.js
 *
 * One-time migration script: reads each user's legacy `balance` / `cached_balance`
 * field (stored as NGN float) and writes the authoritative integer `balance_kobo`
 * field to their wallet document.
 *
 * Safe to run multiple times — uses set({ merge: true }) so re-runs are idempotent.
 * Run from functions/ directory: node backfill_balance_kobo.js
 */
const admin = require("firebase-admin");
const serviceAccount = require("./gatekipa.json");

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

async function run() {
  console.log("=================================================");
  console.log("  BALANCE_KOBO BACKFILL — Phase 1 Kobo Migration");
  console.log("=================================================\n");

  let totalMigrated = 0;
  let totalSkipped = 0;
  let totalErrors = 0;
  let lastDoc = null;
  let hasMore = true;
  const BATCH_SIZE = 500;

  while (hasMore) {
    let query = db.collection("users").orderBy("__name__").limit(BATCH_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) { hasMore = false; break; }
    lastDoc = snap.docs[snap.docs.length - 1];

    const batch = db.batch();
    let batchCount = 0;

    for (const userDoc of snap.docs) {
      const uid = userDoc.id;
      try {
        const walletRef = db.doc(`users/${uid}/wallet/balance`);
        const walletSnap = await walletRef.get();

        if (!walletSnap.exists) {
          totalSkipped++;
          continue;
        }

        const data = walletSnap.data();

        // Already migrated — skip to avoid clobbering
        if (data.balance_kobo !== undefined) {
          totalSkipped++;
          continue;
        }

        const legacyBalance = data.cached_balance ?? data.balance ?? 0;
        const balanceKobo = Math.round(legacyBalance * 100);

        batch.set(walletRef, { balance_kobo: balanceKobo }, { merge: true });
        batchCount++;
        totalMigrated++;

        if (batchCount % 100 === 0) {
          console.log(`  ↳ Batching UID ${uid} (₦${legacyBalance} → ${balanceKobo} kobo)`);
        }
      } catch (e) {
        console.error(`  ✗ Failed for UID ${uid}: ${e.message}`);
        totalErrors++;
      }
    }

    if (batchCount > 0) await batch.commit();
    console.log(`Batch complete. Migrated ${batchCount} wallets in this page.`);
  }

  console.log(`\n✅ Backfill complete.`);
  console.log(`   Migrated : ${totalMigrated}`);
  console.log(`   Skipped  : ${totalSkipped} (already migrated or no wallet)`);
  console.log(`   Errors   : ${totalErrors}`);
  process.exit(0);
}

run().catch(e => { console.error("Fatal:", e); process.exit(1); });
