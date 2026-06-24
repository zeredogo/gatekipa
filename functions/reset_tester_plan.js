const admin = require("firebase-admin");
const serviceAccount = require("./gatekipa.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  try {
    const email = "plan_tester@gatekipa.app";
    const password = "Password123!";
    let user;
    
    try {
      user = await admin.auth().getUserByEmail(email);
      console.log("User already exists, updating...");
      await admin.auth().updateUser(user.uid, { password });
    } catch(e) {
      if (e.code === 'auth/user-not-found') {
        user = await admin.auth().createUser({
          email,
          password,
          displayName: "Plan Tester"
        });
        console.log("User created.");
      } else throw e;
    }

    await admin.firestore().collection("users").doc(user.uid).set({
      email,
      firstName: "Plan",
      lastName: "Tester",
      planTier: "none",
      cardsIncluded: 0,
      isPremium: false,
      kycStatus: "approved",
      uid: user.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    
    await admin.firestore().doc(`users/${user.uid}/wallet/balance`).set({
      balance: 10000,
      balance_kobo: 1000000,
      currency: "NGN"
    }, { merge: true });

    console.log("✅ Successfully created/reset plan_tester@gatekipa.app with 'none' planTier.");
  } catch(e) {
    console.error("Failed:", e.message);
  } finally {
    process.exit(0);
  }
}
run();
