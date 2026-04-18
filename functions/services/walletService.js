const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail, requireFields, requireKyc } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");

const PAYSTACK_SECRET_KEY = defineSecret("PAYSTACK_SECRET_KEY");

exports.fundWallet = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireVerifiedEmail(request.auth);
  // This endpoint is intentionally disabled. All wallet funding must go
  // through the Paystack checkout flow and be verified server-side via verifyPaystackPayment.
  throw new HttpsError(
    "permission-denied", 
    "Direct wallet funding is not supported. Please use the in-app top-up flow."
  );
});



exports.createVaultAccount = onCall({ region: "us-central1", enforceAppCheck: true, secrets: [PAYSTACK_SECRET_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;

  const secretKey = PAYSTACK_SECRET_KEY.value();
  if (!secretKey) {
    throw new HttpsError("internal", "Paystack secret key is not configured.");
  }

  // 1. Fetch user data to create or fetch Paystack Customer
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");

  const userData = userDoc.data();
  const email = request.auth.token.email || userData.email;
  if (!email) throw new HttpsError("failed-precondition", "Email is required to generate a vault account.");

  let paystackCustomerId = userData.paystack_customer_id;

  try {
    if (!paystackCustomerId) {
      // Create Customer
      const custObj = {
        email: email,
        first_name: userData.first_name || "",
        last_name: userData.last_name || "",
        phone: userData.phone || "",
        metadata: { uid: uid }
      };

      const custRes = await axios.post("https://api.paystack.co/customer", custObj, {
        headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
      });
      
      if (!custRes.data.status) {
        throw new Error(custRes.data.message || "Failed to create Paystack customer");
      }
      
      paystackCustomerId = custRes.data.data.customer_code;
      await db.collection("users").doc(uid).update({ paystack_customer_id: paystackCustomerId });
    }

    // 2. Create Dedicated Virtual Account (DVA)
    const dvaPayload = {
      customer: paystackCustomerId,
      preferred_bank: "titan-paystack" // Usually titan-paystack or wema-bank
    };

    const dvaRes = await axios.post("https://api.paystack.co/dedicated_account", dvaPayload, {
      headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
    });

    if (!dvaRes.data.status) {
      throw new Error(dvaRes.data.message || "Failed to create dedicated account");
    }

    const accountData = dvaRes.data.data;
    const nuban = accountData.account_number;
    const bankName = accountData.bank.name;
    const accountName = accountData.account_name;

    await db.collection("users").doc(uid).update({
      bridgecardNuban: nuban, // Keeping the same variable name so frontend doesn't break
      bridgecardBankName: bankName,
      bridgecardAccountName: accountName,
    });

    return { success: true, nuban: nuban, bankName: bankName, accountName: accountName };
    
  } catch (error) {
    logger.error(`[Wallet] createVaultAccount failed for ${uid}:`, error.response?.data || error.message);
    throw new HttpsError("internal", error.response?.data?.message || error.message);
  }
});
