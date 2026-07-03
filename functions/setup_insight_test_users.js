const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();
const auth = admin.auth();

async function createUser(email, planTier) {
  let uid;
  try {
    const userRecord = await auth.getUserByEmail(email);
    uid = userRecord.uid;
    await auth.updateUser(uid, { password: 'Password123!' });
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const userRecord = await auth.createUser({
        email,
        password: 'Password123!',
        emailVerified: true,
      });
      uid = userRecord.uid;
    } else {
      throw e;
    }
  }

  // Set up Firestore doc
  const pastDate = new Date();
  pastDate.setFullYear(pastDate.getFullYear() - 1);
  
  await db.collection('users').doc(uid).set({
    uid: uid,
    email: email,
    firstName: email.split('_')[1].split('@')[0].toUpperCase(),
    lastName: 'Test',
    planTier: planTier,
    kycStatus: 'verified',
    requiresMigration: false,
    sentinel_trial_expiry_date: pastDate, // expired trial
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });

  console.log(`Configured ${email} with planTier: ${planTier}`);
}

async function setup() {
  await createUser('insight_free@gatekipa.app', 'none');
  await createUser('insight_premium@gatekipa.app', 'premium');
  await createUser('insight_business@gatekipa.app', 'business');
  process.exit(0);
}

setup().catch(console.error);
