"use client";

import React from "react";
import { 
  ShieldCheck, 
  Users, 
  CreditCard, 
  Activity, 
  TrendingUp,
  ServerCrash
} from "lucide-react";
import { motion } from "framer-motion";

interface DashboardClientProps {
  totalUsers: number;
  activeCards: number;
  isHealthy: boolean;
  totalTransactions: number;
}

export default function DashboardClient({ totalUsers, activeCards, isHealthy, totalTransactions }: DashboardClientProps) {
  const stats = [
    { label: "Total Users", value: totalUsers.toLocaleString(), change: "Live", icon: Users, color: "text-forest-400" },
    { label: "Active/Frozen Cards", value: activeCards.toLocaleString(), change: "Live", icon: CreditCard, color: "text-green-400" },
    { label: "System Status", value: isHealthy ? "Healthy" : "Lockdown", change: isHealthy ? "99.9%" : "Degraded", icon: isHealthy ? Activity : ServerCrash, color: isHealthy ? "text-emerald-400" : "text-rose-400" },
    { label: "Total Transactions", value: totalTransactions.toLocaleString(), change: "Live", icon: ShieldCheck, color: "text-amber-400" },
  ];

  const recentAlerts = [
    { id: 1, type: "system", message: "Admin Dashboard connected to Firebase successfully", time: "Just now" },
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold text-white tracking-tight">Welcome back, Admin</h1>
        <p className="text-gray-400 mt-1">Here is what's happening across Gatekipa today, pulled live from Firebase.</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {stats.map((stat, i) => (
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.1 }}
            key={i} 
            className="glass-panel rounded-2xl p-6 relative overflow-hidden group hover:border-white/15 transition-colors"
          >
            <div className={`absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity ${stat.color}`}>
              <stat.icon className="w-24 h-24 transform translate-x-4 -translate-y-4" />
            </div>
            <div className="relative z-10">
              <div className="flex justify-between items-start">
                <div className={`p-3 rounded-xl bg-white/5 ${stat.color}`}>
                  <stat.icon className="w-6 h-6" />
                </div>
                <span className={`flex items-center gap-1 text-sm font-medium px-2 py-1 rounded-full ${stat.color} bg-white/5`}>
                  <TrendingUp className="w-3 h-3" />
                  {stat.change}
                </span>
              </div>
              <div className="mt-6">
                <p className="text-gray-400 text-sm font-medium mb-1">{stat.label}</p>
                <h3 className="text-3xl font-bold text-white tracking-tight">{stat.value}</h3>
              </div>
            </div>
          </motion.div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Chart Area */}
        <div className="lg:col-span-2 glass-panel rounded-2xl p-6 min-h-[400px]">
          <div className="flex items-center justify-between mb-8">
            <h2 className="text-xl font-bold text-white">Platform Activity</h2>
            <select className="bg-white/5 border border-white/10 rounded-lg px-3 py-1.5 text-sm text-gray-300 focus:outline-none focus:border-forest-500/50">
              <option>Last 7 Days</option>
              <option>Last 30 Days</option>
              <option>This Year</option>
            </select>
          </div>
          <div className="w-full h-64 flex items-center justify-center border border-dashed border-white/10 rounded-xl">
            <p className="text-gray-500 text-sm">Real-time Chart data loading...</p>
          </div>
        </div>

        {/* Alerts Area */}
        <div className="glass-panel rounded-2xl p-6 flex flex-col">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold text-white">Priority Alerts</h2>
            <button className="text-sm text-forest-400 hover:text-forest-300">View All</button>
          </div>
          <div className="flex-1 space-y-4">
            {recentAlerts.map((alert) => (
              <div key={alert.id} className="p-4 rounded-xl bg-white/5 border border-white/5 hover:bg-white/10 transition-colors cursor-pointer group">
                <div className="flex gap-4">
                  <div className={`mt-1 shrink-0 w-2 h-2 rounded-full ${
                    alert.type === 'fraud' ? 'bg-rose-500' : 
                    alert.type === 'system' ? 'bg-amber-500' : 'bg-forest-500'
                  }`}></div>
                  <div>
                    <p className="text-sm text-gray-200 group-hover:text-white transition-colors">{alert.message}</p>
                    <p className="text-xs text-gray-500 mt-2">{alert.time}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
