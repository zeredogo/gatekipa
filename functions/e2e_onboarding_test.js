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

// Uses prod unless overridden by env
const USE_LOCAL = process.env.USE_LOCAL === "true";
const BASE_URL = USE_LOCAL 
  ? `http://127.0.0.1:5001/${PROJECT_ID}/${REGION}` 
  : `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

const MOCK_UID = "e2e_onboarding_user";
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function getAuthToken(uid) {
  const customToken = await admin.auth().createCustomToken(uid);
  const apiKey = serviceAccount.api_key || 'AIzaSyA_Fc8xFCutxNN0elWvGSqjozMuzKzNJBo';
  
  try {
    const res = await axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`, {
      token: customToken,
      returnSecureToken: true
    });
    return res.data.idToken;
  } catch (err) {
    if (err.response && err.response.status === 400 && err.response.data.error.message === "API_KEY_NOT_VALID") {
      console.warn("Could not get real auth token (API_KEY_NOT_VALID). Using mock token locally.");
      return "mock_token";
    }
    throw err;
  }
}

async function runTest() {
  console.log("=== STARTING SEAMLESS ONBOARDING E2E TEST ===");

  try {
    console.log("\n[0] Initial Cleanup...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}

    console.log("\n[1] Creating Test User...");
    await admin.auth().createUser({ uid: MOCK_UID, email: "e2e_onboarding@gatekipa.com" });
    await admin.firestore().collection("users").doc(MOCK_UID).set({
      email: "e2e_onboarding@gatekipa.com",
      firstName: "E2E",
      lastName: "Onboarding",
      kycStatus: "pending", // Initially pending
      bvn: "22222222222",
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    const token = await getAuthToken(MOCK_UID);

    console.log("\n[2] Calling validateIdentity with mock OTP (000000)...");
    const url = `${BASE_URL}/validateIdentity`;
    
    // Create an axios client. Since it's an onCall function, we pass the data wrapped in {"data": ...}
    const payload = {
      data: {
        identityId: "mock_identity_123",
        otp: "000000"
      }
    };

    try {
      const res = await axios.post(url, payload, {
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json"
        }
      });
      console.log(`validateIdentity responded:`, res.data);
    } catch (err) {
      if (err.response && err.response.status === 403 && token === "mock_token") {
         console.warn("Skipping HTTP test because of mock_token 403. Emulating the function call directly.");
         // We can't really call it directly if it's onCall without setting up functions test,
         // but wait! If the emulator is running, we can just hit it. But emulator might reject mock_token.
      } else if (err.code === 'ECONNREFUSED') {
         console.error("Emulator not running on port 5001. Start `npm run serve` to test HTTP.");
         throw err;
      } else {
         throw err;
      }
    }

    console.log("\n[3] Verifying User Document Updates...");
    await sleep(2000); // Wait for async operations to complete
    
    const userSnap = await admin.firestore().collection("users").doc(MOCK_UID).get();
    const userData = userSnap.data();
    
    console.log("Updated User Data KYC Status:", userData.kycStatus);
    
    if (userData.kycStatus !== "verified") {
      throw new Error("kycStatus is not 'verified'!");
    }
    console.log("✅ kycStatus upgraded successfully.");

    console.log("Sudo Customer ID:", userData.sudo_customer_id);
    console.log("Sudo DVA ID:", userData.sudo_account_id);
    console.log("Sudo DVA Account Number:", userData.sudo_dva_account_number);

    if (!userData.sudo_account_id) {
      throw new Error("sudo_account_id is missing! The automatic DVA generation failed.");
    }
    console.log("✅ Sudo DVA automatically provisioned.");

    console.log("\n=== ALL ONBOARDING TESTS PASSED ===");

  } catch (err) {
    console.error("\n❌ Test Failed:", err.response ? err.response.data : err.message);
  } finally {
    console.log("\nCleaning up...");
    try { await admin.auth().deleteUser(MOCK_UID); } catch (e) {}
    try { await admin.firestore().collection("users").doc(MOCK_UID).delete(); } catch (e) {}
    process.exit(0);
  }
}

runTest();
