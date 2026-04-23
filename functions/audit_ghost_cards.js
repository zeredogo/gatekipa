const admin = require('firebase-admin');
const path = require('path');

// Service account lives in functions/ alongside this script.
const serviceAccount = require(path.join(__dirname, 'gatekipa.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function auditGhostCards() {
  console.log("🔍 Starting Audit: Searching for Ghost Cards (pending_issuance)...");

  // Query 1: Cards with local_status == 'pending_issuance' OR status == 'pending_issuance'
  const pendingStatusCards = await db.collection("cards")
    .where("status", "==", "pending_issuance")
    .get();
    
  const localPendingStatusCards = await db.collection("cards")
    .where("local_status", "==", "pending_issuance")
    .get();

  // Deduplicate by ID
  const map = new Map();
  pendingStatusCards.docs.forEach(doc => map.set(doc.id, doc));
  localPendingStatusCards.docs.forEach(doc => map.set(doc.id, doc));

  const ghostCards = [];

  for (const [id, doc] of map.entries()) {
    const data = doc.data();
    
    // The definition of a Ghost Card:
    // 1. Stuck in pending_issuance
    // 2. Missing bridgecard_card_id (no real Mastercard provisioned)
    if (!data.bridgecard_card_id) {
        ghostCards.push({
            id: doc.id,
            account_id: data.account_id,
            created_by: data.created_by,
            name: data.name,
            created_at: data.created_at 
                ? new Date(data.created_at).toISOString() 
                : "Unknown"
        });
    }
  }

  console.log("\n========================================================");
  console.log(`⚠️  FOUND ${ghostCards.length} GHOST CARD(S)`);
  console.log("========================================================\n");

  if (ghostCards.length === 0) {
      console.log("✅ Platform is clean. No ghost cards found.");
      return;
  }

  // Print detailed report
  ghostCards.forEach((card, index) => {
      console.log(`[Card ${index + 1}]`);
      console.log(`  Card ID:     ${card.id}`);
      console.log(`  User ID:     ${card.created_by}`);
      console.log(`  Account ID:  ${card.account_id}`);
      console.log(`  Card Name:   ${card.name}`);
      console.log(`  Created At:  ${card.created_at}`);
      console.log("--------------------------------------------------------");
  });

  console.log(`\nNext Steps:`);
  console.log(`  1. Use the User ID list above to lookup their email addresses in the Authentication tab or 'users' collection.`);
  console.log(`  2. Email the affected users and ask them to open the app.`);
  console.log(`  3. Instruct them to go to their Cards list, tap the "Pending" card, and click the new "Complete Activation" button.`);
}

auditGhostCards()
  .then(() => process.exit(0))
  .catch((err) => {
      console.error("❌ Error auditing cards:", err);
      process.exit(1);
  });
