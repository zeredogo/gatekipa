const admin = require("firebase-admin");
const serviceAccount = require("/Users/mac/Gatekipa web/gatekipa/gatekipa.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function check() {
  const snapshot = await db.collection("mail").limit(5).get();
  console.log("Mail collection empty?", snapshot.empty);
  snapshot.forEach(doc => {
    console.log(doc.id, JSON.stringify(doc.data(), null, 2));
  });
}
check().catch(console.error);
