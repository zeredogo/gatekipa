const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireVerifiedEmail, requireFields, requireKyc, requireAdmin } = require("../utils/validators");
const crypto = require("crypto");
const { internalFreezeBridgecard } = require("./bridgecardService");
const { sendNotification } = require("./notificationService");
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

exports.createVirtualCard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {

  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  await requireKyc(uid);

  const data = request.data;
  
  requireFields(data, ["account_id", "name"]);
  const { account_id, name, is_trial = false, category = 'personal', currency = 'NGN' } = data;

  // Verify account ownership or membership
  const accountDoc = await db.collection("accounts").doc(account_id).get();
  if (!accountDoc.exists) throw new HttpsError("not-found", "Account not found.");
  if (accountDoc.data().owner_user_id !== uid) {
    const tmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
    if (!tmSnap.exists || tmSnap.data().role !== "admin") {
      throw new HttpsError("permission-denied", "Only owner or admin can create cards.");
    }
  }

  const { last4, masked_number, cvv } = generatePlaceholderDetails();

  const cardRef = db.collection("cards").doc();
  const now = Date.now();

  const card = {
    id: cardRef.id,
    account_id,
    name: name.trim(),
    status: "pending_issuance", // Becomes 'active' after createBridgecard succeeds
    is_trial: is_trial,
    category: category,
    currency: currency,
    last4,
    masked_number,
    cvv,
    balance_limit: 0,
    spent_amount: 0,
    charge_count: 0,
    created_at: now,
    created_by: uid
  };

  await cardRef.set(card);

  // Trial Card Auto-Rules
  if (is_trial) {
    const rulesBatch = db.batch();
    
    // Max charges = 1
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

    // Expiry = 30 days
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

    await rulesBatch.commit();
  }

  return { success: true, cardId: cardRef.id, card };
});

exports.toggleCardStatus = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const { card_id, status } = request.data;
  requireFields(request.data, ["card_id", "status"]);

  const cardSnap = await db.collection("cards").doc(card_id).get();
  if (!cardSnap.exists) throw new HttpsError("not-found", "Card not found");
  
  const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountDoc.exists || accountDoc.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Only the account owner can toggle card status.");
  }

  await db.collection("cards").doc(card_id).update({
    status: status,
    ...(cardSnap.data().bridgecard_card_id && { bridgecard_status: status === "blocked" ? "frozen" : status }),
  });

  if (cardSnap.data().bridgecard_card_id) {
    try {
      await internalFreezeBridgecard(cardSnap.data().bridgecard_card_id, status === "blocked" || status === "frozen", cardSnap.data().currency);
    } catch (e) {
      logger.error(`[CardToggle] Bridgecard toggle failed for ${card_id}`, e);
      throw new HttpsError("internal", `Failed to sync toggled status to Bridgecard: ${e.message}`);
    }
  }

  return { success: true };
});

exports.renameCard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
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
    status: "blocked"
  });
};

/**
 * activateKillSwitch — blocks all active cards across all accounts owned by the caller.
 * Called via httpsCallable('activateKillSwitch') from the Flutter app (biometric-gated).
 */
exports.activateKillSwitch = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
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
exports.adminGlobalKillSwitch = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAdmin(request.auth);

  const cardsSnap = await db.collection("cards")
    .where("status", "==", "active")
    .get();

  if (cardsSnap.empty) return { success: true, processed: 0, frozen: 0, failed: 0 };

  let totalBlocked = 0;
  const failedFreezes = [];

  // Batch process
  const batchArray = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const doc of cardsSnap.docs) {
    currentBatch.update(doc.ref, { 
      status: "blocked",
      ...(doc.data().bridgecard_card_id && { bridgecard_status: "frozen" }),
    });
    operationCount++;

    if (doc.data().bridgecard_card_id) {
      try {
        await internalFreezeBridgecard(doc.data().bridgecard_card_id, true, doc.data().currency);
        totalBlocked++;
      } catch (e) {
        logger.error(`[AdminKillSwitch] Failed to freeze card ${doc.id} at Bridgecard`, e);
        failedFreezes.push(doc.id);
      }
    }

    if (operationCount === 450) {
      batchArray.push(currentBatch);
      currentBatch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    batchArray.push(currentBatch);
  }

  for (const batch of batchArray) {
    await batch.commit();
  }

  if (failedFreezes.length > 0) {
    throw new HttpsError(
      "internal",
      `FAILED STATE: Could not freeze ${failedFreezes.length} cards (${failedFreezes.slice(0, 5).join(', ')}...). Manual intervention required.`
    );
  }

  return { success: true, processed: cardsSnap.size, frozen: totalBlocked, failed: failedFreezes.length };
});

/**
 * sendCardNotification — called by the Flutter client after card setup to
 * dispatch a server-side in-app notification without any direct Firestore writes
 * from the client. Keeps the entire notification pipeline on the backend.
 */
exports.sendCardNotification = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
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
