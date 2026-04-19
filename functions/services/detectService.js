const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth } = require("../utils/validators");

/**
 * detectSubscriptions — analyses a list of SMS/notification messages
 * and returns detected recurring subscription charges.
 * 
 * Input:  { messages: string[] }
 * Output: { count: number, subscriptions: { name, amount, currency }[] }
 */
exports.detectSubscriptions = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const { messages = [] } = request.data;
  const uid = request.auth.uid;

  if (!Array.isArray(messages)) {
    throw new HttpsError("invalid-argument", "messages must be an array of strings.");
  }

  // Pattern-based detection engine (keyword + amount extraction)
  const subscriptionKeywords = [
    "subscription", "recurring", "monthly", "annually", "billed",
    "auto-renew", "renewal", "plan", "membership", "receipt"
  ];

  const amountPattern = /(NGN|₦|\$|USD|EUR|GBP)\s?([\d,]+(?:\.\d{2})?)/i;
  const merchantPattern = /(?:from|receipt from|paid to|charged by)\s+([A-Za-z0-9\s]+)/i;

  const detected = [];
  const batch = db.batch();
  const subscriptionsRef = db.collection('users').doc(uid).collection('detected_subscriptions');

  for (const msg of messages) {
    if (typeof msg !== 'string') {
      console.warn("[DetectSubscriptions] Skipping non-string message component:", typeof msg);
      continue;
    }
    
    const lower = msg.toLowerCase();
    const isSubscription = subscriptionKeywords.some(kw => lower.includes(kw));
    if (!isSubscription) continue;

    let amountInCents = 0;
    let currencyStr = 'NGN';
    const amountMatch = msg.match(amountPattern);
    
    if (amountMatch) {
      currencyStr = amountMatch[1].toUpperCase();
      if (currencyStr === '₦') currencyStr = 'NGN';
      if (currencyStr === '$') currencyStr = 'USD';
      
      const rawNumber = amountMatch[2].replace(/,/g, '');
      const parsedAmount = parseFloat(rawNumber);
      if (!isNaN(parsedAmount)) {
          amountInCents = Math.round(parsedAmount * 100);
      }
    }

    const merchantMatch = msg.match(merchantPattern);
    const merchantName = merchantMatch && merchantMatch[1] ? merchantMatch[1].trim() : "Unknown Merchant";

    const subDoc = {
      name: merchantName,
      amount: amountInCents,
      currency: currencyStr,
      category: 'Service',
      cycle: 'monthly',
      color_hex: '#1E40AF',
      icon: 'receipt_long_rounded',
      raw_message: msg.substring(0, 80),
      detectedAt: new Date().toISOString()
    };

    detected.push(subDoc);
    const newDocRef = subscriptionsRef.doc();
    batch.set(newDocRef, subDoc);
  }

  // Commit to firestore
  if (detected.length > 0) {
    try {
        await batch.commit();
        console.info(`[DetectSubscriptions] Successfully committed ${detected.length} subscriptions to Firestore for uid: ${uid}`);
    } catch (e) {
        console.error("[DetectSubscriptions] Firestore batch commit failed:", e);
        throw new HttpsError("internal", "Failed to save detected subscriptions");
    }
  }

  return {
    success: true,
    count: detected.length,
    subscriptions: detected,
  };
});
