const admin = require('firebase-admin');
const path = require('path');

const localKeyPath = path.join('/Users/mac/Gatekipa/admin-portal', 'gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(localKeyPath),
});

const db = admin.firestore();

async function checkTx() {
  const transactionsSnapshot = await db.collection("transactions").get();
  
  transactionsSnapshot.forEach(doc => {
    const data = doc.data();
    console.log(doc.id, data.type, data.amount, data.status);
  });
}

checkTx().then(() => process.exit(0)).catch(console.error);
