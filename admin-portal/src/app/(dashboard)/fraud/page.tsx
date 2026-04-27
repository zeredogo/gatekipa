"use client";

import React from "react";
import { AlertTriangle, Activity } from "lucide-react";

export default function FraudPage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Fraud Detection</h1>
          <p className="text-gray-400 mt-1">Algorithmic risk flagging, anomalous velocity alerts, and compromised BIN tracking.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-rose-500">
          <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">Blocked BINs</h3>
          <p className="text-3xl font-bold text-rose-400">124</p>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-amber-500">
          <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">High-Risk Users</h3>
          <p className="text-3xl font-bold text-amber-400">3</p>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-emerald-500">
          <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">Velocity Blocks</h3>
          <p className="text-3xl font-bold text-emerald-400">42</p>
        </div>
      </div>

      <div className="glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center">
        <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mb-4">
          <Activity className="w-8 h-8 text-emerald-400" />
        </div>
        <h3 className="text-xl font-bold text-white mb-2">No Active Threats</h3>
        <p className="text-gray-400 max-w-md">The fraud detection algorithm is actively monitoring transactions. No high-severity threats currently detected.</p>
      </div>
    </div>
  );
}
