require("dotenv").config();
process.env.FIREBASE_PROJECT_ID = "gatekipa-bbd1c";

const admin = require("firebase-admin");
const path = require("path");

const serviceAccount = require("./gatekipa.json");
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: "https://gatekipa-bbd1c-default-rtdb.firebaseio.com"
  });
}
const db = admin.firestore();
const { processTransactionInternal } = require("./services/transactionService");

const MOCK_UID = "e2e_sentinel_user";
const MOCK_CARD_ID = "e2e_sentinel_card";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function runSentinelTest() {
  console.log("=== STARTING SENTINEL FEATURES E2E TEST ===\n");

  console.log("[0] Initial Cleanup...");
  await db.collection("users").doc(MOCK_UID).delete().catch(() => {});
  await db.collection("cards").doc(MOCK_CARD_ID).delete().catch(() => {});
  
  const systemStateRef = db.collection("system_state").doc("global");
  await systemStateRef.set({ mode: "NORMAL" }, { merge: true });

  console.log("[1] Creating Test User & Card...");
  await db.collection("users").doc(MOCK_UID).set({
    firstName: "Sentinel",
    lastName: "Tester",
    spending_lock: true // ON BY DEFAULT for first test
  });

  await db.collection("users").doc(MOCK_UID).collection("wallet").doc("balance").set({
    balance_kobo: 1000000 // 10k NGN
  });

  await db.collection("cards").doc(MOCK_CARD_ID).set({
    account_id: MOCK_UID,
    status: "active",
    sudo_card_id: "mock_sudo_card"
  });

  console.log("\n[2] Testing: SPENDING LOCK...");
  let errorCaught = false;
  try {
    await processTransactionInternal({
      type: "card_charge",
      userId: MOCK_UID,
      amount: 1000,
      idempotencyKey: "sentinel_test_1_" + Date.now(),
      metadata: { cardId: MOCK_CARD_ID }
    });
  } catch (err) {
    if (err.message.includes("SPENDING_LOCK_ACTIVE")) {
      errorCaught = true;
      console.log("✅ Spending Lock successfully blocked the transaction.");
    } else {
      console.error("❌ Unexpected error:", err);
    }
  }
  if (!errorCaught) throw new Error("Spending Lock failed to block the transaction!");

  console.log("\n[3] Testing: SYSTEM WIDE BLOCK (Global Toggle)...");
  // Turn off personal spending lock, but turn ON global block
  await db.collection("users").doc(MOCK_UID).update({ spending_lock: false });
  await systemStateRef.set({ mode: "LOCKDOWN" }, { merge: true });

  errorCaught = false;
  try {
    await processTransactionInternal({
      type: "card_charge",
      userId: MOCK_UID,
      amount: 1000,
      idempotencyKey: "sentinel_test_2_" + Date.now(),
      metadata: { cardId: MOCK_CARD_ID }
    });
  } catch (err) {
    if (err.message.includes("SYSTEM_LOCKDOWN")) {
      errorCaught = true;
      console.log("✅ Global Block successfully intercepted the transaction.");
    } else {
      console.error("❌ Unexpected error:", err);
    }
  }
  if (!errorCaught) throw new Error("Global Block failed to block the transaction!");

  console.log("\n[4] Testing: RULE ENGINE (Card strict_limit)...");
  await systemStateRef.set({ mode: "NORMAL" }, { merge: true });
  await db.collection("cards").doc(MOCK_CARD_ID).update({ strict_limit_ngn: 500 });


  errorCaught = false;
  try {
    await processTransactionInternal({
      type: "card_charge",
      userId: MOCK_UID,
      amount: 1000, // Attempting 1000, limit is 500
      idempotencyKey: "sentinel_test_3_" + Date.now(),
      metadata: { cardId: MOCK_CARD_ID }
    });
  } catch (err) {
    if (err.message.includes("RULE_BLOCKED")) {
      errorCaught = true;
      console.log(`✅ Rule Engine intercepted transaction: ${err.message}`);
    } else {
      console.error("❌ Unexpected error:", err);
    }
  }
  if (!errorCaught) throw new Error("Rule Engine failed to block the transaction!");

  console.log("\n[5] Testing: SUCCESSFUL TRANSACTION PASSING ALL TOGGLES...");
  await db.collection("cards").doc(MOCK_CARD_ID).update({ strict_limit_ngn: 5000 }); // Increase limit
  await sleep(1000);
  
  await processTransactionInternal({
    type: "card_charge",
    userId: MOCK_UID,
    amount: 1000, // Should pass
    idempotencyKey: "sentinel_test_4_" + Date.now(),
    metadata: { cardId: MOCK_CARD_ID }
  });

  const walletSnap = await db.collection("users").doc(MOCK_UID).collection("wallet").doc("balance").get();
  console.log("✅ Transaction successful. New balance:", walletSnap.data().balance_kobo);

  console.log("\n=== ALL SENTINEL FEATURES E2E TESTS PASSED ===");

  console.log("\nCleaning up...");
  await db.collection("users").doc(MOCK_UID).delete();
  await db.collection("cards").doc(MOCK_CARD_ID).delete();
  process.exit(0);
}

runSentinelTest().catch(console.error);
