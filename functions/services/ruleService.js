const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields, requireAdmin } = require("../utils/validators");
const { evaluateTransaction, userHasSentinelAccess } = require("../engines/ruleEngine");

exports.createRule = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const data = request.data;
  
  requireFields(data, ["card_id", "type", "sub_type", "value"]);

  const uid = request.auth.uid;
  
  // Verify card exists
  const cardSnap = await db.collection("cards").doc(data.card_id).get();
  if (!cardSnap.exists) {
    throw new HttpsError("not-found", "Card not found.");
  }
  
  // Verify card's account ownership OR team admin membership
  const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
  if (!accountDoc.exists) {
    throw new HttpsError("not-found", "Account not found.");
  }
  const ownerId = accountDoc.data().owner_user_id;
  if (ownerId !== uid) {
    // FIX: Team admins have full account rights — they must be able to create card rules.
    // Previously only the owner could, silently blocking all team admin members.
    const tmSnap = await db
      .collection("team_members")
      .where("account_id", "==", accountDoc.id)
      .where("user_id", "==", uid)
      .where("role", "==", "admin")
      .limit(1)
      .get();
    if (tmSnap.empty) {
      throw new HttpsError("permission-denied", "Only the account owner or team admins can create card rules.");
    }
  }
  
  // Enforce Premium Rule Limits
  // FIX #4: max_per_txn and max_charges are BASIC rules submitted for all plans during card creation.
  // Keeping them here caused silent permission-denied failures for free/activation plan users.
  // True sentinel-only rules: monthly_cap, valid_duration, block_after_first, block_if_amount_changes.
  const advancedRules = ["monthly_cap", "valid_duration", "block_after_first", "block_if_amount_changes", "night_lockdown", "instant_breach_alert"];
  if (advancedRules.includes(data.sub_type)) {
    const ownerDoc = await db.collection("users").doc(uid).get();
    const ownerData = ownerDoc.exists ? ownerDoc.data() : null;
    
    if (!userHasSentinelAccess(ownerData)) {
      throw new HttpsError("permission-denied", "This rule requires a Sentinel Prime or Business plan.");
    }
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

exports.deleteRule = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { rule_id } = request.data;
  requireFields(request.data, ["rule_id"]);

  const ruleSnap = await db.collection("rules").doc(rule_id).get();
  if (!ruleSnap.exists) throw new HttpsError("not-found", "Rule not found.");

  const cardSnap = await db.collection("cards").doc(ruleSnap.data().card_id).get();
  if (cardSnap.exists) {
      const accountDoc = await db.collection("accounts").doc(cardSnap.data().account_id).get();
      if (accountDoc.exists) {
        const ownerId = accountDoc.data().owner_user_id;
        if (ownerId !== uid) {
          // FIX: Also allow team admins to delete rules, consistent with create.
          const tmSnap = await db
            .collection("team_members")
            .where("account_id", "==", accountDoc.id)
            .where("user_id", "==", uid)
            .where("role", "==", "admin")
            .limit(1)
            .get();
          if (tmSnap.empty) {
            throw new HttpsError("permission-denied", "Only the account owner or team admins can delete card rules.");
          }
        }
      }
  }

  await db.collection("rules").doc(rule_id).delete();
  return { success: true };
});

/**
 * adminSimulateRuleEngine — Executes evaluating logic but bypasses actual freezing actions.
 * Perfect for frontend UI debugging traces.
 */
exports.adminSimulateRuleEngine = onCall({ region: "us-central1", enforceAppCheck: false }, async (request) => {
  requireAdmin(request.auth);
  
  const { card_id, amount, merchant_name, currency, channel } = request.data;
  requireFields(request.data, ["card_id", "amount", "merchant_name"]);

  // We mock a transaction object exactly matching Webhook schema payload
  const mockTx = {
    amount: parseInt(amount, 10),
    currency: currency || "NGN",
    merchant_name,
    channel: channel || "WEB",
  };

  // Run the actual evaluation module WITHOUT firing the freeze triggers 
  const result = await evaluateTransaction(card_id, mockTx, { dryRun: true });

  return result;
});
