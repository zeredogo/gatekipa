"use client";

import React, { useState } from "react";
import { RotateCw, CheckCircle, AlertTriangle, Clock } from "lucide-react";
import { runReconciliationSweep } from "@/app/actions/adminActions";
import { useRouter } from "next/navigation";

interface SweepLog {
  id: string;
  timestamp: string;
  gatekipa_ledger: number;
  bridgecard_escrow: number;
  difference: number;
  status: string;
}

export default function ReconciliationClient({ 
  gatekipaLedger, 
  sudoEscrow,
  lastSweep,
  sweepsHistory = []
}: { 
  gatekipaLedger: number; 
  sudoEscrow: number;
  lastSweep: string;
  sweepsHistory: SweepLog[];
}) {
  const router = useRouter();
  const [isSweeping, setIsSweeping] = useState(false);

  const handleSweep = async () => {
    setIsSweeping(true);
    try {
      const res = await runReconciliationSweep();
      if (res.success) {
        alert(res.message || "Ledger synced");
        router.refresh();
      } else {
        alert("Failed to run sweep: " + res.error);
      }
    } catch {
      alert("Error running sweep");
    } finally {
      setIsSweeping(false);
    }
  };

  const parity = gatekipaLedger === sudoEscrow;

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Reconciliation Center</h1>
          <p className="text-gray-400 mt-1">Audit ledger parity between Gatekipa internal user wallets and Sudo Africa issuing accounts.</p>
          {lastSweep && (
            <p className="text-xs text-emerald-400 mt-2 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" />
              Last audit sweep executed: {new Date(lastSweep).toLocaleString()}
            </p>
          )}
        </div>
        <div className="flex gap-3">
          <button 
            onClick={handleSweep}
            disabled={isSweeping}
            className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 disabled:opacity-50 text-white px-5 py-3 rounded-xl transition-colors font-bold text-sm shadow-lg shadow-forest-950/20">
            <RotateCw className={`w-4 h-4 ${isSweeping ? "animate-spin" : ""}`} />
            {isSweeping ? "Auditing Balances..." : "Run Reconciliation Sweep"}
          </button>
        </div>
      </div>

      {/* Ledger Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-emerald-500">
          <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-2">Gatekipa Wallets Ledger</h3>
          <p className="text-3xl font-bold text-emerald-400">₦{gatekipaLedger.toLocaleString()}</p>
          <p className="text-xs text-gray-400 mt-2">Sum of all users active cash balances calculated inside Gatekipa.</p>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-violet-500">
          <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-2">Sudo Africa Issuing Balance</h3>
          <p className="text-3xl font-bold text-violet-400">₦{sudoEscrow.toLocaleString()}</p>
          <p className="text-xs text-gray-400 mt-2">Actual company settlement pool available in our Sudo integration wallet.</p>
        </div>
      </div>

      {/* Status Alert Banner */}
      <div className={`glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center border-t-2 ${parity ? "border-emerald-500" : "border-rose-500"}`}>
        <div className={`w-16 h-16 rounded-full flex items-center justify-center mb-4 ${parity ? "bg-emerald-500/10" : "bg-rose-500/10"}`}>
          {parity ? <CheckCircle className="w-8 h-8 text-emerald-400" /> : <AlertTriangle className="w-8 h-8 text-rose-400" />}
        </div>
        <h3 className="text-xl font-bold text-white mb-2">
          {parity ? "Perfect Ledger Parity" : "Ledger Desync Detected"}
        </h3>
        <p className="text-gray-400 max-w-md text-sm leading-relaxed">
          {parity 
            ? "The internal user wallets and the external Sudo Africa issuing account are perfectly synced. There are zero mismatched records." 
            : `Desync detected: there is a discrepancy of ₦${Math.abs(gatekipaLedger - sudoEscrow).toLocaleString()} between Gatekipa internal wallets and Sudo Africa escrow. Please audit transaction flow.`}
        </p>
      </div>

      {/* Sweeps Audit History */}
      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-5 border-b border-white/5 bg-white/2 flex items-center gap-2">
          <Clock className="w-4 h-4 text-gray-400" />
          <h2 className="text-sm font-semibold text-white">Ledger Audit History Trail</h2>
          <span className="ml-auto text-xs text-gray-500">Latest 20 audit sweeps</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Timestamp</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Gatekipa Balances</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Sudo Escrow Balance</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Difference</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider text-right">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {sweepsHistory.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-8 text-center text-gray-500 text-sm">
                    No historical reconciliation logs found. Run a sweep above to generate the first audit record.
                  </td>
                </tr>
              ) : sweepsHistory.map(sweep => {
                const isParity = sweep.status === "PARITY";
                return (
                  <tr key={sweep.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4 text-sm text-white">
                      {new Date(sweep.timestamp).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" })}
                    </td>
                    <td className="p-4 text-sm text-gray-300 font-medium">₦{sweep.gatekipa_ledger.toLocaleString()}</td>
                    <td className="p-4 text-sm text-gray-300 font-medium">₦{sweep.bridgecard_escrow.toLocaleString()}</td>
                    <td className={`p-4 text-sm font-bold ${sweep.difference === 0 ? "text-gray-400" : "text-rose-400"}`}>
                      {sweep.difference > 0 ? "+" : ""}{sweep.difference.toLocaleString()}
                    </td>
                    <td className="p-4 text-right">
                      <span className={`px-2.5 py-1 rounded-full text-xs font-bold border ${
                        isParity ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/20" : "bg-rose-500/10 text-rose-400 border-rose-500/20"
                      }`}>
                        {sweep.status}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
