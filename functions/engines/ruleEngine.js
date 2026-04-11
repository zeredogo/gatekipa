const { db } = require("../utils/firebase");

/**
 * Helper to determine if a timestamp is in the current month
 * @param {number|object} timestamp - Epoch ms or Firestore Timestamp
 */
function isThisMonth(timestamp) {
  const date = timestamp && timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
  const now = new Date();
  return date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear();
}

/**
 * Core Rule Evaluator mapped directly to PRD specifications
 */
function evaluateRule(rule, amount, pastTxns) {
  switch (rule.sub_type) {
    case "max_per_txn":
      if (amount > rule.value) {
        return { passed: false, reason: "Exceeded max per transaction" };
      }
      break;

    case "monthly_cap":
      const monthlyTotal = pastTxns
        .filter(txn => isThisMonth(txn.timestamp))
        .reduce((sum, txn) => sum + txn.amount, 0);

      if (monthlyTotal + amount > rule.value) {
        return { passed: false, reason: "Monthly cap exceeded" };
      }
      break;

    case "expiry_date":
      // Value expected to be epoch ms or similar
      if (Date.now() > rule.value) {
        return { passed: false, reason: "Card expired" };
      }
      break;

    case "valid_duration":
      // Value expected to be milliseconds duration. Checks if current time is past rule.created_at + duration
      if (Date.now() > (rule.created_at + rule.value)) {
        return { passed: false, reason: "Card valid duration exceeded" };
      }
      break;

    case "max_charges":
      if (pastTxns.length >= rule.value) {
        return { passed: false, reason: "Max charges reached" };
      }
      break;

    case "block_after_first":
      if (pastTxns.length >= 1) {
        return { passed: false, reason: "Already used once" };
      }
      break;

    case "block_if_amount_changes":
      if (pastTxns.length > 0) {
        // pastTxns sorted ascending by time (first is oldest)
        const firstAmount = pastTxns[0].amount;
        if (amount !== firstAmount) {
          return { passed: false, reason: "Amount changed" };
        }
      }
      break;
  }

  return { passed: true };
}

/**
 * Master transaction evaluator. 
 * IF ANY rule fails -> DECLINE. ELSE -> APPROVE.
 */
async function evaluateTransaction(cardId, amount, merchantName) {
  // Fetch rules for this card
  const rulesSnap = await db.collection("rules").where("card_id", "==", cardId).get();
  const rules = rulesSnap.docs.map(doc => doc.data());

  // Fetch past approved transactions for this card
  // Indexed by card_id, ordered by timestamp ascending to satisfy block_if_amount_changes grabbing pastTxns[0]
  const txnsSnap = await db.collection("transactions")
    .where("card_id", "==", cardId)
    .where("status", "==", "approved")
    .orderBy("timestamp", "asc")
    .get();
  
  const pastTxns = txnsSnap.docs.map(doc => doc.data());

  for (const rule of rules) {
    const result = evaluateRule(rule, amount, pastTxns);

    if (!result.passed) {
      return {
        approved: false,
        reason: result.reason
      };
    }
  }

  return { approved: true };
}

module.exports = {
  evaluateTransaction,
  evaluateRule
};
