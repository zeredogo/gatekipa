const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const crypto = require("crypto");
const { internalFreezeBridgecard } = require("./bridgecardService");

/** Generate masked card number, returning parts */
function generateCardDetails() {
  const last4 = Math.floor(1000 + Math.random() * 9000).toString();
  const masked = `5399 **** **** ${last4}`;
  const cvv = Math.floor(100 + Math.random() * 900).toString();
  return { last4, masked_number: masked, cvv };
}

exports.createVirtualCard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const data = request.data;
  
  requireFields(data, ["account_id", "name"]);
  
  const { account_id, name, is_trial = false, category = 'personal' } = data;

  // Verify account ownership or membership
  const accountDoc = await db.collection("accounts").doc(account_id).get();
  if (!accountDoc.exists) throw new HttpsError("not-found", "Account not found.");
  if (accountDoc.data().owner_user_id !== uid) {
    const tmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
    if (!tmSnap.exists || tmSnap.data().role !== "admin") {
      throw new HttpsError("permission-denied", "Only owner or admin can create cards.");
    }
  }

  // Generate card display details
  const { last4, masked_number, cvv } = generateCardDetails();

  const cardRef = db.collection("cards").doc();
  const now = Date.now();

  const card = {
    id: cardRef.id,
    account_id,
    name: name.trim(),
    status: "active",
    is_trial: is_trial,
    category: category,
    last4,
    masked_number,
    cvv,
    balance_limit: 0,
    spent_amount: 0,
    charge_count: 0,
    created_at: now
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
  requireAuth(request.auth);
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
      await internalFreezeBridgecard(cardSnap.data().bridgecard_card_id, status === "blocked" || status === "frozen");
    } catch (e) {
      console.error("Bridgecard toggle failed", e);
    }
  }

  return { success: true };
});

exports.renameCard = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
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
  requireAuth(request.auth);
  const uid = request.auth.uid;

  // 1. Find all accounts owned by this user
  const accountsSnap = await db.collection("accounts")
    .where("owner_user_id", "==", uid)
    .get();

  if (accountsSnap.empty) return { success: true, blocked: 0 };

  const accountIds = accountsSnap.docs.map(d => d.id);

  // 2. Fetch all active cards across those accounts (Firestore 'in' supports ≤10 values)
  const chunks = [];
  for (let i = 0; i < accountIds.length; i += 10) {
    chunks.push(accountIds.slice(i, i + 10));
  }

  let totalBlocked = 0;
  for (const chunk of chunks) {
    const cardsSnap = await db.collection("cards")
      .where("account_id", "in", chunk)
      .where("status", "==", "active")
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
            await internalFreezeBridgecard(doc.data().bridgecard_card_id, true);
          } catch (e) {
            console.error("Bridgecard killswitch failed", e);
          }
        }
      }
      await batch.commit();
      totalBlocked += cardsSnap.size;
    }
  }

  return { success: true, blocked: totalBlocked };
});
