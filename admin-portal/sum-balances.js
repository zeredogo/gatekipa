const admin = require('firebase-admin');
const path = require('path');

const localKeyPath = path.join('/Users/mac/Gatekipa/admin-portal', 'gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(localKeyPath),
});

const db = admin.firestore();

async function getBalances() {
  const usersSnap = await db.collection("users").get();
  let totalBalance = 0;
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
    if (walletSnap.exists) {
      const b = walletSnap.data().cached_balance ?? walletSnap.data().balance ?? 0;
      totalBalance += b;
    }
  }
  console.log("Total Gatekipa Balance:", totalBalance);
}

getBalances().then(() => process.exit(0)).catch(console.error);
