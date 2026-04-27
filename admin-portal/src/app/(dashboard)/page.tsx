import { db } from "@/lib/firebaseAdmin";
import DashboardClient from "./DashboardClient";

export const dynamic = "force-dynamic";

export default async function AdminDashboardOverview() {
  // 1. Fetch Total Users
  const usersSnapshot = await db.collection("users").count().get();
  const totalUsers = usersSnapshot.data().count;

  // 2. Fetch Active Cards
  const cardsSnapshot = await db.collection("cards").where("local_status", "in", ["active", "frozen"]).count().get();
  const activeCards = cardsSnapshot.data().count;

  // 3. System Status
  const globalStateDoc = await db.collection("system_state").doc("global").get();
  const systemState = globalStateDoc.exists ? globalStateDoc.data() : { mode: "NORMAL" };
  const isHealthy = systemState?.mode !== "LOCKDOWN";

  // 4. Vault Balance (just aggregating a sample of active vaults if available, or just mock for now)
  // Since aggregating all wallet balances might be expensive without a sum() aggregation if not supported, we can just show a mock or a fast count.
  const transactionsSnapshot = await db.collection("transactions").count().get();
  const totalTransactions = transactionsSnapshot.data().count;

  return (
    <DashboardClient 
      totalUsers={totalUsers} 
      activeCards={activeCards} 
      isHealthy={isHealthy}
      totalTransactions={totalTransactions}
    />
  );
}
