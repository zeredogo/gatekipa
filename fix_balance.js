const admin = require('firebase-admin');
const serviceAccount = require('./functions/keys/gatekipa-bbd1c-firebase-adminsdk-r8mta-a9242d55c7.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fix() {
  const users = await db.collection('users').where('username', '==', 'martynseric').get();
  if (users.empty) {
    console.log('User not found');
    process.exit(1);
  }
  const user = users.docs[0];
  console.log('Found user:', user.id, user.data().walletBalance);
  
  await user.ref.update({
    walletBalance: admin.firestore.FieldValue.increment(-700)
  });
  console.log('Decremented wallet balance by 700. New balance:', (await user.ref.get()).data().walletBalance);
  process.exit(0);
}

fix().catch(console.error);
