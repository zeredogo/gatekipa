const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require('./gatekipa.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function makeSuperAdmin() {
  const email = 'kusuconsult@gmail.com';
  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().setCustomUserClaims(user.uid, { super_admin: true, admin: true });
    console.log(`Successfully added super_admin claims to user ${email} (UID: ${user.uid})`);
    
    // Also verify what claims they have now
    const updatedUser = await admin.auth().getUser(user.uid);
    console.log('Current claims:', updatedUser.customClaims);
    process.exit(0);
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      console.error(`User with email ${email} not found. Please create the account in Firebase Auth first.`);
    } else {
      console.error('Error setting custom claims:', error);
    }
    process.exit(1);
  }
}

makeSuperAdmin();
