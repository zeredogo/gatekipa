const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail, requireFields, requireKyc, requirePin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");
const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
const { getMessaging } = require("firebase-admin/messaging");

const PAYSTACK_SECRET_KEY = defineSecret("PAYSTACK_SECRET_KEY");

exports.fundWallet = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  // This endpoint is intentionally disabled. All wallet funding must go
  // through the Paystack checkout flow and be verified server-side via verifyPaystackPayment.
  throw new HttpsError(
    "permission-denied", 
    "Direct wallet funding is not supported. Please use the in-app top-up flow."
  );
});



exports.createVaultAccount = onCall({ region: "us-central1", secrets: [PAYSTACK_SECRET_KEY] }, async (request) => {
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

  const firstName = userData.firstName || userData.first_name || "Gatekipa";
  const lastName = userData.lastName || userData.last_name || "User";
  // Paystack strictly requires a phone number for DVA generation
  const phone = userData.phoneNumber || userData.phone || "08000000000";

  let paystackCustomerId = userData.paystack_customer_id;

  try {
    if (!paystackCustomerId) {
      // Create Customer
      const custObj = {
        email: email,
        first_name: firstName,
        last_name: lastName,
        phone: phone,
        metadata: { uid: uid }
      };

      let custRes;
      try {
        custRes = await axios.post("https://api.paystack.co/customer", custObj, {
          headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
        });
      } catch (err) {
        // If it failed because customer already exists, fetch the customer by email
        logger.warn(`[Wallet] Failed to create customer, attempting to fetch by email: ${email}. Error:`, err.response?.data?.message || err.message);
        custRes = await axios.get(`https://api.paystack.co/customer/${encodeURIComponent(email)}`, {
          headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
        });
      }
      
      if (!custRes.data.status) {
        throw new Error(custRes.data.message || "Failed to create or fetch Paystack customer");
      }
      
      paystackCustomerId = custRes.data.data.customer_code;
      await db.collection("users").doc(uid).update({ paystack_customer_id: paystackCustomerId });
    }

    // Always update/patch the customer details in Paystack. 
    // This handles cases where the customer was originally created with an old name or without a phone number.
    const updateObj = {
      first_name: firstName,
      last_name: lastName,
      phone: phone,
    };
    try {
      await axios.put(`https://api.paystack.co/customer/${paystackCustomerId}`, updateObj, {
        headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
      });
    } catch (e) {
      logger.warn(`Failed to update customer ${paystackCustomerId} before DVA creation`, e.response?.data || e.message);
    }

    // 2. Create Dedicated Virtual Account (DVA)
    // titan-paystack is the preferred bank but is sometimes unavailable — fall back to wema-bank.
    let dvaRes;
    const dvabanks = ["titan-paystack", "wema-bank"];
    let lastDvaError;
    for (const bank of dvabanks) {
      try {
        const dvaPayload = { customer: paystackCustomerId, preferred_bank: bank };
        dvaRes = await axios.post("https://api.paystack.co/dedicated_account", dvaPayload, {
          headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
        });
        if (dvaRes.data.status) break; // success — stop trying
        lastDvaError = new Error(dvaRes.data.message || `DVA creation failed with bank ${bank}`);
      } catch (e) {
        lastDvaError = e;
        logger.warn(`[Wallet] DVA creation failed with bank ${bank}, trying next...`, e.response?.data || e.message);
      }
    }

    if (!dvaRes?.data?.status) {
      throw lastDvaError || new Error("All DVA bank options exhausted");
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

exports.recreateVaultAccount = onCall({ region: "us-central1", secrets: [PAYSTACK_SECRET_KEY] }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const secretKey = PAYSTACK_SECRET_KEY.value();
  
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found");
    const userData = userSnap.data();
    
    const paystackCustomerId = userData.paystack_customer_id;
    if (!paystackCustomerId) {
       throw new HttpsError("failed-precondition", "User has no existing vault account.");
    }

    const email = userData.email || request.auth.token.email;
    const firstName = userData.firstName || userData.first_name || "Gatekipa";
    const lastName = userData.lastName || userData.last_name || "User";
    const phone = userData.phoneNumber || userData.phone || "08000000000";

    // 1. Update Customer Profile
    const updateObj = { first_name: firstName, last_name: lastName, phone: phone };
    await axios.put(`https://api.paystack.co/customer/${paystackCustomerId}`, updateObj, {
      headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" }
    });

    // 2. Fetch and Deactivate Existing DVAs
    const accountsRes = await axios.get(`https://api.paystack.co/dedicated_account?customer=${paystackCustomerId}`, {
      headers: { Authorization: `Bearer ${secretKey}` }
    });
    
    if (accountsRes.data.status && accountsRes.data.data.length > 0) {
       for (const account of accountsRes.data.data) {
           try {
               await axios.delete(`https://api.paystack.co/dedicated_account/${account.id}`, {
                   headers: { Authorization: `Bearer ${secretKey}` }
               });
           } catch (e) {
               logger.warn(`Failed to deactivate old DVA ${account.id}`, e.response?.data || e.message);
           }
       }
    }

    // 3. Create a New Dedicated Virtual Account
    let dvaRes;
    const dvabanks = ["titan-paystack", "wema-bank"];
    let lastDvaError;
    for (const bank of dvabanks) {
      try {
        dvaRes = await axios.post("https://api.paystack.co/dedicated_account", 
          { customer: paystackCustomerId, preferred_bank: bank }, 
          { headers: { Authorization: `Bearer ${secretKey}`, "Content-Type": "application/json" } }
        );
        if (dvaRes.data.status) break;
        lastDvaError = new Error(dvaRes.data.message || `DVA creation failed with bank ${bank}`);
      } catch (e) {
        lastDvaError = e;
      }
    }

    if (!dvaRes?.data?.status) {
      throw lastDvaError || new Error("Failed to regenerate DVA");
    }

    const accountData = dvaRes.data.data;
    const nuban = accountData.account_number;
    const bankName = accountData.bank.name;
    const accountName = accountData.account_name;

    await db.collection("users").doc(uid).update({
      bridgecardNuban: nuban,
      bridgecardBankName: bankName,
      bridgecardAccountName: accountName,
    });

    return { success: true, nuban: nuban, bankName: bankName, accountName: accountName };
    
  } catch (error) {
    logger.error(`[Wallet] recreateVaultAccount failed for ${uid}:`, error.response?.data || error.message);
    throw new HttpsError("internal", error.response?.data?.message || error.message);
  }
});


exports.requestWithdrawal = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const data = request.data;

  requireFields(data, ["amount", "bank_code", "account_number"]);
  const { amount, bank_code, account_number, bank_name, account_name } = data;

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be a strictly positive finite number.");
  }
  
  // 1. System gate — fail-closed on LOCKDOWN
  const mode = await getSystemMode();
  assertSystemAllowsFinancialOps(mode);

  // IAM Enforcement
  await requireKyc(uid);
  
  // SECURE TRANSACTION PIN ENFORCEMENT
  // Neutralizes Client-Side bypass vectors where attackers on new devices
  // approve transactions locally without knowing the user's PIN.
  await requirePin(uid, data.pin);

  const walletRef = db.doc(`users/${uid}/wallet/balance`);
  const withdrawalRef = db.collection("withdrawal_requests").doc();
  const ledgerRef = db.collection("wallet_ledger").doc();
  
  // Phase 1 (Kobo): Convert to integer kobo once
  const amountKobo = Math.round(amount * 100);

  try {
    await db.runTransaction(async (t) => {
      const doc = await t.get(walletRef);
      const walletData = doc.data() || {};
      const currentBalanceKobo = walletData.balance_kobo ?? Math.round((walletData.cached_balance ?? walletData.balance ?? 0) * 100);
      
      if (currentBalanceKobo < amountKobo) {
        throw new HttpsError("failed-precondition", "Insufficient funds for withdrawal.");
      }
      
      const balanceAfterKobo = currentBalanceKobo - amountKobo;

      // 2. Atomically lock funds (deduct from wallet immediately)
      t.set(walletRef, { 
        balance_kobo: FieldValue.increment(-amountKobo),
        cached_balance: FieldValue.increment(-amount), // legacy dual-write
        balance: FieldValue.increment(-amount) // legacy dual-write
      }, { merge: true });
      
      // 3. Create ledger entry reflecting the hold
      t.set(ledgerRef, {
        user_id: uid,
        type: "debit",
        amount_kobo: amountKobo,
        amount, // legacy dual-write
        reference: withdrawalRef.id,
        balance_after_kobo: balanceAfterKobo,
        balance_after: balanceAfterKobo / 100, // legacy dual-write
        source: "withdrawal_hold",
        created_at: FieldValue.serverTimestamp(),
      });
      
      // 4. Create pending withdrawal request
      t.set(withdrawalRef, {
        user_id: uid,
        amount,
        bank_code,
        account_number,
        bank_name: bank_name || "Unknown",
        account_name: account_name || "Unknown",
        status: "PENDING_ADMIN_APPROVAL",
        created_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp()
      });
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("[Wallet] Withdrawal lock failed:", error);
    throw new HttpsError("internal", "Failed to lock funds for withdrawal.");
  }

  // 5. Notify the user of the pending withdrawal (Best Effort)
  try {
    const ownerSnap = await db.collection("users").doc(uid).get();
    const fcmToken = ownerSnap.data()?.fcm_token;
    
    // Add in-app notification
    await db.collection("users").doc(uid).collection("notifications").add({
      title: `Withdrawal Requested (₦${amount.toLocaleString()})`,
      body: `Your withdrawal is pending admin approval. If you did not request this, freeze your account immediately.`,
      timestamp: new Date(),
      isRead: false,
      type: "alert",
    });

    if (fcmToken) {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: `Withdrawal Pending (₦${amount.toLocaleString()})`,
          body: "Your withdrawal request is under review. If you did not request this, contact support immediately.",
        },
        data: { type: "withdrawal_requested", amount: String(amount) },
      });
    }
  } catch (notifyErr) {
    logger.warn("[Wallet] Failed to send withdrawal notification", notifyErr);
  }

  return { success: true, request_id: withdrawalRef.id, status: "PENDING_ADMIN_APPROVAL" };
});
