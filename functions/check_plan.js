const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function checkPlan() {
  const usersRef = db.collection('users');
  const snapshot = await usersRef.where('email', '==', 'plan_tester@gatekipa.app').get();
  
  if (snapshot.empty) {
    console.log('User not found.');
  } else {
    const doc = snapshot.docs[0];
    console.log(`Email: ${doc.data().email}, PlanTier: ${doc.data().planTier}`);
  }
  process.exit(0);
}

checkPlan().catch(console.error);
