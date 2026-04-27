const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function resetStuckKyc() {
  console.log("Starting KYC reset for stuck users...");
  let count = 0;
  
  const snapshot = await db.collection("users").get();
  
  for (const doc of snapshot.docs) {
    const data = doc.data();
    
    // Skip if already verified or no kycMeta
    if (!data.kycMeta || data.kycStatus === "verified" || data.bridgecard_cardholder_id) {
        continue;
    }

    // Check if they have a selfie, and either an ID Number (for Nigerians) OR a Photo (Non-Nigerians)
    const hasSelfie = !!data.kycMeta.selfie;
    const hasIdNumber = !!data.kycMeta.idNumber;
    const hasPhoto = !!data.kycMeta.photo;

    if (hasSelfie && (hasIdNumber || hasPhoto)) {
      console.log(`[${doc.id}] Found stuck user (Status: ${data.kycStatus || 'null'}). Resetting to verified...`);
      
      await doc.ref.update({
        kycStatus: "verified",
        "kycMeta.adminRetryTriggeredAt": admin.firestore.FieldValue.serverTimestamp()
      });
      count++;
    }
  }

  console.log(`\n===========================================`);
  console.log(`Successfully reset KYC for ${count} stuck user(s)!`);
  console.log(`===========================================`);
  console.log("These users will now see 'Verification Complete' in their profile.");
  console.log("When they tap 'Create Virtual Card', the backend will automatically");
  console.log("pull their saved photos and submit them to Bridgecard for real verification.");
}

resetStuckKyc().then(() => process.exit(0)).catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
