const { db } = require("../utils/firebase");
const logger = require("firebase-functions/logger");

/**
 * Fetches user behavior and card history aggregates to construct JIT behavior profile.
 */
async function fetchLedgerStats(cardId) {
  try {
    const since = new Date();
    since.setDate(since.getDate() - 30);

    const snap = await db.collection("card_ledger")
      .where("card_id", "==", cardId)
      .where("type", "==", "charge")
      .where("created_at", ">=", since)
      .select("amount", "merchant_name")
      .get();

    const charges = snap.docs.map(doc => doc.data());
    const count = charges.length;
    
    const sum = charges.reduce((acc, c) => acc + (c.amount || 0), 0);
    const avgAmount = count > 0 ? sum / count : 0;
    
    const knownMerchants = Array.from(new Set(charges.map(c => c.merchant_name || "")));
    
    // Fetch recent failed velocity attempts
    const fiveMinsAgo = new Date(Date.now() - 5 * 60 * 1000);
    const failedAttemptsSnap = await db.collection("negative_balance_ledgers")
      .where("uid", "==", cardId) // fallback to card specific failed limits if tracked
      .where("created_at", ">=", fiveMinsAgo.getTime())
      .count()
      .get();
      
    const recentAttemptsCount = failedAttemptsSnap.data().count;

    return {
      avgTransactionAmount: avgAmount,
      chargeCount: count,
      knownMerchants,
      recentAttemptsCount
    };
  } catch (err) {
    logger.warn(`[RiskEngine] Failed to fetch ledger stats: ${err.message}. Using defaults.`);
    return {
      avgTransactionAmount: 0,
      chargeCount: 0,
      knownMerchants: [],
      recentAttemptsCount: 0
    };
  }
}

/**
 * Calculates a transaction risk score from 0 to 100.
 * 
 * @param {object} card - Firestore card document data
 * @param {object} user - Firestore user document data
 * @param {object} txn - Current incoming transaction metadata (amount, merchantName, ip, deviceFingerprint, etc.)
 * @param {object} aggregates - Pre-computed historical ledger statistics
 * @returns {{ score: number, reasons: string[] }}
 */
function calculateRiskScore(card, user, txn, aggregates = {}) {
  let score = 0;
  const reasons = [];

  const amount = txn.amount || 0;
  const merchantName = (txn.merchantName || "Unknown Merchant").toLowerCase();
  
  // 1. Time of Transaction check (Midnight 1AM - 5AM WAT)
  const nowUtc = new Date();
  const hourWAT = (nowUtc.getUTCHours() + 1) % 24;
  if (hourWAT >= 1 && hourWAT < 5) {
    score += 20;
    reasons.push("Midnight Transaction");
  }

  // 2. Transaction Amount Deviation check (>1.5x average historical transaction)
  const avgAmount = aggregates.avgTransactionAmount || 0;
  const historicalCount = aggregates.chargeCount || 0;
  if (historicalCount >= 3 && amount > (avgAmount * 1.5)) {
    score += 20;
    reasons.push("Unusual Amount");
  }

  // 3. New Merchant check
  const knownMerchants = aggregates.knownMerchants || [];
  const normalizedMerchant = merchantName.trim();
  const isNewMerchant = knownMerchants.length > 0 && !knownMerchants.some(m => normalizedMerchant.includes(m.toLowerCase()));
  if (isNewMerchant) {
    score += 15;
    reasons.push("New Merchant");
  }

  // 4. International Country check
  const isInternational = txn.merchantCountry && txn.merchantCountry !== "NG";
  if (isInternational) {
    score += 15;
    reasons.push("International Country");
  }

  // 5. VPN / TOR / Proxy Environment check
  const env = txn.environment || {};
  if (env.isVpn || env.isTor || env.isProxy) {
    score += 25;
    reasons.push("VPN Detected");
  }

  // 6. Velocity Check (attempts in last 5 minutes)
  const recentAttempts = aggregates.recentAttemptsCount || 0;
  if (recentAttempts > 3) {
    score += 15;
    reasons.push("High Velocity Attempts");
  }

  // 7. Card age check (Card created < 24 hours ago)
  const cardCreatedAt = card.created_at?.toMillis ? card.created_at.toMillis() : Date.now();
  const cardAgeHours = (Date.now() - cardCreatedAt) / (1000 * 60 * 60);
  if (cardAgeHours < 24) {
    score += 10;
    reasons.push("New Card");
  }

  // Cap risk score between 0 and 100
  const finalScore = Math.min(100, Math.max(0, score));

  logger.info(`[RiskEngine] Evaluated risk score: ${finalScore}% for card ${card.id || 'unknown'}. Reasons: ${reasons.join(', ')}`);

  return {
    score: finalScore,
    reasons
  };
}

module.exports = {
  calculateRiskScore,
  fetchLedgerStats
};
