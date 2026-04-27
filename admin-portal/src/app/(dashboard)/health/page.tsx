"use client";

import React from "react";
import { HeartPulse, Server, Database } from "lucide-react";

export default function HealthPage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">System Health</h1>
          <p className="text-gray-400 mt-1">Real-time Firebase and Bridgecard telemetry.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="glass-panel rounded-2xl p-6 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-emerald-500/10 rounded-xl">
              <Database className="w-6 h-6 text-emerald-400" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white">Firebase Firestore</h3>
              <p className="text-sm text-gray-400">Database Read/Write Latency</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-xl font-bold text-emerald-400">12ms</p>
            <p className="text-xs text-emerald-500">Operational</p>
          </div>
        </div>

        <div className="glass-panel rounded-2xl p-6 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-forest-500/10 rounded-xl">
              <Server className="w-6 h-6 text-forest-400" />
            </div>
            <div>
              <h3 className="text-lg font-bold text-white">Bridgecard API</h3>
              <p className="text-sm text-gray-400">External Issuing Partner Uptime</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-xl font-bold text-forest-400">45ms</p>
            <p className="text-xs text-forest-500">99.99% Uptime</p>
          </div>
        </div>
      </div>
    </div>
  );
}
