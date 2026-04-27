const admin = require('firebase-admin');
admin.initializeApp({ projectId: "gatekipa-bbd1c" });
const db = admin.firestore();

async function run() {
  const snapshot = await db.collection("users").where("bridgecard_cardholder_id", "!=", null).limit(5).get();
  if (snapshot.empty) {
    console.log("No users found with bridgecard_cardholder_id");
  } else {
    snapshot.forEach(doc => {
      console.log(doc.id, "=>", doc.data().bridgecard_cardholder_id);
    });
  }
}
run();
