const admin = require('firebase-admin');

try {
  const serviceAccount = require('/Users/mac/Gatekeeper/functions/gatekipa.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
} catch (e) {
  admin.initializeApp();
}
const db = admin.firestore();

async function cleanMockSubs() {
  const snapshot = await db.collectionGroup('detected_subscriptions').get();
  console.log(`Found ${snapshot.size} detected_subscriptions documents.`);
  
  const batch = db.batch();
  let count = 0;
  snapshot.forEach(doc => {
      console.log(`- ID: ${doc.id}, Parent (User ID): ${doc.ref.parent.parent.id}, Data amount: ${doc.data().amount}`);
      batch.delete(doc.ref);
      count++;
  });
  
  if (count > 0) {
    await batch.commit();
    console.log(`Deleted ${count} mock documents successfully.`);
  } else {
    console.log("No mock documents found.");
  }
}
cleanMockSubs().catch(console.error);
