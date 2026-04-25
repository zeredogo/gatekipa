const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function fixPremiumUsers() {
  const usersRef = db.collection('users');
  const snapshot = await usersRef.where('isPremium', '==', true).get();
  
  if (snapshot.empty) {
    console.log('No premium users found.');
    return;
  }
  
  let count = 0;
  const batch = db.batch();
  
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.planTier === 'premium' && data.cardsIncluded !== 3) {
      console.log(`Fixing cardsIncluded for user: ${doc.id}`);
      batch.update(doc.ref, { cardsIncluded: 3 });
      count++;
    }
  }
  
  if (count > 0) {
    await batch.commit();
    console.log(`Fixed ${count} premium users.`);
  } else {
    console.log('All premium users already have correct planTier.');
  }
}

fixPremiumUsers().then(() => process.exit(0)).catch(e => {
  console.error(e);
  process.exit(1);
});
