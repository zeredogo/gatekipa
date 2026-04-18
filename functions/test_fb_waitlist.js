const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const serviceAccount = require("./gatekipa.json");

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

async function countWaitlist() {
  try {
    const collections = await db.listCollections();
    console.log("Collections in Firebase:", collections.map(c => c.id).join(", "));

    const snap = await db.collection("waitlist").get();
    console.log("Waitlist total:", snap.docs.length);
  } catch (e) {
    console.error("Error reading waitlist from FB:", e);
  }
}
countWaitlist();
