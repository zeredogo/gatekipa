import { db } from "@/lib/firebaseAdmin";
import ReconciliationClient from "./ReconciliationClient";

export const dynamic = "force-dynamic";

export default async function ReconciliationPage() {
  const statsSnap = await db.doc("system_stats/reconciliation").get();
  
  const gatekipaLedger = statsSnap.data()?.gatekipa_ledger || 0;
  const sudoEscrow = statsSnap.data()?.bridgecard_escrow || 0; 
  const lastSweep = statsSnap.data()?.last_sweep || "";

  // Fetch reconciliation audit sweeps history
  const sweepsSnap = await db.collection("reconciliation_sweeps")
    .orderBy("timestamp", "desc")
    .limit(20)
    .get();

  const sweeps = sweepsSnap.docs.map(doc => {
    const d = doc.data();
    return {
      id: doc.id,
      timestamp: d.timestamp || "",
      gatekipa_ledger: d.gatekipa_ledger || 0,
      bridgecard_escrow: d.bridgecard_escrow || 0,
      difference: d.difference || 0,
      status: d.status || "PARITY"
    };
  });

  return (
    <ReconciliationClient 
      gatekipaLedger={gatekipaLedger}
      sudoEscrow={sudoEscrow}
      lastSweep={lastSweep}
      sweepsHistory={sweeps}
    />
  );
}
