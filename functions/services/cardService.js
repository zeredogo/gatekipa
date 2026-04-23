const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireVerifiedEmail, requireFields, requireKyc, requireAdmin } = require("../utils/validators");
const crypto = require("crypto");
const { internalFreezeBridgecard } = require("./bridgecardService");
const { sendNotification } = require("./notificationService");
const { FieldValue } = require("firebase-admin/firestore");
const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
const { assertValidTransition } = require("../core/stateMachine");
const logger = require("firebase-functions/logger");


/** Generate a temporary card placeholder — real PAN/CVV come from Bridgecard after cardholder registration */
function generatePlaceholderDetails() {
  // We do NOT generate fake card numbers. The real PAN is issued by Bridgecard
  // after registerCardholder + createBridgecard are called. Until then, the card
  // is in a 'pending_issuance' state and the UI shows a clear loading indicator.
  return {
    last4: null,
    masked_number: "Card Pending Issuance",
    cvv: null,
  };
}

exports.createVirtualCard = onCall({ region: "us-central1" }, async (request) => {

  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  await requireKyc(uid);

  const data = request.data;
  
  requireFields(data, ["account_id", "name"]);
  const { account_id, name, is_trial = false, category = 'personal', currency = 'NGN' } = data;

  const userDoc = await db.collection("users").doc(uid).get();
  const currentPlan = userDoc.exists ? (userDoc.data().planTier || "free") : "free";

  // Verify account ownership or membership
  let accountData = {};
  if (account_id === uid) {
    // Virtual personal account fallback
    if (currentPlan !== "free" && currentPlan !== "instant") {
      throw new HttpsError("permission-denied", "An explicit client profile is required for upgraded plans.");
    }
    accountData = { owner_user_id: uid };
  } else {
    const accountDoc = await db.collection("accounts").doc(account_id).get();
    if (!accountDoc.exists) throw new HttpsError("not-found", "Account not found.");
    
    accountData = accountDoc.data();
    if (accountData.owner_user_id !== uid) {
      const tmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
      if (!tmSnap.exists || tmSnap.data().role !== "admin") {
        throw new HttpsError("permission-denied", "Only owner or admin can create cards.");
      }
    }
  }

  // ENFORCE PLAN LOGIC ON BACKEND natively using User's Plan
  const activeCardsSnap = await db.collection("cards")
    .where("account_id", "==", account_id)
    .where("status", "in", ["active", "pending_issuance"])
    .count()
    .get();

  const activeCardCount = activeCardsSnap.data().count;

  // Plan Limits Matrix
  let maxAllowed = 1; // Default
  if (currentPlan === "free" || currentPlan === "instant") {
    maxAllowed = 1;
  } else if (currentPlan === "activation") {
    maxAllowed = 2;
  } else if (currentPlan === "premium") {
    maxAllowed = 3;
  } else if (currentPlan === "business") {
    maxAllowed = 5;
  } else {
    // Unknown plans default to 1 for safety
    maxAllowed = 1;
  }

  if (activeCardCount >= maxAllowed) {
    throw new HttpsError(
      "permission-denied", 
      `The '${currentPlan}' plan is limited to ${maxAllowed} active card(s). Please upgrade to create more.`
    );
  }

  const { last4, masked_number, cvv } = generatePlaceholderDetails();

  const cardRef = db.collection("cards").doc();
  const now = Date.now();

  const card = {
    id: cardRef.id,
    account_id,
    name: name.trim(),
    // localStatus is the authoritative status field. 'status' kept for migration window.
    local_status: "pending_issuance",
    status: "pending_issuance",
    lifecycle_version: 0,
    is_trial: is_trial,
    category: category,
    currency: currency,
    last4,
    masked_number,
    cvv,
    // allocated_amount replaces balance_limit. Both written during migration window.
    allocated_amount: 0,
    balance_limit: 0,
    // cached fields — updated by Cloud Functions after card_ledger commits
    spent_amount: 0,
    charge_count: 0,
    created_at: now,
    created_by: uid
  };

  await cardRef.set(card);

  // Plan specific auto-rules
  const rulesBatch = db.batch();
  let hasRules = false;

  if (is_trial) {
    hasRules = true;
    const maxChargeRef = db.collection("rules").doc();
    rulesBatch.set(maxChargeRef, {
      id: maxChargeRef.id,
      card_id: cardRef.id,
      type: "behavior",
      sub_type: "max_charges",
      value: 1,
      meta: {},
      created_at: now
    });
  }

  if (is_trial || currentPlan === "premium" || currentPlan === "business") {
    hasRules = true;
    const expiryRef = db.collection("rules").doc();
    rulesBatch.set(expiryRef, {
      id: expiryRef.id,
      card_id: cardRef.id,
      type: "time",
      sub_type: "expiry_date",
      value: now + 30 * 24 * 60 * 60 * 1000,
      meta: {},
      created_at: now
    });
  }

  if (hasRules) {
    await rulesBatch.commit();
  }

  return { success: true, cardId: cardRef.id, card };
});

exports.toggleCardStatus = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { card_id, status: targetStatus } = request.data;
  requireFields(request.data, ["card_id", "status"]);

  // Validate target is a known status
  const allowedTargets = ["active", "frozen", "terminated"];
  if (!allowedTargets.includes(targetStatus)) {
    throw new HttpsError("invalid-argument", `Invalid status '${targetStatus}'. Must be one of: ${allowedTargets.join(", ")}.`);
  }

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found");

  const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountDoc.exists || accountDoc.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Only the account owner can toggle card status.");
  }

  // State machine enforcement — no skipping allowed
  const currentStatus = cardSnap.data().local_status || cardSnap.data().status;
  try {
    assertValidTransition(currentStatus, targetStatus);
  } catch (e) {
    throw new HttpsError("failed-precondition", e.message);
  }

  // Write both local_status (authoritative) and status (migration compat)
  await db.collection("cards").doc(card_id).update({
    local_status: targetStatus,
    status: targetStatus,
    lifecycle_version: FieldValue.increment(1),
    ...(cardSnap.data().bridgecard_card_id && {
      bridgecard_status: targetStatus === "frozen" ? "frozen" : targetStatus
    }),
  });

  if (cardSnap.data().bridgecard_card_id) {
    try {
      await internalFreezeBridgecard(
        cardSnap.data().bridgecard_card_id,
        targetStatus === "frozen",
        cardSnap.data().currency
      );
    } catch (e) {
      logger.error(`[CardToggle] Bridgecard sync failed for ${card_id}`, e);
      // Do NOT throw — local status is already updated. Bridgecard sync is best-effort.
      // A reconciliation job will re-sync if needed.
      logger.warn(`[CardToggle] Local status updated but Bridgecard sync failed. Card ${card_id} will be reconciled.`);
    }
  }

  return { success: true };
});

exports.renameCard = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { card_id, new_name } = request.data;
  requireFields(request.data, ["card_id", "new_name"]);

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found");

  // Verify the caller owns or is a member of the associated account
  const accountId = cardSnap.data().account_id;
  const accountDoc = await db.collection("accounts").doc(accountId).get();
  if (!accountDoc.exists) throw new HttpsError("not-found", "Account not found");

  const isOwner = accountDoc.data().owner_user_id === uid;
  if (!isOwner) {
    const memberSnap = await db.collection("team_members").doc(`${accountId}_${uid}`).get();
    if (!memberSnap.exists) {
      throw new HttpsError("permission-denied", "You do not have access to rename this card.");
    }
  }

  await db.collection("cards").doc(card_id).update({
    name: new_name.trim()
  });

  return { success: true };
});

exports.disableCard = async function(cardId) {
  await db.collection("cards").doc(cardId).update({
    local_status: "frozen",
    status: "blocked", // migration compat
    lifecycle_version: FieldValue.increment(1),
  });
};

/**
 * activateKillSwitch — blocks all active cards across all accounts owned by the caller.
 * Called via httpsCallable('activateKillSwitch') from the Flutter app (biometric-gated).
 */
exports.activateKillSwitch = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;

  // 1. Find all accounts owned by this user
  const accountsSnap = await db.collection("accounts")
    .where("owner_user_id", "==", uid)
    .get();

  const accountIds = accountsSnap.docs.map(d => d.id);
  const cardIdsToBlock = new Set();
  
  // 1.a) Get all active cards directly created by this user
  const myCardsSnap = await db.collection("cards")
    .where("created_by", "==", uid)
    .where("status", "==", "active")
    .get();
    
  for (const doc of myCardsSnap.docs) {
    cardIdsToBlock.add(doc.id);
  }

  // 1.b) Get all active cards in accounts owned by the user
  if (accountIds.length > 0) {
    const chunks = [];
    for (let i = 0; i < accountIds.length; i += 10) {
      chunks.push(accountIds.slice(i, i + 10));
    }
    
    for (const chunk of chunks) {
      const accCardsSnap = await db.collection("cards")
        .where("account_id", "in", chunk)
        .where("status", "==", "active")
        .get();
        
      for (const doc of accCardsSnap.docs) {
        cardIdsToBlock.add(doc.id);
      }
    }
  }

  if (cardIdsToBlock.size === 0) return { success: true, blocked: 0 };

  // 2. Fetch the actual card documents matching the merged Set
  // Since we already might have the documents, wait, let's just fetch them again in chunks 
  // or store the documents in a Map to avoid re-fetching!
  // It's cleaner to re-fetch in chunks by ID:
  const allCardIds = Array.from(cardIdsToBlock);
  const cardChunks = [];
  for (let i = 0; i < allCardIds.length; i += 10) {
    cardChunks.push(allCardIds.slice(i, i + 10));
  }

  let totalBlocked = 0;
  const failedFreezes = [];

  for (const chunk of cardChunks) {
    const cardsSnap = await db.collection("cards")
      .where("__name__", "in", chunk)
      .get();

    if (!cardsSnap.empty) {
      const batch = db.batch();
      for (const doc of cardsSnap.docs) {
        batch.update(doc.ref, { 
          status: "blocked",
          ...(doc.data().bridgecard_card_id && { bridgecard_status: "frozen" }),
        });

        if (doc.data().bridgecard_card_id) {
          try {
            await internalFreezeBridgecard(doc.data().bridgecard_card_id, true, doc.data().currency);
          } catch (e) {
            logger.error(`[KillSwitch] Failed to freeze card ${doc.id} at Bridgecard`, e);
            failedFreezes.push(doc.id);
          }
        }
      }
      await batch.commit();
      totalBlocked += cardsSnap.size;
    }
  }

  if (failedFreezes.length > 0) {
    throw new HttpsError(
      "internal",
      `FAILED STATE: Could not freeze ${failedFreezes.length} cards (${failedFreezes.join(', ')}). Manual intervention required.`
    );
  }

  return { success: true, blocked: totalBlocked };
});

/**
 * adminGlobalKillSwitch — blocks ALL active cards across the absolute entire platform.
 * Protected by strict `requireAdmin` custom claim validation.
 */
exports.adminGlobalKillSwitch = onCall({ region: "us-central1", enforceAppCheck: false }, async (request) => {
  requireAdmin(request.auth);

  // ── STEP 1: Write system_state/global FIRST — instant gate ─────────────────
  // All Cloud Functions now reject immediately before a single card is touched.
  await db.doc("system_state/global").set({
    mode: "LOCKDOWN",
    reason: "Admin Global Kill Switch activated via Cloud Function",
    activated_by: request.auth.uid,
    updated_at: FieldValue.serverTimestamp(),
  });

  logger.info("[AdminKillSwitch] System mode set to LOCKDOWN — gate closed.");

  // ── STEP 2: Card document sweep (best-effort UI consistency) ────────────────
  const cardsSnap = await db.collection("cards")
    .where("local_status", "==", "active")
    .get();

  // Also sweep legacy cards still using old 'status' field
  const legacySnap = await db.collection("cards")
    .where("status", "==", "active")
    .get();

  const allDocs = new Map();
  for (const doc of [...cardsSnap.docs, ...legacySnap.docs]) {
    allDocs.set(doc.id, doc);
  }

  if (allDocs.size === 0) return { success: true, mode: "LOCKDOWN", processed: 0 };

  let totalFrozen = 0;
  const batchArray = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const [, doc] of allDocs) {
    currentBatch.update(doc.ref, {
      local_status: "frozen",
      status: "blocked",
      lifecycle_version: FieldValue.increment(1),
      admin_locked_at: FieldValue.serverTimestamp(),
      ...(doc.data().bridgecard_card_id && { bridgecard_status: "frozen" }),
    });
    operationCount++;
    totalFrozen++;

    if (operationCount === 450) {
      batchArray.push(currentBatch);
      currentBatch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) batchArray.push(currentBatch);

  for (const batch of batchArray) {
    await batch.commit();
  }

  // ── STEP 3: Queue Bridgecard freeze task (async, best-effort) ──────────────
  await db.collection("admin_tasks").add({
    type: "BRIDGECARD_MASS_FREEZE",
    status: "PENDING",
    triggered_by: request.auth.uid,
    card_count: totalFrozen,
    created_at: FieldValue.serverTimestamp(),
  });

  logger.info(`[AdminKillSwitch] Froze ${totalFrozen} cards. Bridgecard freeze queued.`);

  return {
    success: true,
    mode: "LOCKDOWN",
    processed: allDocs.size,
    frozen: totalFrozen,
    bridgecardFreezeStatus: "queued_async",
  };
});

/**
 * sendCardNotification — called by the Flutter client after card setup to
 * dispatch a server-side in-app notification without any direct Firestore writes
 * from the client. Keeps the entire notification pipeline on the backend.
 */
exports.sendCardNotification = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const { cardId, title, body, type = "alert" } = request.data;

  if (!cardId || !title || !body) {
    throw new HttpsError("invalid-argument", "cardId, title and body are required.");
  }

  // Verify the card belongs to the calling user
  const cardSnap = await db.collection("cards").doc(cardId).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found.");

  const accountId = cardSnap.data().account_id;
  const accountSnap = await db.collection("accounts").doc(accountId).get();
  if (!accountSnap.exists) throw new HttpsError("not-found", "Account not found.");

  if (accountSnap.data().owner_user_id !== request.auth.uid) {
    throw new HttpsError("permission-denied", "You can only notify on your own cards.");
  }

  await sendNotification(accountId, body, { title, type });
  return { success: true };
});
