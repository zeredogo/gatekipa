const admin = require("firebase-admin");
try { admin.initializeApp(); } catch(e) {}
const db = admin.firestore();

async function check() {
  const users = await db.collection("users").where("email", "in", ["steviekusu@gmail.com"]).get();
  for (const doc of users.docs) {
    const wDoc = await db.collection("users").doc(doc.id).collection("wallet").doc("balance").get();
    console.log(`User: ${doc.data().email} (UID: ${doc.id}) | Wallet Balance: ${wDoc.exists ? wDoc.data().balance : 0}`);
  }
}
check().catch(console.error);
