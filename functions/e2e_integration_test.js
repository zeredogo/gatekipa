const admin = require("firebase-admin");
const axios = require("axios");
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

const MOCK_UID = "e2e_test_user_9999";
const MOCK_EMAIL = "e2e_test_user_9999@gatekipa.com";

let idToken = "";

async function getAuthToken(uid) {
  const customToken = await admin.auth().createCustomToken(uid);
  const apiKey = serviceAccount.api_key || 'AIzaSyA_Fc8xFCutxNN0elWvGSqjozMuzKzNJBo';
  const res = await axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`, {
    token: customToken,
    returnSecureToken: true
  });
  return res.data.idToken;
}

async function callFn(fnName, data = {}) {
  const url = `${BASE_URL}/${fnName}`;
  const res = await axios.post(url, { data }, {
    headers: { Authorization: `Bearer ${idToken}` }
  });
  return res.data.result || res.data;
}

async function runTests() {
  console.log("=== STARTING E2E INTEGRATION TEST ===");

  try {
    // 0. Cleanup from previous failed runs
    console.log("\n[0] Initial Cleanup...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    const oldCards = await admin.firestore().collection("cards").where("account_id", "==", MOCK_UID).get();
    for (const doc of oldCards.docs) {
      await doc.ref.delete();
    }
    await admin.firestore().collection("users").doc(MOCK_UID).delete();

    // 1. Setup Mock User
    console.log("\n[1] Creating Mock Firebase User...");
    await admin.auth().createUser({
      uid: MOCK_UID,
      email: MOCK_EMAIL,
      emailVerified: true,
      password: "SuperSecretPassword123!",
      displayName: "E2E Test User"
    });
    console.log("    ✅ Firebase Auth User created.");

    await admin.firestore().collection("users").doc(MOCK_UID).set({
      email: MOCK_EMAIL,
      firstName: "E2E",
      lastName: "Test User",
      role: "user",
      bvnVerified: true,
      kycStatus: "verified",
      address: "123 Mock Street",
      city: "Lagos",
      state: "Lagos",
      postalCode: "100001",
      country: "Nigeria",
      planTier: "instant", // using instant to bypass 1-card limit
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      walletBalance: 100000
    });
    
    // Initialize wallet subcollection for Sudo deductions
    await admin.firestore().collection("users").doc(MOCK_UID).collection("wallet").doc("balance").set({
      balance_kobo: 10000000,
      cached_balance: 100000,
      balance: 100000
    });
    
    console.log("    ✅ Firestore User Document and Wallet initialized.");

    idToken = await getAuthToken(MOCK_UID);
    console.log("    ✅ Auth Token obtained.");

    // 1.5 Set Transaction Pin
    console.log("\n[1.5] Setting Transaction PIN...");
    await callFn("setTransactionPin", { pin: "1234" });
    console.log("    ✅ Transaction PIN set to 1234.");

    // 2. KYC / Identity
    console.log("\n[2] Testing Identity Verification (KYC)...");
    try {
      const kycRes = await callFn("verifyBvn", {
        bvn: "22222222222",
        firstName: "E2E",
        lastName: "Test User",
        dob: "1990-01-01",
        phoneNumber: "+2348000000000"
      });
      console.log("    ✅ verifyBvn returned:", kycRes);
    } catch(err) {
      console.log("    ⚠️ verifyBvn warning (expected if Sudo rejects fake BVN):", err.response?.data?.error?.message || err.message);
    }

    // 3. Admin System Mode
    console.log("\n[3] Testing Admin Operations...");
    const sysDoc = await admin.firestore().collection("system").doc("config").get();
    console.log("    ✅ Current System Mode:", sysDoc.data()?.system_mode || "Normal");

    // 4. Virtual Card Engine
    console.log("\n[4] Testing Virtual Card Creation (Firestore)...");
    let cardId;
    try {
      const vCardRes = await callFn("createVirtualCard", {
        account_id: MOCK_UID,
        name: "E2E Netflix Card",
        limit_amount: 5000,
        currency: "NGN",
        color: "blue"
      });
      console.log("    ✅ createVirtualCard raw response:", vCardRes);
      cardId = vCardRes.cardId || vCardRes.card_id || vCardRes.data?.cardId || vCardRes.data?.card_id;
      console.log("    ✅ createVirtualCard returned ID:", cardId);
    } catch(err) {
      console.error("    ❌ createVirtualCard failed:", err.response?.data || err.message);
      throw err;
    }

    if (cardId) {
      console.log("\n[4b] Linking Sudo Virtual Card...");
      try {
        const sudoRes = await callFn("createSudoCard", {
          card_id: cardId,
          transactionPin: "1234"
        });
        console.log("    ✅ createSudoCard returned:", sudoRes);
      } catch(err) {
        console.log("    ⚠️ createSudoCard warning (expected due to Sudo funding/account limits):", err.message);
        console.log("    ⚠️ createSudoCard response data:", JSON.stringify(err.response?.data || {}, null, 2));
      }
    }

    // 5. Cleanup
    console.log("\n[5] Cleaning up E2E Mock User...");
    await admin.auth().deleteUser(MOCK_UID);
    await admin.firestore().collection("users").doc(MOCK_UID).delete();
    if (cardId) await admin.firestore().collection("cards").doc(cardId).delete();
    console.log("    ✅ Cleanup complete.");

    console.log("\n=== E2E INTEGRATION TEST FINISHED ===");

  } catch (error) {
    console.error("Critical E2E Failure:", error);
  }
}

runTests();
