"use client";

import React from "react";
import { Webhook, ArrowDownToLine } from "lucide-react";

export default function WebhooksPage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Incoming Webhooks</h1>
          <p className="text-gray-400 mt-1">Monitor asynchronous events from Bridgecard and Paystack.</p>
        </div>
      </div>

      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Event Payload</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Source</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Time</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              <tr className="hover:bg-white/5 transition-colors">
                <td className="p-4">
                  <div className="flex items-center gap-3">
                    <ArrowDownToLine className="w-4 h-4 text-gray-400" />
                    <code className="text-sm text-gray-300">charge.success</code>
                  </div>
                </td>
                <td className="p-4"><span className="text-sm font-medium text-emerald-400">Paystack</span></td>
                <td className="p-4"><span className="text-sm text-gray-400">Just now</span></td>
                <td className="p-4"><span className="px-2 py-1 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-full text-xs font-medium">Processed</span></td>
              </tr>
              <tr className="hover:bg-white/5 transition-colors">
                <td className="p-4">
                  <div className="flex items-center gap-3">
                    <ArrowDownToLine className="w-4 h-4 text-gray-400" />
                    <code className="text-sm text-gray-300">card.transaction.successful</code>
                  </div>
                </td>
                <td className="p-4"><span className="text-sm font-medium text-forest-400">Bridgecard</span></td>
                <td className="p-4"><span className="text-sm text-gray-400">2 mins ago</span></td>
                <td className="p-4"><span className="px-2 py-1 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-full text-xs font-medium">Processed</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
