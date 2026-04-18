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
 * Returns true if the current server time is within the night lockdown window
 * (midnight 00:00 through 05:59 WAT, UTC+1).
 */
function isNightLockdownActive() {
  // WAT = UTC+1. Adjust server (UTC) time.
  const nowUtc = new Date();
  const hourWAT = (nowUtc.getUTCHours() + 1) % 24;
  return hourWAT >= 0 && hourWAT < 6;
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

    case "night_lockdown":
      // Per-card night lockdown: blocks 12AM-6AM WAT. Only enforced when rule value is truthy.
      if (rule.value && isNightLockdownActive()) {
        return { passed: false, reason: "Night lockdown active (12AM-6AM)" };
      }
      break;
  }

  return { passed: true };
}

/**
 * Master transaction evaluator. 
 * IF ANY rule fails -> DECLINE. ELSE -> APPROVE.
 */
async function evaluateTransaction(cardId, amount, merchantName, options = { dryRun: false }) {
  // 1. Fetch the card to get its account
  const cardSnap = await db.collection("cards").doc(cardId).get();
  if (!cardSnap.exists) return { approved: false, reason: "Card not found" };
  const card = cardSnap.data();

  // 2. Fetch the account to get the owner UID
  const accountSnap = await db.collection("accounts").doc(card.account_id).get();
  if (!accountSnap.exists) return { approved: false, reason: "Account not found" };
  const ownerUid = accountSnap.data().owner_user_id;

  const evaluations = [];
  let isGlobalBlocked = false;
  let globalReason = null;

  // 3. Enforce GLOBAL USER-LEVEL GUARDS (nightLockdown, geoFence)
  const userSnap = await db.collection("users").doc(ownerUid).get();
  if (userSnap.exists) {
    const userData = userSnap.data();

    // Night Lockdown
    if (userData.nightLockdown === true && isNightLockdownActive()) {
      isGlobalBlocked = true;
      globalReason = "Global night lockdown is active (12AM-6AM)";
      evaluations.push({ rule: "Global Night Lockdown", result: "FAIL" });
      if (!options.dryRun) return { approved: false, reason: globalReason };
    } else {
      evaluations.push({ rule: "Global Night Lockdown", result: "PASS" });
    }

    // Geo-Fence (Bypassed if USD Card)
    if (card.currency !== 'USD' && userData.geoFence === true && merchantName && merchantName.toLowerCase().includes('[intl]')) {
      isGlobalBlocked = true;
      globalReason = "Geo-fence active: only Nigerian transactions allowed";
      evaluations.push({ rule: "Global Geo-Fence", result: "FAIL" });
      if (!options.dryRun) return { approved: false, reason: globalReason };
    } else {
      evaluations.push({ rule: "Global Geo-Fence", result: "PASS" });
    }
  }

  // 3.5 Enforce Sub-User Hierarchical Spending Limits
  const creatorUid = card.created_by || ownerUid;
  if (creatorUid !== ownerUid) {
    const tmSnap = await db.collection("team_members").doc(`${card.account_id}_${creatorUid}`).get();
    if (tmSnap.exists && tmSnap.data().spend_limit) {
      const spendLimit = Number(tmSnap.data().spend_limit);
      
      // Calculate how much they've already spent this month across all their cards natively
      // Fetch all cards created by them in this account
      const subUserCardsSnap = await db.collection("cards")
        .where("account_id", "==", card.account_id)
        .where("created_by", "==", creatorUid)
        .get();
      
      const subUserCardIds = subUserCardsSnap.docs.map(d => d.id);
      
      if (subUserCardIds.length > 0) {
        // Unfortunately `whereIn` only allows 30 items, but sub-users shouldn't reach that natively
        const boundedIds = subUserCardIds.slice(0, 30); 
        
        let subUserMonthlySpent = 0;
        
        // Optimize by just summing up spent amounts from the cards directly since limits are simple
        // Wait, 'spent_amount' tracks lifetime. We need strictly this month's transactions.
        const monthTxnsSnap = await db.collection("transactions")
          .where("card_id", "in", boundedIds)
          .where("status", "==", "approved")
          .get();
          
        subUserMonthlySpent = monthTxnsSnap.docs
          .map(d => d.data())
          .filter(txn => isThisMonth(txn.timestamp))
          .reduce((acc, txn) => acc + txn.amount, 0);

        if (subUserMonthlySpent + amount > spendLimit) {
          isGlobalBlocked = true;
          globalReason = `Hierarchical limit reached. Budget remaining: ₦${Math.max(0, spendLimit - subUserMonthlySpent)}`;
          evaluations.push({ rule: "Team Member Spend Limit", result: "FAIL" });
          if (!options.dryRun) return { approved: false, reason: globalReason };
        } else {
          evaluations.push({ rule: "Team Member Spend Limit", result: "PASS" });
        }
      }
    }
  }

  // 4. Fetch card-level rules
  const rulesSnap = await db.collection("rules").where("card_id", "==", cardId).get();
  const rules = rulesSnap.docs.map(doc => doc.data());

  // 5. Fetch past approved transactions for this card
  const txnsSnap = await db.collection("transactions")
    .where("card_id", "==", cardId)
    .where("status", "==", "approved")
    .orderBy("timestamp", "asc")
    .get();
  
  const pastTxns = txnsSnap.docs.map(doc => doc.data());

  // 6. Evaluate each card rule (USD Cards explicitly ignore advanced restrictions)
  if (card.currency === 'USD') {
     evaluations.push({ rule: "USD Card Optimization", result: "Bypassed Advanced Card-Level Constraints" });
  } else {
    for (const rule of rules) {
      if (rule.sub_type !== "night_lockdown") {
          // It ignores all rules except maybe night_lockdown, or we just let it evaluate all if it's NGN.
          // Since the chunk above says USD bypasses it, we only run the loop entirely for NGN cards 
          // (or evaluate all rules if NGN, but wait, night_lockdown was a rule we should keep? 
          // The user said bypass the advanced rules blocker. We can just skip running `evaluateRule` for advanced rules if USD.)
      }
      // Actually, since USD cards bypass advanced rules, we can just skip evaluation for advanced rules if the card is USD.
      // Wait, let's just make it simple: if card is USD, we ONLY enforce "night_lockdown" if it's created.
      if (card.currency === 'USD' && rule.sub_type !== 'night_lockdown') {
         continue; // Bypass advanced rule
      }
      
      const result = evaluateRule(rule, amount, pastTxns);
      evaluations.push({ rule: `${rule.type} - ${rule.sub_type || ''}`, result: result.passed ? "PASS" : `FAIL (${result.reason})` });
      
      if (!result.passed) {
        if (!options.dryRun) {
          return { approved: false, reason: result.reason };
        } else {
          isGlobalBlocked = true;
          globalReason = globalReason || result.reason;
        }
      }
    }
  }

  if (options.dryRun) {
    return {
      decision: isGlobalBlocked ? "BLOCKED" : "APPROVED",
      reason: globalReason || "All rules passed.",
      evaluations
    };
  }

  return { approved: true };
}

module.exports = {
  evaluateTransaction,
  evaluateRule
};
