"use client";

import React from "react";
import { Search, RotateCw, CheckCircle, AlertTriangle } from "lucide-react";

export default function ReconciliationPage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Reconciliation</h1>
          <p className="text-gray-400 mt-1">Audit ledger parity between Gatekipa Firestore and the Bridgecard external API.</p>
        </div>
        <div className="flex gap-3">
          <button className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
            <RotateCw className="w-4 h-4" />
            Run Reconciliation Sweep
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-emerald-500">
          <h3 className="text-lg font-bold text-white mb-2">Gatekipa Ledger</h3>
          <p className="text-3xl font-bold text-emerald-400">₦24,592,000</p>
          <p className="text-sm text-gray-400 mt-2">Total user balances mapped internally.</p>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-forest-500">
          <h3 className="text-lg font-bold text-white mb-2">Bridgecard Escrow</h3>
          <p className="text-3xl font-bold text-forest-400">₦24,592,000</p>
          <p className="text-sm text-gray-400 mt-2">Actual funds settled with issuing partner.</p>
        </div>
      </div>

      <div className="glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center">
        <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mb-4">
          <CheckCircle className="w-8 h-8 text-emerald-400" />
        </div>
        <h3 className="text-xl font-bold text-white mb-2">Perfect Ledger Parity</h3>
        <p className="text-gray-400 max-w-md">The internal user wallets and the external Bridgecard issuing wallets are perfectly synced. There are zero mismatched records.</p>
      </div>
    </div>
  );
}
