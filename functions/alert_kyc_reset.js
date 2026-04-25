const admin = require("firebase-admin");

// Initialize Firebase Admin (assuming default credentials work locally if GOOGLE_APPLICATION_CREDENTIALS is set, 
// or if run inside an environment with Firebase configured).
// If not already initialized:
if (!admin.apps.length) {
  const serviceAccount = require("./gatekipa.json"); // Using the correct service account key
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();
const messaging = admin.messaging();

async function alertAndResetDummyKyc() {
  console.log("Starting KYC Deadlock Remediation Script...");
  
  try {
    // Find all users who passed the local dummy lock but never successfully registered with Bridgecard
    const snapshot = await db.collection("users")
      .where("kycStatus", "==", "verified")
      .get();
      
    if (snapshot.empty) {
      console.log("No users found with kycStatus == 'verified'.");
      return;
    }

    let resetCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const uid = doc.id;
      
      // If they don't have a bridgecard cardholder ID, their KYC is essentially a local "dummy" lock
      if (!data.bridgecard_cardholder_id) {
        console.log(`Processing UID: ${uid}...`);
        
        // 1. Reset local KYC status so the UI unlocks the KYC capture flow
        await doc.ref.update({
          kycStatus: "unverified",
          kycMeta: admin.firestore.FieldValue.delete()
        });
        
        console.log(`  - Reset kycStatus to 'unverified' for ${uid}`);
        resetCount++;

        // 2. Add an in-app notification
        await db.collection("users").doc(uid).collection("notifications").add({
          user_id: uid,
          type: "system",
          title: "Action Required: Identity Update",
          body: "We have updated our verification system. Please re-submit your identity document to continue using Gatekipa.",
          isRead: false,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`  - Created in-app notification for ${uid}`);

        // 3. Send Push Notification if they have an FCM token
        if (data.fcm_token) {
          try {
            await admin.messaging().send({
              token: data.fcm_token,
              notification: {
                title: "Action Required: Identity Verification",
                body: "We have updated our verification system. Please re-submit your identity document to continue using Gatekipa.",
              },
              data: {
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                route: "/profile/kyc",
              },
            });
            console.log(`  - Sent FCM push notification to ${uid}`);
          } catch (fcmErr) {
            console.warn(`  - Failed to send FCM to ${uid}:`, fcmErr.message);
          }
        }
      }
    }
    
    console.log(`\nRemediation Complete! Successfully reset and alerted ${resetCount} users.`);
    
  } catch (error) {
    console.error("Script failed:", error);
  }
}

alertAndResetDummyKyc();
