const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");
const serviceAccount = require("./gatekipa.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const PROJECT_ID = "gatekipa-bbd1c";
const REGION = "us-central1";

const USE_LOCAL = process.env.USE_LOCAL === "true";
const BASE_URL = USE_LOCAL 
  ? `http://127.0.0.1:5001/${PROJECT_ID}/${REGION}` 
  : `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

const MOCK_UID = "e2e_sudo_webhook_user";
const MOCK_DVA_ID = "mock_sudo_dva_007";
const AMOUNT = 5000;

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function runTest() {
  console.log("=== STARTING SUDO WEBHOOK E2E TEST ===");

  try {
    console.log("\n[0] Initial Cleanup...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}
    try { await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).delete(); } catch (e) {}
    console.log("Cleanup complete.");

    console.log("\n[1] Creating Test User with mock Sudo DVA ID...");
    await admin.auth().createUser({ uid: MOCK_UID, email: "e2e_sudo_webhook@gatekipa.com" });
    await admin.firestore().collection("users").doc(MOCK_UID).set({
      email: "e2e_sudo_webhook@gatekipa.com",
      sudo_dva_id: MOCK_DVA_ID,
      fcm_token: "mock_fcm_token_123", // To test notification doesn't crash
      kycStatus: "verified",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(`User created. UID: ${MOCK_UID}, DVA: ${MOCK_DVA_ID}`);

    // Initial wallet
    await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).set({
      balance: 0,
      balance_kobo: 0,
      cached_balance: 0
    });

    console.log("\n[2] Firing Sudo Webhook (account.deposit)...");
    
    const eventId = `evt_mock_${Date.now()}`;
    const payload = {
      event: "account.deposit",
      data: {
        _id: eventId,
        amount: AMOUNT, // Sudo sends numeric amount. Let's say 5000 NGN.
        currency: "NGN",
        accountId: MOCK_DVA_ID,
        type: "credit",
        createdAt: new Date().toISOString()
      }
    };

    const secret = process.env.SUDO_WEBHOOK_SECRET || "gatekipa_sudo_webhook_secret_2024!";
    const signature = crypto.createHmac("sha512", secret).update(JSON.stringify(payload)).digest("hex");

    const url = `${BASE_URL}/sudoWebhook`;
    console.log(`POST ${url}`);
    
    const res = await axios.post(url, payload, {
      headers: {
        "Content-Type": "application/json",
        "x-sudo-signature": secret
      }
    });

    console.log(`Webhook responded with status ${res.status}:`, res.data);

    console.log("\n[3] Verifying Wallet Balance...");
    await sleep(2000); // Wait for async operations to complete
    
    const walletSnap = await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).get();
    const walletData = walletSnap.data();
    
    console.log("Wallet Data:", walletData);
    
    // Check if the balance_kobo is updated correctly
    if (walletData.balance_kobo !== AMOUNT * 100) {
      throw new Error(`Wallet balance mismatch! Expected ${AMOUNT * 100} kobo, got ${walletData.balance_kobo}`);
    }
    console.log("✅ Wallet successfully funded by webhook.");

    console.log("\n[4] Firing Duplicate Webhook (Idempotency Test)...");
    const res2 = await axios.post(url, payload, {
      headers: {
        "Content-Type": "application/json",
        "x-sudo-signature": secret
      }
    });
    console.log(`Duplicate webhook responded with status ${res2.status}:`, res2.data);
    
    await sleep(2000);
    const walletSnap2 = await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).get();
    if (walletSnap2.data().balance_kobo !== AMOUNT * 100) {
      throw new Error(`Idempotency failed! Balance changed to ${walletSnap2.data().balance_kobo} kobo on duplicate webhook.`);
    }
    console.log("✅ Idempotency working correctly.");

    console.log("\n[5] Checking Notifications...");
    const notifsSnap = await admin.firestore().collection(`users/${MOCK_UID}/notifications`).get();
    if (notifsSnap.empty) {
      throw new Error("No notification created for wallet funding.");
    }
    console.log(`✅ Found ${notifsSnap.size} notification(s).`);

    console.log("\n=== ALL SUDO WEBHOOK TESTS PASSED ===");

  } catch (err) {
    console.error("Test Failed:", err.response ? err.response.data : err.message);
  } finally {
    console.log("\nCleaning up...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}
    process.exit(0);
  }
}

runTest();
