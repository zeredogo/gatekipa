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
  snapshot.forEach(doc => {
    console.log(doc.id, doc.data().name, "accountId:", doc.data().account_id, "userId:", doc.data().user_id, "created_by:", doc.data().created_by);
  });
}

checkCards().then(() => process.exit(0)).catch(console.error);
