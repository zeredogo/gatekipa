"use client";

import { Activity, ShieldAlert, Wallet, CreditCard, Lock, Unlock, Loader2 } from "lucide-react";
import { useState } from "react";
import { toggleLockdown } from "./actions";

interface DashboardProps {
  initialIsLockdown: boolean;
  stats: {
    totalBalance: number;
    activeCards: number;
    webhookEvents: number;
  };
  transactions: any[];
}

export default function DashboardClient({ initialIsLockdown, stats, transactions }: DashboardProps) {
  const [isLockdown, setIsLockdown] = useState(initialIsLockdown);
  const [loading, setLoading] = useState(false);

  const handleToggle = async () => {
    setLoading(true);
    try {
      const newState = await toggleLockdown(isLockdown);
      setIsLockdown(newState);
    } catch (e) {
      console.error(e);
      alert("Failed to toggle lockdown state");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen p-8 md:p-16 flex flex-col items-center">
      <div className="w-full max-w-6xl space-y-8">
        
        <header className="flex justify-between items-center glass-panel p-6">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Gatekeepeer <span className="text-accent">Admin</span></h1>
            <p className="text-gray-400 mt-1">Platform Control & Oversight</p>
          </div>
          <div className="flex items-center gap-4">
            <span className="relative flex h-3 w-3">
              <span className={`animate-ping absolute inline-flex h-full w-full rounded-full opacity-75 ${isLockdown ? 'bg-danger' : 'bg-success'}`}></span>
              <span className={`relative inline-flex rounded-full h-3 w-3 ${isLockdown ? 'bg-danger' : 'bg-success'}`}></span>
            </span>
            <span className="text-sm font-medium tracking-wide text-gray-300">
              {isLockdown ? 'SYSTEM LOCKDOWN' : 'SYSTEM HEALTHY'}
            </span>
          </div>
        </header>

        <section className={`glass-panel p-8 relative overflow-hidden border ${isLockdown ? 'border-danger/60 bg-danger/5' : 'border-danger/30'}`}>
          <div className="absolute top-0 right-0 -mr-16 -mt-16 w-64 h-64 bg-danger/10 rounded-full blur-3xl pointer-events-none"></div>
          
          <div className="flex items-start justify-between relative z-10">
            <div>
              <h2 className="text-xl font-semibold flex items-center gap-2">
                <ShieldAlert className="text-danger w-6 h-6" />
                Global Lockdown Guard
              </h2>
              <p className="text-gray-400 mt-2 max-w-xl">
                Engaging lockdown will immediately reject all Paystack and Bridgecard webhook events, freezing all platform transactions and virtual card authorizations.
              </p>
            </div>
            
            <button
              onClick={handleToggle}
              disabled={loading}
              className={`px-8 py-4 rounded-xl font-bold text-white transition-all duration-300 flex items-center gap-3 ${
                isLockdown 
                ? "bg-gradient-to-r from-success to-emerald-500 shadow-[0_0_20px_rgba(16,185,129,0.4)]" 
                : "bg-gradient-to-r from-danger to-red-600 shadow-[0_0_20px_rgba(239,68,68,0.4)] hover:scale-105"
              } ${loading ? "opacity-75 cursor-not-allowed" : ""}`}
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : (isLockdown ? <Unlock className="w-5 h-5" /> : <Lock className="w-5 h-5" />)}
              {isLockdown ? "DISENGAGE LOCKDOWN" : "ENGAGE LOCKDOWN"}
            </button>
          </div>
        </section>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="glass-card p-6 flex flex-col gap-4">
            <div className="flex items-center gap-3 text-accent">
              <Wallet className="w-6 h-6" />
              <h3 className="font-semibold">Wallet Ledger</h3>
            </div>
            <div className="text-4xl font-bold tracking-tighter">₦ {(stats.totalBalance / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
            <p className="text-sm text-gray-400">Total circulating balance</p>
          </div>
          
          <div className="glass-card p-6 flex flex-col gap-4">
            <div className="flex items-center gap-3 text-purple-400">
              <CreditCard className="w-6 h-6" />
              <h3 className="font-semibold">Active Cards</h3>
            </div>
            <div className="text-4xl font-bold tracking-tighter">{stats.activeCards}</div>
            <p className="text-sm text-gray-400">Issued via Bridgecard</p>
          </div>

          <div className="glass-card p-6 flex flex-col gap-4">
            <div className="flex items-center gap-3 text-orange-400">
              <Activity className="w-6 h-6" />
              <h3 className="font-semibold">Webhook Events</h3>
            </div>
            <div className="text-4xl font-bold tracking-tighter">{stats.webhookEvents}</div>
            <p className="text-sm text-gray-400">Processed successfully</p>
          </div>
        </div>

        <section className="glass-panel p-6">
          <h2 className="text-xl font-semibold mb-6 flex items-center gap-2">
            <Activity className="text-gray-400 w-5 h-5" />
            Recent Webhooks
          </h2>
          
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="border-b border-white/10 text-gray-400 text-sm">
                  <th className="pb-3 px-4 font-medium">Event ID</th>
                  <th className="pb-3 px-4 font-medium">Type</th>
                  <th className="pb-3 px-4 font-medium">Status</th>
                  <th className="pb-3 px-4 font-medium">Time</th>
                </tr>
              </thead>
              <tbody className="text-sm">
                {transactions.length === 0 ? (
                  <tr><td colSpan={4} className="py-4 text-center text-gray-500">No recent events.</td></tr>
                ) : transactions.map((row, i) => (
                  <tr key={i} className="border-b border-white/5 hover:bg-white/5 transition-colors">
                    <td className="py-4 px-4 font-mono text-gray-400">{row.id}</td>
                    <td className="py-4 px-4">{row.type}</td>
                    <td className="py-4 px-4">
                      <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                        row.status === "failed" || row.status === "declined" ? "bg-danger/20 text-danger" : 
                        row.status === "completed" ? "bg-success/20 text-success" : "bg-gray-500/20 text-gray-400"
                      }`}>
                        {row.status}
                      </span>
                    </td>
                    <td className="py-4 px-4 text-gray-500">{row.time}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

      </div>
    </main>
  );
}
