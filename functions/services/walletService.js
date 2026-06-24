const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail, requireFields, requireKyc, requirePin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");
const { getSystemMode, assertSystemAllowsFinancialOps } = require("../core/systemState");
const { getMessaging } = require("firebase-admin/messaging");


exports.fundWallet = onCall({ region: "us-central1" }, async (request) => {
  requireVerifiedEmail(request.auth);
  // This endpoint is intentionally disabled. All wallet funding must go
  // through the Paystack checkout flow and be verified server-side via verifyPaystackPayment.
  throw new HttpsError(
    "permission-denied", 
    "Direct wallet funding is not supported. Please use the in-app top-up flow."
  );
});


const SAFEHAVEN_CLIENT_ID = defineSecret("SAFEHAVEN_CLIENT_ID");
const SAFEHAVEN_PRIVATE_KEY = defineSecret("SAFEHAVEN_PRIVATE_KEY");

exports.initiateVaultVerification = onCall({ region: "us-central1", secrets: [SAFEHAVEN_CLIENT_ID, SAFEHAVEN_PRIVATE_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;

  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");

  const { initiateSafeHavenVerification } = require("./safehavenService");
  return await initiateSafeHavenVerification(uid, userDoc.data());
});

exports.createVaultAccount = onCall({ region: "us-central1", secrets: [SAFEHAVEN_CLIENT_ID, SAFEHAVEN_PRIVATE_KEY] }, async (request) => {
  requireVerifiedEmail(request.auth);
  const uid = request.auth.uid;
  const otp = request.data?.otp;
  
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");

  const userData = userDoc.data();
  // SafeHaven requires fresh OTP and identityId per attempt
  const identityId = request.data?.identityId || userData.safehaven_identity_id;

  if (!identityId) {
    throw new HttpsError("failed-precondition", "Identity ID missing. Please verify your KYC identity first.");
  }

  if (userData.safehaven_dva_account_number) {
    throw new HttpsError("already-exists", "Virtual Account already exists.");
  }

  const { generateSafeHavenDva } = require("./safehavenService");
  return await generateSafeHavenDva(uid, userData, identityId, otp);
});

exports.recreateVaultAccount = exports.createVaultAccount;



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
