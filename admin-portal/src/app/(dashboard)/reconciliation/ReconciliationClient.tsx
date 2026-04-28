"use client";

import React, { useState } from "react";
import { Search, RotateCw, CheckCircle, AlertTriangle } from "lucide-react";
import { runReconciliationSweep } from "@/app/actions/adminActions";

export default function ReconciliationClient({ 
  gatekipaLedger, 
  bridgecardEscrow,
  lastSweep 
}: { 
  gatekipaLedger: number, 
  bridgecardEscrow: number,
  lastSweep: string
}) {
  const [isSweeping, setIsSweeping] = useState(false);

  const handleSweep = async () => {
    setIsSweeping(true);
    try {
      const res = await runReconciliationSweep();
      if (res.success) {
        alert(res.message || "Ledger synced");
      } else {
        alert("Failed to run sweep: " + res.error);
      }
    } catch (e: any) {
      alert("Error running sweep");
    } finally {
      setIsSweeping(false);
    }
  };

  const parity = gatekipaLedger === bridgecardEscrow;

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Reconciliation</h1>
          <p className="text-gray-400 mt-1">Audit ledger parity between Gatekipa Firestore and the Bridgecard external API.</p>
          {lastSweep && <p className="text-xs text-emerald-400 mt-2">Last sweep: {new Date(lastSweep).toLocaleString()}</p>}
        </div>
        <div className="flex gap-3">
          <button 
            onClick={handleSweep}
            disabled={isSweeping}
            className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 disabled:opacity-50 text-white px-4 py-2 rounded-xl transition-colors font-medium">
            <RotateCw className={`w-4 h-4 ${isSweeping ? "animate-spin" : ""}`} />
            {isSweeping ? "Sweeping..." : "Run Reconciliation Sweep"}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-emerald-500">
          <h3 className="text-lg font-bold text-white mb-2">Gatekipa Ledger</h3>
          <p className="text-3xl font-bold text-emerald-400">₦{gatekipaLedger.toLocaleString()}</p>
          <p className="text-sm text-gray-400 mt-2">Total user balances mapped internally.</p>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-forest-500">
          <h3 className="text-lg font-bold text-white mb-2">Bridgecard Escrow</h3>
          <p className="text-3xl font-bold text-forest-400">₦{bridgecardEscrow.toLocaleString()}</p>
          <p className="text-sm text-gray-400 mt-2">Actual funds settled with issuing partner.</p>
        </div>
      </div>

      <div className={`glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center border-t-2 ${parity ? "border-emerald-500" : "border-rose-500"}`}>
        <div className={`w-16 h-16 rounded-full flex items-center justify-center mb-4 ${parity ? "bg-emerald-500/10" : "bg-rose-500/10"}`}>
          {parity ? <CheckCircle className="w-8 h-8 text-emerald-400" /> : <AlertTriangle className="w-8 h-8 text-rose-400" />}
        </div>
        <h3 className="text-xl font-bold text-white mb-2">
          {parity ? "Perfect Ledger Parity" : "Ledger Desync Detected"}
        </h3>
        <p className="text-gray-400 max-w-md">
          {parity 
            ? "The internal user wallets and the external Bridgecard issuing wallets are perfectly synced. There are zero mismatched records." 
            : "There is a mismatch between Gatekipa local ledger and external settlement balances. Please run a manual audit."}
        </p>
      </div>
    </div>
  );
}
