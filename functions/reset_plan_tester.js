const admin = require('firebase-admin');
const serviceAccount = require('../functions/gatekipa.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function resetPlanTester() {
  const usersRef = db.collection('users');
  const snapshot = await usersRef.where('email', '==', 'plan_tester@gatekipa.app').get();
  
  if (snapshot.empty) {
    console.log('User not found.');
    process.exit(0);
  }

  const doc = snapshot.docs[0];
  await doc.ref.update({
    planTier: 'none'
  });
  
  console.log('Successfully reset planTier to "none".');
  process.exit(0);
}

resetPlanTester().catch(console.error);
