const admin = require("firebase-admin");
const serviceAccount = require("./gatekipa.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function migrateUsers() {
  console.log("=== Migrating Users Collection ===");
  const usersSnapshot = await db.collection("users").get();
  let migrated = 0;

  for (const doc of usersSnapshot.docs) {
    const data = doc.data();
    const updates = {};
    const deletions = {};

    if (data.bridgecardNuban) {
      updates.vaultNuban = data.bridgecardNuban;
      deletions.bridgecardNuban = admin.firestore.FieldValue.delete();
    }
    if (data.bridgecardBankName) {
      updates.vaultBankName = data.bridgecardBankName;
      deletions.bridgecardBankName = admin.firestore.FieldValue.delete();
    }
    if (data.bridgecardAccountName) {
      updates.vaultAccountName = data.bridgecardAccountName;
      deletions.bridgecardAccountName = admin.firestore.FieldValue.delete();
    }
    if (data.bridgecard_cardholder_id) {
      updates.vault_cardholder_id = data.bridgecard_cardholder_id;
      deletions.bridgecard_cardholder_id = admin.firestore.FieldValue.delete();
    }

    if (Object.keys(updates).length > 0) {
      await doc.ref.update({ ...updates, ...deletions });
      migrated++;
    }
  }
  console.log(`Migrated ${migrated} users.`);
}

async function migrateCards() {
  console.log("\n=== Migrating Cards Collection ===");
  const cardsSnapshot = await db.collection("cards").get();
  let migrated = 0;

  for (const doc of cardsSnapshot.docs) {
    const data = doc.data();
    const updates = {};
    const deletions = {};

    if (data.bridgecard_status) {
      updates.sudo_status = data.bridgecard_status;
      deletions.bridgecard_status = admin.firestore.FieldValue.delete();
    }
    if (data.bridgecard_card_id) {
      updates.sudo_card_id = data.bridgecard_card_id;
      deletions.bridgecard_card_id = admin.firestore.FieldValue.delete();
    }
    if (data.bridgecard_currency) {
      updates.sudo_currency = data.bridgecard_currency;
      deletions.bridgecard_currency = admin.firestore.FieldValue.delete();
    }

    if (Object.keys(updates).length > 0) {
      await doc.ref.update({ ...updates, ...deletions });
      migrated++;
    }
  }
  console.log(`Migrated ${migrated} cards.`);
}

async function migrateTransactions() {
  console.log("\n=== Migrating Transactions (Ledgers) ===");
  const usersSnapshot = await db.collection("users").get();
  let migrated = 0;

  for (const userDoc of usersSnapshot.docs) {
    const txnsSnapshot = await userDoc.ref.collection("wallet_transactions").get();
    for (const doc of txnsSnapshot.docs) {
      const data = doc.data();
      const updates = {};
      const deletions = {};

      if (data.bridgecardRef) {
        updates.providerRef = data.bridgecardRef;
        deletions.bridgecardRef = admin.firestore.FieldValue.delete();
      }
      if (data.paystackRef) {
        updates.providerRef = data.paystackRef;
        deletions.paystackRef = admin.firestore.FieldValue.delete();
      }

      if (Object.keys(updates).length > 0) {
        await doc.ref.update({ ...updates, ...deletions });
        migrated++;
      }
    }
  }
  console.log(`Migrated ${migrated} transactions.`);
}

async function runAll() {
  try {
    await migrateUsers();
    await migrateCards();
    await migrateTransactions();
    console.log("\n✅ Migration complete.");
  } catch (err) {
    console.error("Migration failed:", err);
  }
}

runAll();
