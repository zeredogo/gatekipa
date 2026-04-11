const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");

exports.fundWallet = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { amount, method, reference } = request.data;

  throw new HttpsError(
    "permission-denied", 
    "This method is deprecated for security reasons. Wallet funding must be atomic via Paystack Webhooks or verifyPaystackPayment."
  );
});

exports.withdrawFunds = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { amount } = request.data;

  requireFields(request.data, ["amount"]);

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be a strictly positive finite number.");
  }

  const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");

  try {
    await db.runTransaction(async (t) => {
      const doc = await t.get(walletRef);
      const currentBalance = doc.exists ? (doc.data().balance || 0) : 0;
      
      if (currentBalance < amount) {
        throw new HttpsError("failed-precondition", "Insufficient funds.");
      }

      t.set(walletRef, { balance: FieldValue.increment(-amount) }, { merge: true });
    });
    
    return { success: true, amount_withdrawn: amount };
  } catch (error) {
    if (error instanceof HttpsError) {
        throw error;
    }
    throw new HttpsError("internal", error.message);
  }
});

exports.createVaultAccount = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;

  // In production, this would make an HTTPS call to Bridgecard's issuing API.
  // We simulate the backend processing here securely instead of allowing clients to choose their NUBAN.
  const simulatedNuban = `810${Date.now().toString().substring(6)}`;
  
  await db.collection("users").doc(uid).update({
    'bridgecardNuban': simulatedNuban,
    'bridgecardBankName': 'Moniepoint MFB',
    'bridgecardAccountName': 'Gatekipa - Dedicated Vault',
  });

  return { success: true, nuban: simulatedNuban };
});
