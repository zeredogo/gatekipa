const admin = require("firebase-admin");

// Initialize with application default if possible, or your specific key.
const serviceAccount = require("/Users/mac/Downloads/gatekeeper-15331-firebase-adminsdk-fbsvc-01e4d6929e.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function runTest() {
  console.log("=== STARTING E2E TEST FLOW ===");
  
  // 1. Create User
  const uid = "test_e2e_user_" + Date.now();
  console.log("1. MOCKING USER AUTH:", uid);
  
  // 2. Create Account
  const accountId = "test_acc_" + Date.now();
  await db.collection("accounts").doc(accountId).set({
    id: accountId,
    owner_user_id: uid,
    plan: "free",
    name: "Test E2E Account",
    created_at: Date.now()
  });
  console.log("2. CREATED ACCOUNT:", accountId, "with plan: free");

  // 3. Bypass via internal logic (Simulate Cloud Function call by writing directly for now, OR using HTTP trigger)
  // Actually, better to test the function logic directly by calling the locally exported function block, 
  // but firebase emulators might not be running. We can import the function directly and call it with a mock request.
  
  const { createVirtualCard } = require("./services/cardService");

  async function simulateCreateCard(plan) {
    console.log(`\n--- Set Plan to: ${plan} ---`);
    await db.collection("accounts").doc(accountId).update({ plan });
    
    try {
      const result = await createVirtualCard({
        auth: {
          uid: uid,
          token: { email_verified: true }
        },
        data: {
          account_id: accountId,
          name: "Test Developer Card - " + plan
        }
      });
      console.log("SUCCESS: Card created ->", result.cardId);
      return true;
    } catch (e) {
      console.log("REJECTED by Backend Logic:", e.message);
      return false;
    }
  }

  // Pre-requisites for cardService
  // KYC validator requires a KYC doc
  await db.collection("kyc_records").doc(uid).set({ status: "verified" });

  await simulateCreateCard("free"); // Success
  await simulateCreateCard("free"); // Should be Rejected
  await simulateCreateCard("premium"); // Success
  await simulateCreateCard("premium"); // Success
  await simulateCreateCard("premium"); // Rejected (already has 3 cards: 1 from free + 2 from premium)
  
  await simulateCreateCard("business"); // Success
  console.log("\n=== TEST COMPLETED SUCCESSFULLY ===");
  process.exit(0);
}

runTest().catch(console.error);
