const admin = require('firebase-admin');
const path = require('path');

// Service account lives in functions/ alongside this script.
// Never commit secrets — this file is in .gitignore.
const serviceAccount = require(path.join(__dirname, 'gatekipa.json'));

const DRY_RUN = process.env.DRY_RUN === '1';
if (DRY_RUN) console.log('⚠️  DRY RUN — no writes will be committed.');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function migrate() {
  console.log("Starting ledger backfill migration...");

  // 1. Backfill Wallet Ledger
  const usersSnap = await db.collection("users").get();
  let walletCount = 0;
  for (const userDoc of usersSnap.docs) {
    const balanceDoc = await db.collection("users").doc(userDoc.id).collection("wallet").doc("balance").get();
    if (balanceDoc.exists) {
      const data = balanceDoc.data();
      const bal = data.cached_balance || data.balance || 0;
      if (bal > 0) {
        // Check if migration entry already exists
        const existing = await db.collection("wallet_ledger")
          .where("user_id", "==", userDoc.id)
          .where("source", "==", "migration")
          .get();
        
        if (existing.empty) {
          if (!DRY_RUN) {
            await db.collection("wallet_ledger").add({
              user_id: userDoc.id,
              type: "credit",
              amount: bal,
              reference: "migration_initial_balance_" + Date.now(),
              balance_after: bal,
              source: "migration",
              description: "Initial ledger backfill",
              created_at: admin.firestore.FieldValue.serverTimestamp()
            });
          }
          walletCount++;
          console.log(`Migrated wallet for user ${userDoc.id} (Balance: ${bal})`);
        }
      }
    }
  }

  // 2. Backfill Card Ledger
  const cardsSnap = await db.collection("cards").get();
  let cardCount = 0;
  let cardFundingCount = 0;
  for (const cardDoc of cardsSnap.docs) {
    const data = cardDoc.data();
    const spentAmount = data.spent_amount || 0;
    const chargeCount = data.charge_count || 1;
    const allocatedAmount = data.allocated_amount || data.balance_limit || 0;

    // Funding entry (so that we have a record of where the balance limit came from)
    if (allocatedAmount > 0) {
      const existingFunding = await db.collection("card_ledger")
        .where("card_id", "==", cardDoc.id)
        .where("type", "==", "funding")
        .where("merchant_name", "==", "Historical Funding Migration")
        .get();
        
      if (existingFunding.empty) {
        if (!DRY_RUN) {
          await db.collection("card_ledger").add({
            card_id: cardDoc.id,
            account_id: data.account_id || "",
            type: "funding",
            amount: allocatedAmount,
            merchant_name: "Historical Funding Migration",
            reference: "migration_funding_" + Date.now(),
            created_at: admin.firestore.FieldValue.serverTimestamp()
          });
        }
        cardFundingCount++;
      }
    }

    // Charge entry
    if (spentAmount > 0) {
      const existingCharge = await db.collection("card_ledger")
        .where("card_id", "==", cardDoc.id)
        .where("type", "==", "charge")
        .where("merchant_name", "==", "Historical Spend Migration")
        .get();
        
      if (existingCharge.empty) {
        // Create an entry that aggregates all historical spend
        if (!DRY_RUN) {
          await db.collection("card_ledger").add({
            card_id: cardDoc.id,
            account_id: data.account_id || "",
            type: "charge",
            amount: spentAmount,
            merchant_name: "Historical Spend Migration",
            reference: "migration_spend_" + Date.now(),
            created_at: admin.firestore.FieldValue.serverTimestamp()
          });
        }
        cardCount++;
        console.log(`Migrated card spend for ${cardDoc.id} (Spent: ${spentAmount})`);
      }
    }
  }

  console.log(`Migration complete!`);
  console.log(`- Created ${walletCount} wallet_ledger credits.`);
  console.log(`- Created ${cardFundingCount} card_ledger funding entries.`);
  console.log(`- Created ${cardCount} card_ledger charge entries.`);
}

migrate().then(() => process.exit(0)).catch(console.error);
