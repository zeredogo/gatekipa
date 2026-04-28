const admin = require('firebase-admin');
const path = require('path');

const localKeyPath = path.join('/Users/mac/Gatekipa/admin-portal', 'gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(localKeyPath),
});

const db = admin.firestore();

async function checkCards() {
  const cardsRef = db.collection('cards');
  const snapshot = await cardsRef.get();
  console.log('Total cards:', snapshot.size);
  let withoutCreatedAt = 0;
  snapshot.forEach(doc => {
    if (!doc.data().created_at) {
      withoutCreatedAt++;
      console.log('Card without created_at:', doc.id, doc.data());
    }
  });
  console.log('Cards without created_at:', withoutCreatedAt);
}

async function run() {
    await checkCards();
    process.exit(0);
}

run().catch(console.error);
