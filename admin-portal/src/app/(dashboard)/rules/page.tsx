"use client";

import React from "react";
import { Cpu, Plus } from "lucide-react";

export default function RulesPage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Global Rules</h1>
          <p className="text-gray-400 mt-1">Adjust platform-wide spending caps and security rules.</p>
        </div>
        <button className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white px-4 py-2 rounded-xl transition-colors font-medium">
          <Plus className="w-4 h-4" />
          Add Global Rule
        </button>
      </div>

      <div className="glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center min-h-[300px]">
        <div className="w-16 h-16 rounded-full bg-forest-500/10 flex items-center justify-center mb-4">
          <Cpu className="w-8 h-8 text-forest-400" />
        </div>
        <h3 className="text-xl font-bold text-white mb-2">No Active Overrides</h3>
        <p className="text-gray-400 max-w-md">The system is operating on default configuration. Create a global rule to temporarily lower limits or block specific merchant categories across all users.</p>
      </div>
    </div>
  );
}
