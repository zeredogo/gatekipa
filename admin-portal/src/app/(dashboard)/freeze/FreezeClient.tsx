"use client";

import React, { useState, useTransition } from "react";
import { ShieldAlert, AlertTriangle, Lock, Unlock, Server, Loader2 } from "lucide-react";
import { toggleGlobalFreeze } from "@/app/actions/adminActions";

export default function FreezeClient({ initialIsFrozen }: { initialIsFrozen: boolean }) {
  const [isFrozen, setIsFrozen] = useState(initialIsFrozen);
  const [isPending, startTransition] = useTransition();

  const handleToggleFreeze = () => {
    startTransition(async () => {
      const result = await toggleGlobalFreeze(isFrozen);
      if (result.success) {
        setIsFrozen(result.mode === "LOCKDOWN");
      } else {
        alert("Failed to toggle freeze state.");
      }
    });
  };

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-3xl font-bold text-white tracking-tight">Global Freeze</h1>
        <p className="text-gray-400 mt-1">Manage global platform security states and emergency protocols.</p>
      </div>

      {/* System Status Banner */}
      <div className={`p-6 rounded-2xl border transition-colors ${isFrozen ? 'bg-rose-500/10 border-rose-500/30' : 'bg-emerald-500/10 border-emerald-500/30'}`}>
        <div className="flex items-start gap-4">
          <div className={`p-3 rounded-full ${isFrozen ? 'bg-rose-500/20' : 'bg-emerald-500/20'}`}>
            <Server className={`w-6 h-6 ${isFrozen ? 'text-rose-400' : 'text-emerald-400'}`} />
          </div>
          <div>
            <h2 className={`text-lg font-bold ${isFrozen ? 'text-rose-400' : 'text-emerald-400'}`}>
              System Status: {isFrozen ? 'FROZEN (SYSTEM-WIDE)' : 'OPERATIONAL'}
            </h2>
            <p className="text-gray-300 mt-1">
              {isFrozen 
                ? 'The platform is currently frozen. All new virtual cards are blocked, existing cards are frozen, and wallet transactions are suspended.'
                : 'All platform services are running normally. Virtual card issuance and wallet funding are active.'}
            </p>
          </div>
        </div>
      </div>

      <div className="grid gap-6">
        {/* Global Freeze Protocol */}
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-rose-500">
          <div className="flex items-start justify-between">
            <div className="flex gap-4">
              <div className="mt-1 p-2 rounded-xl bg-rose-500/10">
                <ShieldAlert className="w-6 h-6 text-rose-500" />
              </div>
              <div>
                <h3 className="text-xl font-bold text-white">Global Platform Freeze</h3>
                <p className="text-gray-400 mt-2 max-w-xl text-sm leading-relaxed">
                  Activating the Global Freeze will instantaneously write to the <code className="text-rose-300 bg-rose-900/30 px-1 py-0.5 rounded">system_state/global</code> document, 
                  forcing all client applications into degraded mode. It will also queue a background job to freeze every single active virtual card across the entire user base.
                </p>
                <div className="mt-4 flex items-center gap-2 text-rose-400 text-sm font-medium">
                  <AlertTriangle className="w-4 h-4" />
                  Warning: This action disrupts all users globally and should only be used in severe security incidents.
                </div>
              </div>
            </div>
          </div>
          <div className="mt-8 pt-6 border-t border-white/5 flex justify-end">
            <button 
              onClick={handleToggleFreeze}
              disabled={isPending}
              className={`flex items-center gap-2 px-6 py-3 rounded-xl font-bold transition-all shadow-lg disabled:opacity-50
                ${isFrozen 
                  ? 'bg-emerald-500 hover:bg-emerald-600 text-white shadow-emerald-500/20' 
                  : 'bg-rose-500 hover:bg-rose-600 text-white shadow-rose-500/20'
                }`}
            >
              {isPending ? <Loader2 className="w-5 h-5 animate-spin" /> : (isFrozen ? <Unlock className="w-5 h-5" /> : <Lock className="w-5 h-5" />)}
              {isFrozen ? 'UNFREEZE SYSTEM' : 'ACTIVATE GLOBAL FREEZE'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
