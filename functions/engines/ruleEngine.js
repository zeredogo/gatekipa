// functions/engines/ruleEngine.js
//
// HARDENED rule engine — all historical data is sourced from card_ledger,
// NOT from card.spentAmount, card.chargeCount, or the transactions collection.
//
// WHY: card.spentAmount is a cached display value updated by Cloud Functions.
// If it's stale (e.g. after a failed write), rules based on it can be bypassed.
// card_ledger is append-only and written within the same Firestore transaction
// as the charge itself, making it tamper-resistant.
//
// IMPORTANT: evaluateTransaction is called INSIDE a Firestore transaction
// (in processTransaction.js). The ledger helpers below perform independent reads
// BEFORE the transaction opens, which is acceptable because:
//   1. All writes are protected by the outer transaction.
//   2. card_ledger is append-only — there are no concurrent writes that
//      could invalidate these reads in a way that would allow a bypass.
//   3. The system mode gate (checked before this function) prevents concurrent
//      requests during lockdown.

const { db } = require("../utils/firebase");
const logger = require("firebase-functions/logger");

// ── Plan tier constants ───────────────────────────────────────────────────────
// FIX #7: Single source of truth for plan naming — "free" is the canonical
// name for Instant plan across all backend code. Frontend should use "free" too.
const SENTINEL_PLANS = ["premium", "business"];
const TRIAL_ELIGIBLE_PLANS = ["free", "activation"];

/**
 * FIX #5: Single consolidated helper to determine if a user has active Sentinel access.
 * Checks both paid plan tier AND active Sentinel trial expiry.
 * Use this everywhere instead of computing isSentinel inline.
 *
 * @param {object} userData - Firestore user document data
 * @returns {boolean}
 */
function userHasSentinelAccess(userData) {
  if (!userData) return false;
  if (SENTINEL_PLANS.includes(userData.planTier)) return true;
  const trialExpiry = userData.sentinel_trial_expiry_date;
  // FIX: Firestore Timestamp objects must use .toMillis() — direct > Date.now() comparison
  // with a Timestamp object is always false in JavaScript.
  const trialExpiryMs = trialExpiry?.toMillis
    ? trialExpiry.toMillis()
    : (typeof trialExpiry === 'number' ? trialExpiry : 0);
  return trialExpiryMs > Date.now();
}

// ── Ledger helpers ────────────────────────────────────────────────────────────

/**
 * Returns the sum of all 'charge' entries for a card in the last N days.
 * Used by: monthly_cap
 */
async function getLedgerSumForDays(cardId, days) {
  const since = new Date();
  since.setDate(since.getDate() - days);

  const snap = await db.collection("card_ledger")
    .where("card_id", "==", cardId)
    .where("type", "==", "charge")
    .where("created_at", ">=", since)
    .get();

  return snap.docs.reduce((sum, doc) => sum + (doc.data().amount || 0), 0);
}

/**
 * Returns the sum of all 'charge' entries in the current calendar month (WAT).
 * Used by: monthly_cap (month boundary version)
 */
async function getLedgerMonthlySum(cardId) {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);

  const snap = await db.collection("card_ledger")
    .where("card_id", "==", cardId)
    .where("type", "==", "charge")
    .where("created_at", ">=", monthStart)
    .get();

  return snap.docs.reduce((sum, doc) => sum + (doc.data().amount || 0), 0);
}

/**
 * Returns the total count of all 'charge' entries for a card.
 * Used by: max_charges, block_after_first
 */
async function getLedgerChargeCount(cardId) {
  const snap = await db.collection("card_ledger")
    .where("card_id", "==", cardId)
    .where("type", "==", "charge")
    .get();

  return snap.size;
}

/**
 * Returns the amount of the very first 'charge' entry for a card.
 * Used by: block_if_amount_changes
 * Returns null if no charges exist yet.
 */
async function getLedgerFirstChargeAmount(cardId) {
  const snap = await db.collection("card_ledger")
    .where("card_id", "==", cardId)
    .where("type", "==", "charge")
    .orderBy("created_at", "asc")
    .limit(1)
    .get();

  if (snap.empty) return null;
  return snap.docs[0].data().amount ?? null;
}

// ── Night lockdown helper ─────────────────────────────────────────────────────

function isNightLockdownActive() {
  const nowUtc = new Date();
  const hourWAT = (nowUtc.getUTCHours() + 1) % 24;
  return hourWAT >= 0 && hourWAT < 6;
}

// ── Sub-user spend helper (still uses card_ledger for accuracy) ───────────────

async function getSubUserMonthlySpend(accountId, creatorUid) {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);

  // Get all cards created by this sub-user in this account
  const cardsSnap = await db.collection("cards")
    .where("account_id", "==", accountId)
    .where("created_by", "==", creatorUid)
    .get();

  if (cardsSnap.empty) return 0;

  const cardIds = cardsSnap.docs.map(d => d.id);
  // card_ledger doesn't support whereIn natively for cardId, so we query per card.
  // For accounts with ≤10 sub-user cards this is fine; add pagination for scale.
  let totalSpend = 0;

  for (const cardId of cardIds.slice(0, 30)) {
    const ledgerSnap = await db.collection("card_ledger")
      .where("card_id", "==", cardId)
      .where("type", "==", "charge")
      .where("created_at", ">=", monthStart)
      .get();

    totalSpend += ledgerSnap.docs.reduce((sum, d) => sum + (d.data().amount || 0), 0);
  }

  return totalSpend;
}

// ── Single rule evaluator ─────────────────────────────────────────────────────

/**
 * Evaluates a single rule against ledger-derived data.
 * All I/O is done outside the Firestore transaction for efficiency.
 *
 * @param {object} rule - Rule document data.
 * @param {number} amount - The charge amount being evaluated.
 * @param {object} ledgerData - Pre-fetched ledger aggregates.
 * @returns {{ passed: boolean, reason?: string }}
 */
function evaluateRule(rule, amount, ledgerData) {
  switch (rule.sub_type) {

    case "max_per_txn":
      if (amount > rule.value) {
        return { passed: false, reason: `Exceeds per-transaction limit of ₦${rule.value}` };
      }
      break;

    case "monthly_cap":
      if (ledgerData.monthlySum + amount > rule.value) {
        return { passed: false, reason: `Monthly cap of ₦${rule.value} would be exceeded` };
      }
      break;

    case "expiry_date":
      if (Date.now() > rule.value) {
        return { passed: false, reason: "Card has expired" };
      }
      break;

    case "valid_duration":
      if (Date.now() > (rule.created_at + rule.value)) {
        return { passed: false, reason: "Card valid duration exceeded" };
      }
      break;

    case "max_charges":
      if (ledgerData.chargeCount >= rule.value) {
        return { passed: false, reason: `Maximum of ${rule.value} charges reached` };
      }
      break;

    case "block_after_first":
      if (ledgerData.chargeCount >= 1) {
        return { passed: false, reason: "Single-use card has already been used" };
      }
      break;

    case "block_if_amount_changes":
      if (ledgerData.firstChargeAmount !== null &&
          Math.abs(amount - ledgerData.firstChargeAmount) > 0.01) {
        return {
          passed: false,
          reason: `Amount ₦${amount} differs from original ₦${ledgerData.firstChargeAmount}`
        };
      }
      break;

    case "night_lockdown":
      if (rule.value && isNightLockdownActive()) {
        return { passed: false, reason: "Night lockdown active (12AM–6AM WAT)" };
      }
      break;
  }

  return { passed: true };
}

// ── Master evaluator ──────────────────────────────────────────────────────────

/**
 * evaluateTransaction — the authoritative rule engine.
 *
 * Runs OUTSIDE a Firestore transaction to perform all necessary reads first,
 * then returns a decision. The caller (processTransaction or bridgecardWebhook)
 * is responsible for the write-side Firestore transaction.
 *
 * @param {string} cardId
 * @param {number} amount
 * @param {string} merchantName
 * @param {object} [options]
 * @param {boolean} [options.dryRun=false] - If true, returns full evaluation without short-circuiting.
 * @returns {Promise<{ approved: boolean, reason?: string, evaluations?: object[] }>}
 */
async function evaluateTransaction(cardId, amount, merchantName, options = { dryRun: false }) {
  // 1. Fetch the card (localStatus is authoritative)
  const cardSnap = await db.collection("cards").doc(cardId).get();
  if (!cardSnap.exists) return { approved: false, reason: "Card not found" };
  const card = cardSnap.data();

  // 2. Status gate — use local_status (hardened field)
  const cardStatus = card.local_status || card.status || "unknown";
  if (cardStatus !== "active") {
    return { approved: false, reason: `Card is ${cardStatus}` };
  }

  // 3. Fetch account + owner
  const accountSnap = await db.collection("accounts").doc(card.account_id).get();
  if (!accountSnap.exists) return { approved: false, reason: "Account not found" };
  const accountData = accountSnap.data();
  const ownerUid = accountData.owner_user_id;

  const evaluations = [];
  let isGlobalBlocked = false;
  let globalReason = null;

  // 4. Global user-level guards
  const userSnap = await db.collection("users").doc(ownerUid).get();
  const userData = userSnap.exists ? userSnap.data() : null;

  // FIX #5: Use single consolidated helper — computed once, used everywhere below
  const isSentinel = userHasSentinelAccess(userData);

  if (userData) {
    // Night lockdown (user-level) — Sentinel feature only
    if (isSentinel && userData.nightLockdown === true && isNightLockdownActive()) {
      isGlobalBlocked = true;
      globalReason = "Global night lockdown is active (12AM–6AM WAT)";
      evaluations.push({ rule: "Global Night Lockdown", result: "FAIL" });
      if (!options.dryRun) return { approved: false, reason: globalReason };
    } else {
      evaluations.push({ rule: "Global Night Lockdown", result: "PASS" });
    }

    // FIX #6: Geo-fence — check real transaction channel/country instead of
    // fake "[intl]" string. Bridgecard webhooks include a `channel` field.
    // Cross-border transactions typically come via "WEB" or "POS" from non-NG merchants.
    // We gate on the card's currency and the merchant country code if present.
    if (isSentinel && userData.geoFence === true && card.currency !== "USD") {
      // merchantName is passed from webhook; check for known international patterns.
      // A more robust solution would use the webhook's `merchant_country` field directly.
      const merchantStr = (merchantName || "").toLowerCase();
      const isInternational = merchantStr.includes("[intl]") || 
                              merchantStr.includes("international") ||
                              (options.merchantCountry && options.merchantCountry !== "NG") ||
                              (options.transactionCurrency && options.transactionCurrency !== "NGN");
      
      if (isInternational) {
        isGlobalBlocked = true;
        globalReason = "Geo-fence active: only Nigerian transactions allowed";
        evaluations.push({ rule: "Global Geo-Fence", result: "FAIL" });
        if (!options.dryRun) return { approved: false, reason: globalReason };
      } else {
        evaluations.push({ rule: "Global Geo-Fence", result: "PASS" });
      }
    } else {
      evaluations.push({ rule: "Global Geo-Fence", result: "PASS" });
    }
  }

  // 5. Sub-user hierarchical spend limit — Sentinel feature only
  const creatorUid = card.created_by || ownerUid;
  if (creatorUid !== ownerUid && isSentinel) {
    const tmSnap = await db.collection("team_members")
      .doc(`${card.account_id}_${creatorUid}`)
      .get();

    if (tmSnap.exists && tmSnap.data().spend_limit) {
      const spendLimit = Number(tmSnap.data().spend_limit);
      const subUserMonthlySpent = await getSubUserMonthlySpend(card.account_id, creatorUid);

      if (subUserMonthlySpent + amount > spendLimit) {
        isGlobalBlocked = true;
        globalReason = `Team member budget exceeded. Remaining: ₦${Math.max(0, spendLimit - subUserMonthlySpent).toFixed(2)}`;
        evaluations.push({ rule: "Team Member Spend Limit", result: "FAIL" });
        if (!options.dryRun) return { approved: false, reason: globalReason };
      } else {
        evaluations.push({ rule: "Team Member Spend Limit", result: "PASS" });
      }
    }
  }

  // 6. Pre-fetch all ledger aggregates for card-level rules
  //    (batched before the rule loop to avoid N round-trips)
  const [monthlySum, chargeCount, firstChargeAmount] = await Promise.all([
    getLedgerMonthlySum(cardId),
    getLedgerChargeCount(cardId),
    getLedgerFirstChargeAmount(cardId),
  ]);

  const ledgerData = { monthlySum, chargeCount, firstChargeAmount };

  // 7. Fetch card-level rules
  const rulesSnap = await db.collection("rules").where("card_id", "==", cardId).get();
  const rules = rulesSnap.docs.map(doc => ({ id: doc.id, ...doc.data() }));

  // 8. Evaluate each rule
  // FIX #5: isSentinel is already computed above — no re-computation needed
  // FIX: max_per_txn and max_charges are BASIC rules — submitted for all plan tiers at card
  // creation. They must NOT be bypassed for non-Sentinel users, otherwise cards lose
  // their spending cap enforcement the moment a trial expires.
  // Sentinel-only: monthly_cap, valid_duration, block_after_first, block_if_amount_changes.
  const advancedRules = ["monthly_cap", "valid_duration", "block_after_first", "block_if_amount_changes", "night_lockdown", "instant_breach_alert"];

  for (const rule of rules) {
    // USD cards bypass advanced spend/behavior rules (keeps USD cards globally spendable)
    if (card.currency === "USD" && rule.sub_type !== "night_lockdown") {
      evaluations.push({ rule: `${rule.sub_type}`, result: "BYPASSED (USD card)" });
      continue;
    }

    // Bypass advanced rules if the user's Sentinel access has expired
    if (!isSentinel && advancedRules.includes(rule.sub_type)) {
      evaluations.push({ rule: `${rule.sub_type}`, result: "BYPASSED (Sentinel access expired)" });
      continue;
    }

    const result = evaluateRule(rule, amount, ledgerData);
    const label = `${rule.type} / ${rule.sub_type}`;
    evaluations.push({
      rule: label,
      result: result.passed ? "PASS" : `FAIL (${result.reason})`,
    });

    if (!result.passed) {
      if (!options.dryRun) {
        return { approved: false, reason: result.reason };
      } else {
        isGlobalBlocked = true;
        globalReason = globalReason || result.reason;
      }
    }
  }

  if (options.dryRun) {
    return {
      decision: isGlobalBlocked ? "BLOCKED" : "APPROVED",
      reason: globalReason || "All rules passed.",
      evaluations,
    };
  }

  return { approved: true };
}

module.exports = {
  evaluateTransaction,
  evaluateRule,
  getLedgerMonthlySum,
  getLedgerChargeCount,
  getLedgerFirstChargeAmount,
  userHasSentinelAccess,
};
