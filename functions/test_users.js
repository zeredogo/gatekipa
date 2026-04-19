const admin = require("firebase-admin");
try { admin.initializeApp(); } catch(e) {}
const db = admin.firestore();

async function check() {
  const users = await db.collection("users").where("email", "in", ["martynseric@gmail.com", "steviekusu@gmail.com"]).get();
  users.forEach(doc => {
    const d = doc.data();
    console.log(`User: ${d.email} | Phone: ${d.phoneNumber || d.phone} | First: ${d.firstName || d.first_name} | Last: ${d.lastName || d.last_name}`);
  });
}
check().catch(console.error);
