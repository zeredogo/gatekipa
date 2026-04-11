const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");

exports.createRule = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const data = request.data;
  
  requireFields(data, ["card_id", "type", "sub_type", "value"]);

  const uid = request.auth.uid;
  
  // Verify card exists
  const cardSnap = await db.collection("cards").doc(data.card_id).get();
  if (!cardSnap.exists) {
    throw new HttpsError("not-found", "Card not found.");
  }
  
  // Verify card's account ownership
  const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountDoc.exists || accountDoc.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Only the account owner can create card rules.");
  }
  
  // Create rule in native collection
  const ruleRef = db.collection("rules").doc();
  const rule = {
    id: ruleRef.id,
    card_id: data.card_id,
    type: data.type,
    sub_type: data.sub_type,
    value: data.value,
    meta: data.meta || {},
    created_at: Date.now()
  };

  await ruleRef.set(rule);

  return { success: true, ruleId: ruleRef.id, rule };
});

exports.deleteRule = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { rule_id } = request.data;
  requireFields(request.data, ["rule_id"]);

  const ruleSnap = await db.collection("rules").doc(rule_id).get();
  if (!ruleSnap.exists) throw new HttpsError("not-found", "Rule not found.");

  const cardSnap = await db.collection("cards").doc(ruleSnap.data().card_id).get();
  if (cardSnap.exists) {
      const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
      if (!accountDoc.exists || accountDoc.data().owner_user_id !== uid) {
          throw new HttpsError("permission-denied", "Only the account owner can delete card rules.");
      }
  }

  await db.collection("rules").doc(rule_id).delete();
  return { success: true };
});
