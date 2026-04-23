const admin = require("firebase-admin");
const serviceAccount = require("../../Downloads/gatekeeper-15331-firebase-adminsdk-fbsvc-01e4d6929e.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}
const db = admin.firestore();

const Module = require('module');
const originalRequire = Module.prototype.require;
Module.prototype.require = function(arg) {
  if (arg === 'firebase-functions/v2/https') {
    return {
      onCall: (opts, handler) => handler,
      onRequest: (opts, handler) => handler,
      HttpsError: class HttpsError extends Error {
        constructor(code, message) { super(message); this.code = code; }
      }
    };
  }
  if (arg === 'firebase-functions/logger') return { error: console.error, info: console.log, warn: console.warn };
  if (arg === 'firebase-functions/params') return { defineSecret: () => ({ value: "secret" }), defineString: () => ({ value: "string" }) };
  return originalRequire.apply(this, arguments);
};

const cardService = require("./services/cardService");

async function run() {
  const uid = "test_e2e_user_" + Date.now();
  const accountId = "test_acc_" + Date.now();
  
  await db.collection("accounts").doc(accountId).set({
    id: accountId,
    owner_user_id: uid,
    plan: "instant"
  });
  
  await db.collection("users").doc(uid).set({ kycStatus: "verified" });

  async function attemptCard(plan) {
    console.log(`\n--- Plan: ${plan} ---`);
    await db.collection("accounts").doc(accountId).update({ plan });
    try {
      const res = await cardService.createVirtualCard({
        auth: { uid, token: { email_verified: true } },
        data: { account_id: accountId, name: "Test Card" }
      });
      console.log("✅ Success! Card ID:", res.cardId);
    } catch (e) {
      console.log("❌ REJECTED:", e.message);
    }
  }

  // 1. Instant Plan (Max 1)
  await attemptCard("instant");
  await attemptCard("instant");

  // 2. Activation Plan (Max 2)
  await attemptCard("activation");
  await attemptCard("activation");

  // 3. Premium Plan (Max 3)
  await attemptCard("premium");
  await attemptCard("premium");

  // 4. Business Plan (Max 5)
  await attemptCard("business");
  await attemptCard("business");
  await attemptCard("business");
  
  console.log("\n=== MATRIX VERIFICATION COMPLETE ===");
  process.exit(0);
}

run().catch(console.error);
