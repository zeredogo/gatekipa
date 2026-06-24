const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  const email = 'plan_tester@gatekipa.app';
  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(user.uid, {
      emailVerified: true
    });
    console.log('Email verified successfully!');
    process.exit(0);
  } catch (error) {
    console.error('Error verifying email:', error);
    process.exit(1);
  }
}
run();
