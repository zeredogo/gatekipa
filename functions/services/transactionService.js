const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth } = require("../utils/validators");
const { evaluateTransaction } = require("../engines/ruleEngine");
const { disableCard } = require("./cardService");
const { sendNotification } = require("./notificationService");
const { FieldValue } = require("firebase-admin/firestore");

/**
 * Endpoint to process a transaction securely.
 */
exports.processTransaction = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const { cardId, amount, merchantName } = request.data;
  
  if (!cardId || !Number.isFinite(amount) || amount <= 0 || !merchantName) {
    throw new HttpsError("invalid-argument", "A valid cardId, positive numeric amount, and merchantName are required.");
  }

  // 1. Fetch Card
  const cardSnap = await db.collection("cards").doc(cardId).get();
  if (!cardSnap.exists) {
    return { approved: false, reason: "Card not found" };
  }
  const card = cardSnap.data();

  // 2. Initial state evaluations (e.g. frozen or deleted)
  if (card.status !== "active") {
    return { approved: false, reason: "Card not active" };
  }

  // 3. Find the Account Owner for wallet deductions
  const accountSnap = await db.collection("accounts").doc(card.account_id).get();
  if (!accountSnap.exists) {
    return { approved: false, reason: "Account closed or invalid" };
  }
  const ownerUid = accountSnap.data().owner_user_id;

  if (ownerUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "You can only process simulated transactions for your own accounts.");
  }

  // 4. Engine execution - strict PRD alignment
  const result = await evaluateTransaction(cardId, amount, merchantName);

  if (result.approved) {
    // 4.1 Perform Atomic Wallet Deduction
    const walletRef = db.collection("users").doc(ownerUid).collection("wallet").doc("balance");
    try {
      await db.runTransaction(async (t) => {
        const walletDoc = await t.get(walletRef);
        const currentBalance = walletDoc.exists ? (walletDoc.data().balance || 0) : 0;
        
        if (currentBalance < amount) {
          throw new Error("Insufficient funds in owner's wallet.");
        }

        t.set(walletRef, { balance: FieldValue.increment(-amount) }, { merge: true });
      });
    } catch (error) {
      result.approved = false;
      result.reason = error.message;
    }
  }

  // 4. Record Transaction
  const txRef = db.collection("transactions").doc();
  const txn = {
    id: txRef.id,
    card_id: cardId,
    account_id: card.account_id,
    merchant_name: merchantName,
    amount,
    status: result.approved ? "approved" : "declined",
    decline_reason: result.reason || null,
    // Use server timestamp so Firestore Timestamp objects are stored correctly
    // (avoids the integer cast bug in analytics date parsing)
    timestamp: FieldValue.serverTimestamp(),
  };

  await txRef.set(txn);

  // 5. Backfill last4 on card if it hasn't been set yet (legacy cards)
  if (result.approved && !card.last4 && cardId) {
    const maskedSuffix = String(amount).slice(-4).padStart(4, "0");
    await db.collection("cards").doc(cardId).set(
      { last4: maskedSuffix },
      { merge: true }
    );
    console.info(`[Transaction] Backfilled last4 '${maskedSuffix}' for card ${cardId}`);
  }

  // 6. Post-Processing: Trial card auto-disable
  if (card.is_trial && result.approved) {
    await disableCard(cardId);
    await sendNotification(card.account_id, "Trial Card auto-disabled after successful transaction.");
  }

  // 7. Post-Processing: Notifications for blocked
  if (!result.approved) {
    await sendNotification(card.account_id, `Transaction blocked at ${merchantName} for ${amount}. Reason: ${result.reason}`);
  }

  return result;
});

