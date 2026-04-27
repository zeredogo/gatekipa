const admin = require("firebase-admin");
admin.initializeApp({ projectId: "gatekipa" }); // replace if needed, or use default if emulator
const db = admin.firestore();

async function run() {
  const queueSnap = await db.collection("card_provisioning_queue").orderBy("created_at", "desc").limit(5).get();
  console.log("Recent card_provisioning_queue:");
  queueSnap.forEach(d => console.log(d.id, d.data()));

  const cardsSnap = await db.collection("cards").orderBy("created_at", "desc").limit(5).get();
  console.log("\nRecent cards:");
  cardsSnap.forEach(d => console.log(d.id, d.data()));
  
  // also get the users to see balance
  if (!queueSnap.empty) {
    const uid = queueSnap.docs[0].data().uid;
    const userDoc = await db.collection("users").doc(uid).get();
    console.log("\nUser doc for", uid, ":", userDoc.data());
    const walletDoc = await db.collection("users").doc(uid).collection("wallet").doc("balance").get();
    console.log("\nWallet doc for", uid, ":", walletDoc.data());
  }
}
run().catch(console.error);
