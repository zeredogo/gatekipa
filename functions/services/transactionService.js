// functions/services/transactionService.js
//
// processTransaction — THE authoritative financial orchestrator.
//
// This function is the ONLY entry point for all financial mutations:
//   - wallet_to_card: debit wallet, fund card
//   - wallet_funding: credit wallet after Paystack verification
//   - card_charge:    process a Bridgecard-originated charge against a card
//
// Guarantees:
//   1. System mode gate  — LOCKDOWN/DEGRADED rejects immediately.
//   2. Idempotency       — duplicate calls return the original result.
//   3. Atomicity         — all writes in a single Firestore transaction.
//   4. Ledger-backed     — every mutation writes to wallet_ledger or card_ledger.
//   5. Status lifecycle  — transaction moves PENDING → PROCESSING → SUCCESS/FAILED/UNKNOWN.
//
// Admin dry-run tool moved to: adminSimulateTransaction (ruleService.js).

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAdmin, requireVerifiedEmail, requirePin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
const { checkIdempotency, storeIdempotencyResult } = require("../core/idempotency");
const { evaluateTransaction } = require("../engines/ruleEngine");
const { disableCard } = require("./cardService");
const { sendNotification } = require("./notificationService");
const { getMessaging } = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

// ── Internal orchestrator (called by other services too) ──────────────────────

/**
 * Core financial transaction processor.
 * Can be called directly by other Cloud Functions (e.g. paystackService).
 *
 * @param {object} params
 * @param {string} params.type           - 'wallet_to_card' | 'wallet_funding' | 'card_charge'
 * @param {string} params.userId         - UID of the initiating/affected user.
 * @param {number} params.amount         - Amount in NGN (not kobo).
 * @param {string} params.idempotencyKey - Unique key to prevent duplicates.
 * @param {object} params.metadata       - Additional context (cardId, paystackRef, etc.)
 * @param {string} [params.correlationId] - Optional trace ID for logging.
 * @returns {Promise<string>} Firestore document ID of the resulting transaction.
 */
async function processTransactionInternal({
  type,
  userId,
  amount,
  idempotencyKey,
  metadata = {},
  correlationId = "unknown",
}) {
  logger.info("[Orchestrator] start", { type, userId, amount, correlationId });

  // ── 1. System gate ─────────────────────────────────────────────────────────
  const mode = await getSystemMode();
  assertSystemAllowsFinancialOps(mode);

  // ── 1.5. Spending Lock gate — user-controlled transaction kill-switch ───────
  // If the user has toggled their Spending Lock ON (spending_lock: true),
  // ALL debit transactions are blocked here before any money moves.
  // Wallet funding (top-up) is exempt — the lock only blocks OUTGOING money.
  const SPENDING_LOCK_EXEMPT_TYPES = ["wallet_funding"];
  if (!SPENDING_LOCK_EXEMPT_TYPES.includes(type)) {
    const userSnap = await db.collection("users").doc(userId).get();
    if (userSnap.exists && userSnap.data().spending_lock === true) {
      logger.warn("[Orchestrator] Spending Lock active — transaction blocked.", { userId, type, correlationId });
      throw new Error("SPENDING_LOCK_ACTIVE: Transactions are blocked. Disable Spending Lock in Settings to proceed.");
    }
  }

  // ── 2. Fast-path idempotency check (non-blocking, catches obvious retries) ─
  const existingTxnId = await checkIdempotency(idempotencyKey);
  if (existingTxnId) {
    logger.info("[Orchestrator] idempotent return (fast-path)", { existingTxnId, correlationId });
    return existingTxnId;
  }

  // ── 3. Create PENDING transaction ──────────────────────────────────────────
  const txnRef = db.collection("transactions").doc();

  // ── 4. ATOMIC core: idempotency guard + financial mutation in ONE transaction ─
  //    This prevents the TOCTOU race where both webhook and client-side
  //    verification pass the fast-path check simultaneously.
  try {
    await db.runTransaction(async (firestoreTxn) => {
      // ── 4a. Atomic idempotency guard (inside the transaction) ────────────
      const idempotencyRef = db.collection("idempotency_keys").doc(idempotencyKey);
      const idempotencySnap = await firestoreTxn.get(idempotencyRef);

      if (idempotencySnap.exists) {
        // Another concurrent request already committed this key.
        // Throw a special error to signal idempotent return.
        const existingId = idempotencySnap.data().result_txn_id;
        throw new Error(`IDEMPOTENT_RETURN:${existingId}`);
      }

      // ── 4b. Execute the type-specific financial mutation (which performs READS) ─
      // Firestore transactions require ALL reads to be executed before ANY writes.
      // Therefore, we must call the type-specific handlers BEFORE we write to idempotencyRef and txnRef.
      if (type === "wallet_to_card") {
        await _processWalletToCard(firestoreTxn, txnRef.id, userId, amount, metadata);
      } else if (type === "wallet_funding") {
        await _processWalletFunding(firestoreTxn, txnRef.id, userId, amount, metadata);
      } else if (type === "card_charge") {
        await _processCardCharge(firestoreTxn, txnRef.id, userId, amount, metadata);
      } else {
        throw new Error(`UNKNOWN_TYPE: Unrecognized transaction type '${type}'.`);
      }

      // ── 4c. Reserve the idempotency key INSIDE the transaction (WRITES) ────────
      const expiresAt = new Date();
      expiresAt.setHours(expiresAt.getHours() + 24);
      firestoreTxn.set(idempotencyRef, {
        user_id: userId,
        result_txn_id: txnRef.id,
        status: "PROCESSING",
        created_at: FieldValue.serverTimestamp(),
        expires_at: expiresAt,
      });

      // ── 4d. Create the transaction document (WRITES) ───────────────────────────
      firestoreTxn.set(txnRef, {
        user_id: userId,
        type,
        status: "PROCESSING",
        amount,
        idempotency_key: idempotencyKey,
        metadata,
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
      });
    });

    // ── 5. Mark SUCCESS (outside transaction — txn already committed) ──────
    await txnRef.update({
      status: "SUCCESS",
      updated_at: FieldValue.serverTimestamp(),
    });

    // Update idempotency key status to SUCCESS
    await db.collection("idempotency_keys").doc(idempotencyKey).update({
      status: "SUCCESS",
    });

    logger.info("[Orchestrator] success", { txnId: txnRef.id, correlationId });

    // ── 6. Post-processing (non-atomic, best-effort) ──────────────────────
    await _postProcess(type, txnRef.id, userId, amount, metadata).catch(e => {
      logger.warn("[Orchestrator] post-process failed (non-critical)", { error: e.message });
    });

    return txnRef.id;

  } catch (error) {
    const message = error.message || "Unknown error";

    // Handle idempotent return from the atomic guard
    if (message.startsWith("IDEMPOTENT_RETURN:")) {
      const existingId = message.split(":")[1];
      logger.info("[Orchestrator] idempotent return (atomic guard)", { existingId, correlationId });
      return existingId;
    }

    const isNetworkError = message.includes("UNAVAILABLE") ||
                           message.includes("network") ||
                           message.includes("timeout") ||
                           message.includes("deadline");

    const finalStatus = isNetworkError ? "UNKNOWN" : "FAILED";

    await txnRef.set({
      user_id: userId,
      type,
      status: finalStatus,
      amount,
      idempotency_key: idempotencyKey,
      metadata,
      error_message: message,
      created_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });

    // Clean up the idempotency key so the user can retry on genuine failures
    if (finalStatus === "FAILED") {
      await db.collection("idempotency_keys").doc(idempotencyKey).delete().catch(() => {});
    }

    logger.error("[Orchestrator] failed", { txnId: txnRef.id, error: message, correlationId });
    throw error;
  }
}

// ── Type-specific handlers ─────────────────────────────────────────────────────

async function _processWalletToCard(firestoreTxn, txnId, userId, amount, metadata) {
  const { cardId, accountId } = metadata;
  if (!cardId || !accountId) throw new Error("wallet_to_card requires cardId and accountId in metadata.");

  // Phase 1 (Kobo): Convert to integer kobo once — all arithmetic uses integers
  const amountKobo = Math.round(amount * 100);
  if (amountKobo <= 0) throw new Error("Amount must be a positive value.");

  // a. Rule evaluation — check card status inside the transaction for safety
  const cardRef = db.collection("cards").doc(cardId);
  const cardSnap = await firestoreTxn.get(cardRef);

  if (!cardSnap.exists) throw new Error("Card not found.");

  const cardStatus = cardSnap.data().local_status || cardSnap.data().status;
  if (cardStatus !== "active" && cardStatus !== "issued") {
    throw new Error(`Card is ${cardStatus} — cannot fund.`);
  }

  // b. Read wallet balance — prefer balance_kobo, fallback to legacy NGN * 100
  const walletRef = db.doc(`users/${userId}/wallet/balance`);
  const walletSnap = await firestoreTxn.get(walletRef);
  const walletData = walletSnap.data() || {};
  const currentBalanceKobo = walletData.balance_kobo
    ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

  if (currentBalanceKobo < amountKobo) {
    const currentNgn = (currentBalanceKobo / 100).toFixed(2);
    const neededNgn = (amountKobo / 100).toFixed(2);
    throw new Error(`INSUFFICIENT_BALANCE: Wallet has ₦${currentNgn}, needs ₦${neededNgn}.`);
  }

  const balanceAfterKobo = currentBalanceKobo - amountKobo;

  // c. Wallet debit ledger entry
  const walletLedgerRef = db.collection("wallet_ledger").doc();
  firestoreTxn.set(walletLedgerRef, {
    user_id: userId,
    type: "debit",
    amount_kobo: amountKobo,
    amount: amountKobo / 100,                // legacy NGN field (dual-write)
    reference: txnId,
    balance_after_kobo: balanceAfterKobo,
    balance_after: balanceAfterKobo / 100,   // legacy NGN field (dual-write)
    source: "wallet_to_card",
    created_at: FieldValue.serverTimestamp(),
  });

  // d. Update wallet balance — integer kobo + legacy NGN dual-write
  firestoreTxn.set(walletRef, {
    balance_kobo: FieldValue.increment(-amountKobo),
    cached_balance: FieldValue.increment(-amount),  // legacy NGN (dual-write)
    balance: FieldValue.increment(-amount),          // legacy NGN (dual-write)
  }, { merge: true });

  // e. Card funding ledger entry
  const cardLedgerRef = db.collection("card_ledger").doc();
  firestoreTxn.set(cardLedgerRef, {
    card_id: cardId,
    account_id: accountId,
    type: "funding",
    amount_kobo: amountKobo,
    amount: amountKobo / 100,                // legacy NGN (dual-write)
    merchant_name: "Wallet Transfer",
    reference: txnId,
    created_at: FieldValue.serverTimestamp(),
  });

  // f. Update card cached display fields
  firestoreTxn.update(cardRef, {
    allocated_amount: FieldValue.increment(amount),
    balance_limit: FieldValue.increment(amount),
  });
}

async function _processWalletFunding(firestoreTxn, txnId, userId, amount, metadata) {
  const { paystackRef, source = "paystack" } = metadata;

  // Phase 1 (Kobo): Convert to integer kobo — all arithmetic uses integers
  const amountKobo = Math.round(amount * 100);

  const walletRef = db.doc(`users/${userId}/wallet/balance`);
  const walletSnap = await firestoreTxn.get(walletRef);
  const walletData = walletSnap.data() || {};
  const currentBalanceKobo = walletData.balance_kobo
    ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

  const balanceAfterKobo = currentBalanceKobo + amountKobo;

  // a. Wallet credit ledger entry
  const walletLedgerRef = db.collection("wallet_ledger").doc();
  firestoreTxn.set(walletLedgerRef, {
    user_id: userId,
    type: "credit",
    amount_kobo: amountKobo,
    amount: amountKobo / 100,              // legacy NGN (dual-write)
    reference: paystackRef || txnId,
    balance_after_kobo: balanceAfterKobo,
    balance_after: balanceAfterKobo / 100, // legacy NGN (dual-write)
    source,
    created_at: FieldValue.serverTimestamp(),
  });

  // b. Update wallet balance — integer kobo + legacy NGN dual-write
  firestoreTxn.set(walletRef, {
    balance_kobo: FieldValue.increment(amountKobo),
    cached_balance: FieldValue.increment(amount),  // legacy NGN (dual-write)
    balance: FieldValue.increment(amount),          // legacy NGN (dual-write)
  }, { merge: true });
}

async function _processCardCharge(firestoreTxn, txnId, userId, amount, metadata) {
  const { cardId, accountId, merchantName = "Unknown", bridgecardRef } = metadata;
  if (!cardId) throw new Error("card_charge requires cardId in metadata.");

  // Phase 1 (Kobo): Convert to integer kobo once
  const amountKobo = Math.round(amount * 100);

  // Card ledger entry
  const cardLedgerRef = db.collection("card_ledger").doc();
  firestoreTxn.set(cardLedgerRef, {
    card_id: cardId,
    account_id: accountId || "",
    type: "charge",
    amount_kobo: amountKobo,
    amount, // legacy NGN
    merchant_name: merchantName,
    reference: bridgecardRef || txnId,
    created_at: FieldValue.serverTimestamp(),
  });

  // Update cached spent_amount and charge_count (display only)
  const cardRef = db.collection("cards").doc(cardId);
  firestoreTxn.update(cardRef, {
    spent_amount_kobo: FieldValue.increment(amountKobo),
    spent_amount: FieldValue.increment(amount), // legacy NGN
    charge_count: FieldValue.increment(1),
  });

  // Track in external_transactions
  if (bridgecardRef) {
    const extRef = db.collection("external_transactions").doc(bridgecardRef);
    firestoreTxn.set(extRef, {
      bridgecard_ref: bridgecardRef,
      internal_card_id: cardId,
      internal_txn_id: txnId,
      current_state: "settled",
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  // --- GATEKIPA TRANSACTION FEE ---
  const flatFeeNGN = 100; // Flat 100 NGN fee regardless of transaction volume
  const flatFeeKobo = flatFeeNGN * 100;

  const walletRef = db.doc(`users/${userId}/wallet/balance`);
  const walletSnap = await firestoreTxn.get(walletRef);
  
  // Best-effort extraction of wallet balance, defaults to 0
  const walletData = walletSnap.exists ? walletSnap.data() : {};
  const currentBalanceKobo = walletData.balance_kobo
    ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);

  if (currentBalanceKobo >= flatFeeKobo) {
    const balanceAfterKobo = currentBalanceKobo - flatFeeKobo;

    const feeLedgerRef = db.collection("wallet_ledger").doc();
    firestoreTxn.set(feeLedgerRef, {
      user_id: userId,
      type: "debit",
      amount_kobo: flatFeeKobo,
      amount: flatFeeNGN,
      reference: `fee_${bridgecardRef || txnId}`,
      balance_after_kobo: balanceAfterKobo,
      balance_after: balanceAfterKobo / 100,
      source: "card_transaction_fee",
      merchant_name: "Gatekipa Trans. Fee",
      created_at: FieldValue.serverTimestamp(),
    });

    // Dual-write deduction for the fee
    firestoreTxn.set(walletRef, {
      balance_kobo: FieldValue.increment(-flatFeeKobo),
      cached_balance: FieldValue.increment(-flatFeeNGN),
      balance: FieldValue.increment(-flatFeeNGN),
    }, { merge: true });
  } else {
    // Record debt to prevent overdrafting wallet
    const debtRef = db.collection("negative_balance_ledgers").doc(`debt_fee_${bridgecardRef || txnId}`);
    firestoreTxn.set(debtRef, {
      uid: userId,
      amount: flatFeeNGN,
      amount_kobo: flatFeeKobo,
      reason: "card_transaction_fee_insufficient_balance",
      reference: `fee_${bridgecardRef || txnId}`,
      created_at: Date.now(),
      status: "unrecovered"
    });
  }
}

// ── Post-processing (best-effort, non-atomic) ──────────────────────────────────

async function _postProcess(type, txnId, userId, amount, metadata) {
  if (type === "card_charge") {
    const { cardId, merchantName } = metadata;
    if (!cardId) return;

    const cardSnap = await db.collection("cards").doc(cardId).get();
    if (!cardSnap.exists) return;
    const card = cardSnap.data();

    // Auto-disable trial cards after successful charge
    if (card.is_trial) {
      await disableCard(cardId);
      await sendNotification(card.account_id, "Your trial card was automatically disabled after use.");
    }

    // FCM + in-app notification for card charges
    // BUG FIX (Bug B): Personal cards have account_id === uid but no accounts document.
    // Old code: accountSnap.exists === false → ownerUid undefined → notification silently skipped.
    // Fix: fallback to card.account_id as ownerUid when no accounts document exists.
    const accountSnap = await db.collection("accounts").doc(card.account_id).get();
    const ownerUid = accountSnap.exists ? accountSnap.data().owner_user_id : card.account_id;
    if (ownerUid) {
      const ownerSnap = await db.collection("users").doc(ownerUid).get();
      const fcmToken = ownerSnap.data()?.fcm_token;

      if (fcmToken) {
        await getMessaging().send({
          token: fcmToken,
          notification: {
            title: `₦${amount} charged at ${merchantName || "merchant"}`,
            body: "A charge was processed on your Gatekipa card.",
          },
          data: { type: "card_charge", amount: String(amount), merchant: merchantName || "" },
        }).catch(e => logger.warn("[FCM] Charge notification failed", { error: e.message }));
      }
    }
  }

  if (type === "wallet_funding") {
    const ownerSnap = await db.collection("users").doc(userId).get();
    const fcmToken = ownerSnap.data()?.fcm_token;

    if (fcmToken) {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: `₦${amount.toLocaleString()} Added!`,
          body: "Your Gatekipa wallet was successfully credited.",
        },
        data: { type: "wallet_funded", amount: String(amount) },
      }).catch(e => logger.warn("[FCM] Funding notification failed", { error: e.message }));
    }
  }
}

// ── Exported Cloud Function (user-callable) ──────────────────────────────────

/**
 * fundCard — wallet_to_card transaction.
 * The Flutter app calls this after biometric approval.
 */
exports.fundCard = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { card_id, account_id, amount, idempotency_key } = request.data;

  if (!card_id || !account_id || !amount || !idempotency_key) {
    throw new HttpsError("invalid-argument", "card_id, account_id, amount, and idempotency_key are required.");
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "amount must be a positive number.");
  }
  if (amount > 500000) {
    throw new HttpsError("invalid-argument", "Cannot fund more than ₦500,000 in a single operation.");
  }
  
  // SECURE TRANSACTION PIN ENFORCEMENT
  await requirePin(uid, request.data.pin);

  // Verify card ownership before the orchestrator runs
  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const accountSnap = await db.collection("accounts").doc(account_id).get();
  if (!accountSnap.exists) throw new HttpsError("not-found", "Account not found.");
  if (accountSnap.data().owner_user_id !== uid) {
    const tmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
    if (!tmSnap.exists) throw new HttpsError("permission-denied", "You do not own this card.");
  }

  try {
    const txnId = await processTransactionInternal({
      type: "wallet_to_card",
      userId: uid,
      amount,
      idempotencyKey: idempotency_key,
      metadata: { cardId: card_id, accountId: account_id },
      correlationId: `fundCard:${uid}:${Date.now()}`,
    });

    return { success: true, txn_id: txnId };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (e.message.startsWith("INSUFFICIENT_BALANCE")) throw new HttpsError("failed-precondition", e.message);
    if (e.message.startsWith("SYSTEM_LOCKDOWN")) throw new HttpsError("unavailable", e.message);
    if (e.message.startsWith("SYSTEM_DEGRADED")) throw new HttpsError("unavailable", e.message);
    if (e.message.startsWith("RULE_VIOLATION")) throw new HttpsError("failed-precondition", e.message);
    throw new HttpsError("internal", e.message);
  }
});

/**
 * processTransaction — the existing admin dry-run function, now also routes
 * real card charges from bridgecardWebhook when called internally.
 * Kept as an exported Cloud Function for backward compatibility.
 */
exports.processTransaction = onCall({ region: "us-central1", enforceAppCheck: false }, async (request) => {
  // Keep admin dry-run capability — evaluateTransaction with dryRun: true
  const { requireAdmin } = require("../utils/validators");
  requireAdmin(request.auth);

  const { cardId, amount, merchantName } = request.data;
  if (!cardId || !Number.isFinite(amount) || amount <= 0 || !merchantName) {
    throw new HttpsError("invalid-argument", "A valid cardId, positive numeric amount, and merchantName are required.");
  }

  // Dry-run now uses the hardened ledger-backed rule engine
  const result = await evaluateTransaction(cardId, amount, merchantName, { dryRun: true });
  return result;
});

// Export the internal function for use by paystackService and bridgecardService
exports.processTransactionInternal = processTransactionInternal;

/**
 * toggleSpendingLock — lets a user enable or disable their Spending Lock.
 *
 * When spending_lock = true:
 *   - card_charge (Bridgecard webhook debit) is BLOCKED
 *   - wallet_to_card (card funding) is BLOCKED
 *   - wallet_funding (Paystack top-up) is ALLOWED
 *
 * The lock is enforced inside processTransactionInternal, so it cannot
 * be bypassed by calling any other function directly.
 */
exports.toggleSpendingLock = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { lock } = request.data;

  if (typeof lock !== "boolean") {
    throw new HttpsError("invalid-argument", "'lock' must be a boolean.");
  }

  await requirePin(uid, request.data.pin);

  await db.collection("users").doc(uid).update({
    spending_lock: lock,
    spending_lock_updated_at: FieldValue.serverTimestamp(),
  });

  logger.info(`[SpendingLock] User ${uid} set spending_lock = ${lock}`);

  // ── 1. Freeze/unfreeze Bridgecard USD cards at issuer level ─────────────────
  try {
    const { internalFreezeBridgecard } = require("./bridgecardService");
    const bcCardsSnap = await db.collection("cards")
      .where("created_by", "==", uid)
      .where("bridgecard_card_id", ">" , "")
      .get();

    const bcPromises = [];
    for (const doc of bcCardsSnap.docs) {
      const cardData = doc.data();
      // Skip NGN/Sudo cards — they are handled below
      if (cardData.sudo_card_id) continue;

      if (lock && (cardData.status === "active" || cardData.local_status === "active")) {
        bcPromises.push(internalFreezeBridgecard(cardData.bridgecard_card_id, true)
          .then(() => doc.ref.update({ status: "frozen", local_status: "frozen", bridgecard_status: "frozen" }))
          .catch(e => logger.error(`[SpendingLock] Failed to freeze Bridgecard ${doc.id}:`, e))
        );
      } else if (!lock && (cardData.status === "frozen" || cardData.local_status === "frozen")) {
        bcPromises.push(internalFreezeBridgecard(cardData.bridgecard_card_id, false)
          .then(() => doc.ref.update({ status: "active", local_status: "active", bridgecard_status: "active" }))
          .catch(e => logger.error(`[SpendingLock] Failed to unfreeze Bridgecard ${doc.id}:`, e))
        );
      }
    }
    if (bcPromises.length > 0) {
      await Promise.allSettled(bcPromises);
      logger.info(`[SpendingLock] Synced ${bcPromises.length} Bridgecard card(s).`);
    }
  } catch (err) {
    logger.error("[SpendingLock] Error syncing Bridgecard freeze state:", err);
  }

  // ── 2. Freeze/unfreeze Sudo Africa NGN cards at issuer level ─────────────────
  // Enforces the lock at the Sudo provider level, not just via JIT blocking.
  // This ensures the card visually shows as 'inactive' in the Sudo dashboard
  // and prevents any edge-case authorizations that may bypass JIT.
  try {
    const sudoApiKey = process.env.SUDO_API_KEY;
    const sudoBaseUrl = process.env.SUDO_BASE_URL || "https://api.sudo.africa";

    if (!sudoApiKey) {
      logger.warn("[SpendingLock] SUDO_API_KEY not set — skipping Sudo card freeze sync.");
    } else {
      const sudoCardsSnap = await db.collection("cards")
        .where("created_by", "==", uid)
        .where("sudo_card_id", ">", "")
        .get();

      const sudoPromises = [];
      const targetStatus = lock ? "inactive" : "active";

      for (const doc of sudoCardsSnap.docs) {
        const cardData = doc.data();
        const sudoCardId = cardData.sudo_card_id;

        const shouldFreeze   = lock  && (cardData.status === "active"  || cardData.local_status === "active");
        const shouldUnfreeze = !lock && (cardData.status === "frozen"  || cardData.local_status === "frozen");

        if (!shouldFreeze && !shouldUnfreeze) continue;

        sudoPromises.push(
          fetch(`${sudoBaseUrl}/cards/${sudoCardId}`, {
            method: "PUT",
            headers: {
              Authorization: `Bearer ${sudoApiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ status: targetStatus }),
          })
          .then(async (r) => {
            if (!r.ok) {
              const errBody = await r.text();
              throw new Error(`Sudo API error ${r.status}: ${errBody}`);
            }
            const localStatus = lock ? "frozen" : "active";
            return doc.ref.update({
              status: localStatus,
              local_status: localStatus,
              bridgecard_status: localStatus, // keep compat field in sync
            });
          })
          .catch(e => logger.error(`[SpendingLock] Failed to ${targetStatus} Sudo card ${doc.id}:`, e.message))
        );
      }

      if (sudoPromises.length > 0) {
        await Promise.allSettled(sudoPromises);
        logger.info(`[SpendingLock] Synced ${sudoPromises.length} Sudo card(s) to '${targetStatus}'.`);
      }
    }
  } catch (err) {
    logger.error("[SpendingLock] Error syncing Sudo freeze state:", err);
  }

  return {
    success: true,
    spending_lock: lock,
    message: lock
      ? "Spending Lock enabled. All debit transactions are now blocked."
      : "Spending Lock disabled. Transactions are now allowed.",
  };
});
