const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
admin.auth().updateUser('UnxIBOSKFqgChOWXsjz2WHTcVV93', { password: '12345Gg!' })
  .then(() => { console.log('Password updated successfully'); process.exit(0); })
  .catch(err => { console.error('Error updating password:', err); process.exit(1); });
