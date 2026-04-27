const admin = require("firebase-admin");
const axios = require("axios");
admin.initializeApp();
const db = admin.firestore();

async function run() {
  const usersRef = db.collection("users");
  const snapshot = await usersRef.where("firstName", "==", "Sunday Stephen").get();
  if (snapshot.empty) {
    console.log("No user found with firstName 'Sunday Stephen'");
    return;
  }
  snapshot.forEach(doc => {
    console.log("Found user:", doc.id, doc.data());
  });
}
run().catch(console.error);
