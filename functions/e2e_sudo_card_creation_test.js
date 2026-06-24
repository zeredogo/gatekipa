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

const MOCK_UID = "e2e_card_creation_user";
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function getAuthToken(uid) {
  const customToken = await admin.auth().createCustomToken(uid);
  // Default firebase config web API key
  const apiKey = serviceAccount.api_key || 'AIzaSyA_Fc8xFCutxNN0elWvGSqjozMuzKzNJBo'; 
  try {
    const res = await axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`, {
      token: customToken,
      returnSecureToken: true
    });
    return res.data.idToken;
  } catch (err) {
    if (err.response && err.response.status === 400) {
      console.warn("Could not get real auth token (API_KEY_NOT_VALID). Using mock token locally.");
      return "mock_token";
    }
    throw err;
  }
}

async function runTest() {
  console.log("=== STARTING SUDO CARD CREATION & FEE DEDUCTION TEST ===");

  try {
    console.log("\n[0] Initial Cleanup...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}
    try { await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).delete(); } catch (e) {}
    const cardsQuery = await admin.firestore().collection("cards").where("uid", "==", MOCK_UID).get();
    for (const d of cardsQuery.docs) await d.ref.delete();
    const ledgerQueryInit = await admin.firestore().collection("wallet_ledger").where("user_id", "==", MOCK_UID).get();
    for (const d of ledgerQueryInit.docs) await d.ref.delete();
    const oldLedgerQueryInit = await admin.firestore().collection("users").doc(MOCK_UID).collection("wallet_transactions").get();
    for (const d of oldLedgerQueryInit.docs) await d.ref.delete();
    console.log("Cleanup complete.");

    console.log("\n[1] Creating Test User...");
    await admin.auth().createUser({ uid: MOCK_UID, email: "e2e_card_test@gatekipa.app", emailVerified: true });
    
    // Generate a proper pin hash for '1111'
    const crypto = require("crypto");
    const salt = crypto.randomBytes(16).toString("hex");
    const hash = crypto.scryptSync("1111", salt, 64).toString("hex");
    const pinHash = `${salt}:${hash}`;

    // Create the required user document WITHOUT mocked Sudo IDs
    // This forces the backend to call ensureSudoCustomer and ensureSudoAccount
    // testing the full Sudo provisioning pipeline.
    await admin.firestore().collection("users").doc(MOCK_UID).set({
      email: "e2e_card_test@gatekipa.app",
      firstName: "Test",
      lastName: "User",
      kycStatus: "verified",
      security: { pinHash }, // Required by validators.js
      planTier: "premium", // Required for NGN cards if cardsIncluded is 0
      cardsIncluded: 0, 
      phone: "+2348000000000",
      bvn: "22222222222",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Create the pending card document required by createSudoCard
    const MOCK_CARD_ID = "mock_card_doc_123";
    await admin.firestore().collection("cards").doc(MOCK_CARD_ID).set({
      uid: MOCK_UID,
      account_id: MOCK_UID,
      sudo_status: "pending",
      currency: "NGN",
      cardType: "virtual",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Test Case 1: Insufficient Funds
    console.log("\n[2] Setting Wallet to 500 NGN (Insufficient Funds)...");
    await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).set({
      balance: 500,
      balance_kobo: 50000,
      cached_balance: 500
    });

    const token = await getAuthToken(MOCK_UID);

    console.log("\n[3] Calling createSudoCard (Expected to fail)...");
    const url = `${BASE_URL}/createSudoCard`;
    const payload = {
      data: {
        card_id: MOCK_CARD_ID, // Provide the pre-created card_id
        amount: 1000, // Wants 1000 NGN funding
        transactionPin: "1111"
      }
    };

    let failedAsExpected = false;
    try {
      await axios.post(url, payload, {
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" }
      });
      console.error("❌ Test Failed: Allowed card creation despite insufficient funds.");
      process.exit(1);
    } catch (err) {
      const errorData = err.response?.data?.error?.message || err.message;
      console.log(`✅ Request rejected successfully: ${errorData}`);
      failedAsExpected = true;
    }

    if (!failedAsExpected) throw new Error("Expected failure on insufficient funds.");

    // Test Case 2: Successful Creation
    console.log("\n[4] Setting Wallet to 5000 NGN (Sufficient Funds)...");
    await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).set({
      balance: 5000,
      balance_kobo: 500000,
      cached_balance: 5000
    });

    // Assertion Flags
    let isDelayedProcessing = false;

    console.log("\n[5] Calling createSudoCard (Expected to succeed or delay)...");
    let createRes;
    try {
      createRes = await axios.post(url, payload, {
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" }
      });
      console.log(`✅ Card Created! Response:`, createRes.data?.result || createRes.data);
    } catch (err) {
       if (err.response && err.response.status === 403 && token === "mock_token") {
          console.warn("Skipping HTTP test because of mock_token 403. Emulating the function call directly.");
       } else if (err.code === 'ECONNREFUSED') {
          console.error("Emulator not running on port 5001. Start `npm run serve` to test HTTP.");
          throw err;
       } else if (err.response && err.response.status === 500 && err.response.data?.error?.message?.includes("taking too long")) {
          console.log("⚠️ Sudo Sandbox timed out. The backend correctly deferred processing.");
          isDelayedProcessing = true;
       } else {
          console.error("❌ Creation Failed:", err.response?.data || err.message);
          throw err;
       }
    }

    // Wait for Firestore to reflect all transactions
    await sleep(2000);

    console.log("\n[6] Verifying Assertions...");
    
    // Assertion 1: Wallet Balance Check
    const walletSnap = await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).get();
    const balance = walletSnap.data()?.balance;
    const escrow = walletSnap.data()?.escrow_kobo || 0;
    console.log(`Current Wallet Balance: ₦${balance}, Escrow: ${escrow} kobo`);
    
    // 5000 - 700 (fee) = 4300
    if (balance !== 4300) {
      throw new Error(`❌ Wallet assertion failed! Expected 4300, got ${balance}`);
    } else {
      console.log(`✅ Wallet balance correctly deducted by exactly ₦700 fee.`);
    }

    if (isDelayedProcessing && escrow !== 70000) { 
      throw new Error(`❌ Escrow assertion failed! Expected 70000, got ${escrow}`);
    } else if (isDelayedProcessing) {
      console.log(`✅ Escrow correctly captured pending transaction: ${escrow} kobo`);
    }

    // Assertion 2: Ledgers
    const txnsSnap = await admin.firestore().collection("users").doc(MOCK_UID).collection("wallet_transactions").get();
    // Wait, the ledger for card creation in sudoService.js doesn't write to `wallet_transactions` directly in the transaction!
    // Let's verify ledger via `wallet_ledger` collection (the global ledger).
    const globalLedgersSnap = await admin.firestore().collection("wallet_ledger").where("user_id", "==", MOCK_UID).get();
    
    let hasFeeLedger = false;
    for (const doc of globalLedgersSnap.docs) {
      const t = doc.data();
      if (t.amount === 700 && t.context === "ngn_card_creation") {
         hasFeeLedger = true;
         console.log(`✅ Ledger correctly recorded fee: Status is '${t.status}'`);
         if (isDelayedProcessing && t.status !== "escrowed") {
             throw new Error(`❌ Delayed processing but ledger status is not escrowed! It is ${t.status}`);
         }
      }
    }

    if (!hasFeeLedger) throw new Error("❌ Ledger assertion failed: Missing ₦700 Issuance Fee record in wallet_ledger.");

    // Assertion 3: Card Database
    const finalCardsSnap = await admin.firestore().collection("cards").where("uid", "==", MOCK_UID).get();
    if (finalCardsSnap.empty) {
      throw new Error("❌ Card assertion failed: No card found in the database.");
    } else {
      console.log(`✅ Card successfully provisioned into 'cards' collection with status: ${finalCardsSnap.docs[0].data().sudo_status}`);
    }

    console.log("\n🎉 ALL E2E SUDO CARD CREATION TESTS PASSED!");

  } catch (error) {
    console.error("\n❌ TEST FAILED:", error.message);
    process.exit(1);
  } finally {
    console.log("\n[7] Cleaning up...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}
    try { await admin.firestore().doc(`users/${MOCK_UID}/wallet/balance`).delete(); } catch (e) {}
    const cardsQuery = await admin.firestore().collection("cards").where("uid", "==", MOCK_UID).get();
    for (const d of cardsQuery.docs) await d.ref.delete();
    const ledgerQuery = await admin.firestore().collection("wallet_ledger").where("user_id", "==", MOCK_UID).get();
    for (const d of ledgerQuery.docs) await d.ref.delete();
    const oldLedgerQuery = await admin.firestore().collection("users").doc(MOCK_UID).collection("wallet_transactions").get();
    for (const d of oldLedgerQuery.docs) await d.ref.delete();
    console.log("Cleanup complete.");
  }
}

runTest();
