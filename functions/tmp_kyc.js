const admin = require("firebase-admin");
process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
admin.initializeApp({ projectId: "gatekipa-bbd1c" });

async function run() {
  await admin.firestore().collection("users").doc("J2GEJFLNbYa5bOCtgkRUbjF0sV83").set({
    kycStatus: "verified"
  }, { merge: true });
  console.log("Updated user KYC status!");
}
run();
