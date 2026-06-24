import { db } from "@/lib/firebaseAdmin";
import ReconciliationClient from "./ReconciliationClient";

export const dynamic = "force-dynamic";

export default async function ReconciliationPage() {
  const statsSnap = await db.doc("system_stats/reconciliation").get();
  
  const gatekipaLedger = statsSnap.data()?.gatekipa_ledger || 0;
  const sudoEscrow = statsSnap.data()?.bridgecard_escrow || 0; // Firestore key retained for backward compat
  const lastSweep = statsSnap.data()?.last_sweep || "";

  return (
    <ReconciliationClient 
      gatekipaLedger={gatekipaLedger}
      sudoEscrow={sudoEscrow}
      lastSweep={lastSweep}
    />
  );
}
