const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function run() {
  const snapshot = await db.collection("users").get();
  for (const doc of snapshot.docs) {
    const d = doc.data();
    if (!d.bridgecard_cardholder_id) {
      console.log(`UID: ${doc.id}`);
      console.log(` - kycStatus: ${d.kycStatus}`);
      console.log(` - hasBvn: ${d.hasBvn}`);
      console.log(` - kycMeta: ${JSON.stringify(d.kycMeta)}`);
      console.log(` - bvnMeta: ${JSON.stringify(d.bvnMeta)}`);
      console.log('---');
    }
  }
}
run().then(() => process.exit(0));
