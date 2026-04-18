const { initializeApp, cert } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const serviceAccount = require("./gatekipa.json");

initializeApp({
  credential: cert(serviceAccount),
  databaseURL: "https://gatekipa-c4c60-default-rtdb.firebaseio.com"
});

const db = getDatabase();

async function countWaitlist() {
  try {
    const dbRef = db.ref("/");
    dbRef.once("value", (snapshot) => {
      const data = snapshot.val();
      if (!data) {
        console.log("No data in root");
        process.exit(0);
      }
      Object.keys(data).forEach(key => {
        if (key.toLowerCase().includes("wait") || key.toLowerCase().includes("user")) {
           const count = Object.keys(data[key]).length;
           console.log(`Found ${key} count:`, count);
        }
      });
      console.log("Root keys:", Object.keys(data));
      process.exit(0);
    });
  } catch(e) {
    console.error(e);
  }
}
countWaitlist();
