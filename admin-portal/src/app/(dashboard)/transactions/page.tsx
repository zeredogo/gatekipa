import { db } from "@/lib/firebaseAdmin";
import TransactionsClient from "./TransactionsClient";

export const dynamic = "force-dynamic";

export default async function TransactionsPage() {
  const allTxSnapshot = await db.collection("transactions").get();
  
  let vaultDeposits = 0;
  let cardFunding = 0;
  let revenueFees = 0;

  allTxSnapshot.forEach(doc => {
    const data = doc.data();
    const amount = data.amount || 0;
    if (data.status !== 'SUCCESS') return;
    if (data.type === "wallet_funding" || data.type === "funding") vaultDeposits += amount;
    if (data.type === "wallet_to_card" || data.type === "card_funding") cardFunding += amount;
    if (data.fee) revenueFees += data.fee;
  });

  // Fetch plan purchases to accurately reflect total platform inflow
  const planPurchasesSnapshot = await db.collectionGroup("plan_purchases").get();
  planPurchasesSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.status === "success" && data.amountKobo) {
      vaultDeposits += (data.amountKobo / 100);
      revenueFees += (data.amountKobo / 100); // Plan purchases are direct revenue
    }
  });

  const transactionsSnapshot = await db.collection("transactions").orderBy("created_at", "desc").limit(25).get();

  const transactions = transactionsSnapshot.docs.map(doc => {
    const data = doc.data();
    const amount = data.amount || 0;

    return {
      id: doc.id,
      type: data.type || "unknown",
      reference: data.reference || data.idempotency_key || doc.id.substring(0, 8),
      userId: data.user_id || data.userId || "Unknown",
      amount: amount,
      status: data.status || "pending",
      createdAt: data.created_at ? new Date(data.created_at.toDate ? data.created_at.toDate() : data.created_at).toLocaleString() : "Unknown",
      isDebit: data.type === "wallet_to_card" || data.type === "card_funding" || data.type === "withdrawal"
    };
  });

  // Fetch some aggregate stats or use the locally aggregated sample for now
  // Real implementation would use an aggregation query if Firestore supports it or a separate stats document.
  
  return (
    <TransactionsClient 
      initialTransactions={transactions} 
      stats={{ vaultDeposits, cardFunding, revenueFees }} 
    />
  );
}
