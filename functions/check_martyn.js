const { db } = require("./utils/firebase");

async function check() {
  const usersRef = db.collection("users");
  const query = await usersRef.where("email", "==", "martynseric@gmail.com").get(); // guessing email or just martynseric
  // let's just fetch all users and look for "martynseric"
  
  const allUsers = await usersRef.get();
  let targetUser = null;
  allUsers.forEach(doc => {
    const data = doc.data();
    if (data.email && data.email.includes("martynseric")) {
      targetUser = { id: doc.id, ...data };
    }
  });

  if (!targetUser) {
    console.log("User not found!");
    return;
  }
  
  console.log("User found:", targetUser.id, targetUser.email);
  
  // Wallet
  const walletDoc = await db.collection("users").doc(targetUser.id).collection("wallet").doc("balance").get();
  console.log("Wallet Balance:", walletDoc.exists ? walletDoc.data() : "No wallet");

  // Wallet Transactions
  const txs = await db.collection("users").doc(targetUser.id).collection("wallet_transactions").get();
  console.log("Transactions:");
  txs.forEach(t => console.log(t.id, t.data()));

  // Funding History
  const fhs = await db.collection("users").doc(targetUser.id).collection("funding_history").get();
  console.log("Funding History:");
  fhs.forEach(t => console.log(t.id, t.data()));
}

check().catch(console.error);
