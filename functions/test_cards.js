const admin = require("firebase-admin");
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: "gatekeeper-15331" });
async function run() {
  const db = admin.firestore();
  const snap = await db.collection("cards").orderBy("created_at", "desc").limit(10).get();
  console.log(`Found ${snap.docs.length} cards.`);
  snap.forEach(doc => {
    const data = doc.data();
    console.log(`Card ${doc.id}: account_id='${data.account_id}', name='${data.name}'`);
  });
}
run().catch(console.error);
