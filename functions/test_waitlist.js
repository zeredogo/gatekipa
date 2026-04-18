const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
initializeApp();
const db = getFirestore();
async function countWaitlist() {
  try {
    const collections = await db.listCollections();
    const collNames = collections.map(c => c.id);
    console.log("Collections:", collNames.join(", "));
    if (collNames.includes("waitlist")) {
      const snap = await db.collection("waitlist").get();
      console.log("waitlist count:", snap.docs.length);
    }
  } catch (e) {
    console.error(e);
  }
}
countWaitlist();
