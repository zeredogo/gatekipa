const admin = require('firebase-admin');
const path = require('path');

const localKeyPath = path.join('/Users/mac/Gatekipa/admin-portal', 'gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(localKeyPath),
});

const db = admin.firestore();

async function checkTx() {
  const transactionsSnapshot = await db.collection("transactions").get();
  
  let vaultDeposits = 0;
  let cardFunding = 0;

  transactionsSnapshot.forEach(doc => {
    const data = doc.data();
    const amount = data.amount || 0;
    if (data.type === "wallet_funding" || data.type === "funding") vaultDeposits += amount;
    if (data.type === "wallet_to_card" || data.type === "card_funding") cardFunding += amount;
  });
  
  console.log('Vault Deposits:', vaultDeposits);
  console.log('Card Funding:', cardFunding);
}

checkTx().then(() => process.exit(0)).catch(console.error);
