require("dotenv").config({ path: "../.env" }); // Assuming we run from functions dir
const admin = require("firebase-admin");
const axios = require("axios");
const serviceAccount = require("./gatekipa.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

// Sandbox/Prod endpoints based on your environment.
// For testing/backfilling safely without a real .env if it uses the sandbox key
const SUDO_API_URL = process.env.SUDO_API_URL || "https://api.sandbox.sudo.cards";
const SUDO_API_KEY = process.env.SUDO_API_KEY;

if (!SUDO_API_KEY) {
  console.error("❌ Missing SUDO_API_KEY in .env");
  process.exit(1);
}

const client = axios.create({
  baseURL: SUDO_API_URL,
  headers: {
    Authorization: `Bearer ${SUDO_API_KEY}`,
    "Content-Type": "application/json",
  },
});

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function runBackfill() {
  console.log("=== Starting Sudo Africa Data Migration & Backfill ===");

  try {
    const usersSnapshot = await db.collection("users").get();
    let corruptedCleared = 0;
    let provisioned = 0;

    // Track assigned accounts to find duplicates
    const assignedAccounts = new Set();
    const duplicateAccounts = new Set();

    console.log(`Analyzing ${usersSnapshot.size} users for corrupted metadata...`);

    // First Pass: Find Duplicates & Cleardown
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      let isCorrupted = false;
      const updates = {};

      const accountId = data.sudo_account_id;
      
      if (accountId) {
        if (accountId.startsWith("mock_sudo_dva_")) {
          isCorrupted = true;
        } else if (assignedAccounts.has(accountId)) {
          isCorrupted = true;
          duplicateAccounts.add(accountId);
        } else {
          assignedAccounts.add(accountId);
        }
      }

      if (isCorrupted) {
        updates.sudo_account_id = admin.firestore.FieldValue.delete();
      }

      // If there are other corrupted mock fields like customer_id
      if (data.sudo_customer_id && data.sudo_customer_id.startsWith("mock_")) {
        updates.sudo_customer_id = admin.firestore.FieldValue.delete();
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.update(updates);
        corruptedCleared++;
        console.log(`[CLEARED] Removed corrupted/duplicate Sudo data for UID: ${doc.id}`);
      }
    }

    // Now loop back over the duplicates and clear them for the *original* user too
    // Because if 2 users had the same account, neither of them should own it (it's compromised/shared).
    if (duplicateAccounts.size > 0) {
      for (const accountId of duplicateAccounts) {
        const snap = await db.collection("users").where("sudo_account_id", "==", accountId).get();
        for (const duplicateDoc of snap.docs) {
           await duplicateDoc.ref.update({ sudo_account_id: admin.firestore.FieldValue.delete() });
           corruptedCleared++;
           console.log(`[CLEARED] Removed shared duplicate Sudo account for UID: ${duplicateDoc.id}`);
        }
      }
    }

    console.log(`\n=== Cleared ${corruptedCleared} corrupted Sudo records. ===\n`);
    console.log(`Starting Provisioning for eligible users...`);

    // Second Pass: Provisioning DVAs
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      const uid = doc.id;
      
      // Check if they need an account
      const needsAccount = !data.sudo_account_id && !data.sudo_customer_id;
      if (!needsAccount) continue;

      // Check if they have a balance
      const walletDoc = await db.collection("users").doc(uid).collection("wallet").doc("balance").get();
      const walletBalance = walletDoc.exists ? (walletDoc.data().balance || 0) : 0;

      // If they have a balance, they are an active legacy user who needs migration
      if (walletBalance > 0) {
        try {
          console.log(`[PROVISIONING] UID: ${uid} (Balance: ${walletBalance})`);
          
          let customerId = data.sudo_customer_id;
          
          // 1. Create Customer if missing
          if (!customerId) {
            const customerPayload = {
              type: "individual",
              name: `${data.firstName || 'Legacy'} ${data.lastName || 'User'}`,
              emailAddress: data.email || `${uid}@gatekipa.app`,
              phoneNumber: data.phone || "08000000000",
            };
            const cusRes = await client.post("/customers", customerPayload);
            customerId = cusRes.data?.data?._id || cusRes.data?.data?.id;
            
            if (!customerId) throw new Error("Missing customer ID in response");
            await doc.ref.update({ sudo_customer_id: customerId });
          }

          // 2. Create Account
          const accountPayload = {
            type: "account",
            currency: "NGN",
            customerId: customerId
          };
          const accRes = await client.post("/accounts", accountPayload);
          const accountId = accRes.data?.data?._id || accRes.data?.data?.id;

          if (!accountId) throw new Error("Missing account ID in response");
          await doc.ref.update({ sudo_account_id: accountId });
          
          provisioned++;
          console.log(`[SUCCESS] Provisioned UID ${uid} -> Customer: ${customerId}, Account: ${accountId}`);

          // Rate limit protection
          await delay(500); 
        } catch (error) {
          const msg = error.response?.data?.message || error.message;
          console.error(`[ERROR] Failed to provision UID ${uid}: ${msg}`);
        }
      } else {
        console.log(`[SKIPPED] UID: ${uid} has 0 balance and no Sudo account. Proceeding...`);
      }
    }

    console.log(`\n✅ Backfill Complete. Provisioned ${provisioned} new accounts.`);

  } catch (error) {
    console.error("Migration failed:", error);
  }
}

runBackfill();
