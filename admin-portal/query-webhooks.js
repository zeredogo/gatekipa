const admin = require('firebase-admin');
const path = require('path');

const localKeyPath = path.join('/Users/mac/Gatekipa/admin-portal', 'gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(localKeyPath),
});

const db = admin.firestore();

async function checkWebhooks() {
  const ref = db.collection('webhook_events');
  const snapshot = await ref.limit(5).get();
  if (snapshot.empty) {
    console.log('No webhooks found in webhook_events');
  } else {
    snapshot.forEach(doc => {
      console.log('Webhook:', doc.id, doc.data());
    });
  }
}

async function run() {
    await checkWebhooks();
    process.exit(0);
}

run().catch(console.error);
