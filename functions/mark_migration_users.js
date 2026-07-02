const admin = require('firebase-admin');
const localKeyPath = './gatekipa.json';

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(localKeyPath)
  });
}

const db = admin.firestore();

async function migrate() {
  console.log("=== STARTING MIGRATION MARKING ===");
  const snapshot = await db.collection('users').get();
  console.log(`Found ${snapshot.size} users in Firestore.`);
  
  let markedCount = 0;
  const batch = db.batch();
  
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const email = (data.email || "").toLowerCase().trim();
    
    if (email === 'kusuconsult@gmail.com' || email === 'steviekusu@gmail.com') {
      console.log(`Skipping verified/admin user: ${email} (${doc.id})`);
      continue;
    }
    
    batch.update(doc.ref, { requiresMigration: true });
    markedCount++;
    console.log(`Marking user for migration: ${email || "No Email"} (${doc.id})`);
  }
  
  if (markedCount > 0) {
    await batch.commit();
  }
  
  console.log(`=== MIGRATION MARKING COMPLETE: Marked ${markedCount} users ===`);
}

migrate().then(() => process.exit(0)).catch(console.error);
