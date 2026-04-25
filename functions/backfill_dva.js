const axios = require('axios');
const admin = require('firebase-admin');
const serviceAccount = require('./gatekipa.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const secretKey = 'sk_live_8e4a2bb7dcf66ec0ab18607f941bf7a9b1f2733e';

async function backfill() {
  console.log("Fetching recent successful Paystack transactions...");
  
  try {
    const res = await axios.get("https://api.paystack.co/transaction?status=success&perPage=100", {
      headers: { Authorization: `Bearer ${secretKey}` }
    });
    
    const transactions = res.data.data;
    console.log(`Found ${transactions.length} successful transactions in this page.`);
    
    let fixedCount = 0;
    for (const tx of transactions) {
      const reference = tx.reference;
      
      const customer = tx.customer;
      if (!customer) continue;
      
      let uid = tx.metadata?.uid || customer.metadata?.uid;
      
      if (!uid && customer.customer_code) {
        const userQuery = await db.collection("users").where("paystack_customer_id", "==", customer.customer_code).limit(1).get();
        if (!userQuery.empty) {
          uid = userQuery.docs[0].id;
        }
      }
      
      if (!uid) {
        console.log(`Could not identify UID for tx ${reference}`);
        continue;
      }
      
      // If the transaction was a plan purchase, the webhook ignored standard funding but processed plan.
      // Let's verify it wasn't a plan purchase.
      if (tx.metadata?.plan && ["free", "activation", "premium", "business"].includes(tx.metadata.plan)) {
        continue;
      }
      
      const idempotencyKey = `${uid}:wallet_funding:${reference}`;
      const snap = await db.collection("idempotency_keys").doc(idempotencyKey).get();
      
      if (snap.exists) {
        continue;
      }
      
      const amountKobo = tx.amount;
      const verifiedAmount = amountKobo / 100;
      
      console.log(`Found missing credit for ${uid}: ${verifiedAmount} NGN (ref: ${reference})`);
      
      await db.runTransaction(async (t) => {
        const walletRef = db.doc(`users/${uid}/wallet/balance`);
        const walletSnap = await t.get(walletRef);
        const currentBalance = (walletSnap.data()?.cached_balance ?? walletSnap.data()?.balance ?? 0);

        const walletLedgerRef = db.collection("wallet_ledger").doc();
        t.set(walletLedgerRef, {
          user_id: uid,
          type: "credit",
          amount: verifiedAmount,
          reference: reference,
          balance_after: currentBalance + verifiedAmount,
          source: "paystack_dva_backfill",
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        t.set(walletRef, {
          cached_balance: admin.firestore.FieldValue.increment(verifiedAmount),
          balance: admin.firestore.FieldValue.increment(verifiedAmount),
        }, { merge: true });
        
        const idempotencyRef = db.collection("idempotency_keys").doc(idempotencyKey);
        const expiresAt = new Date();
        expiresAt.setHours(expiresAt.getHours() + 24);
        
        t.set(idempotencyRef, {
          user_id: uid,
          status: "SUCCESS",
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          expires_at: expiresAt,
          note: "backfilled via script"
        });
      });
      console.log(`Successfully credited ${verifiedAmount} NGN to ${uid}`);
      fixedCount++;
    }
    
    console.log(`Finished processing. Fixed ${fixedCount} missing deposits.`);
    
  } catch (e) {
    console.error(e.response ? e.response.data : e.message);
  }
}

backfill();
