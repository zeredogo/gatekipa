const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require(path.join(__dirname, 'gatekipa.json'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function run() {
  const txs = await db.collection("transactions")
     .where("type", "==", "card_creation")
     .get();
     
  console.log("Recent Card Creation Transactions:");
  for (const doc of txs.docs) {
      const data = doc.data();
      console.log(`[${doc.id}] User: ${data.user_id}, Status: ${data.status}, Date: ${data.created_at}`);
      const cards = await db.collection("cards").where("created_by", "==", data.user_id).get();
      if (cards.empty) {
          console.log(`  --> User HAS NO CARD in db! Let's check pending...`);
      } else {
          cards.forEach(c => console.log(`  --> Found Card: ${c.id}, status: ${c.data().status}`));
      }
  }
}
run().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
