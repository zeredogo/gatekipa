"use client";

import React, { useState } from "react";
import { Wallet, Search, Filter, ArrowDownRight, ArrowUpRight } from "lucide-react";

export default function TransactionsClient({ initialTransactions, stats }: { initialTransactions: any[], stats: any }) {
  const [searchTerm, setSearchTerm] = useState("");

  const filteredTransactions = initialTransactions.filter(t => 
    t.reference.toLowerCase().includes(searchTerm.toLowerCase()) || 
    t.userId.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Wallet Transactions</h1>
          <p className="text-gray-400 mt-1">Audit fund flows, wallet top-ups, card funding, and system deductions.</p>
        </div>
        <div className="flex gap-3">
          <button className="flex items-center gap-2 bg-white/5 hover:bg-white/10 text-white px-4 py-2 rounded-xl transition-colors border border-white/10">
            <Filter className="w-4 h-4" />
            Filter
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="glass-panel rounded-2xl p-6">
          <p className="text-gray-400 text-sm font-medium mb-1">Total Vault Deposits (Recent)</p>
          <h3 className="text-3xl font-bold text-emerald-400 tracking-tight">₦{stats.vaultDeposits.toLocaleString()}</h3>
        </div>
        <div className="glass-panel rounded-2xl p-6">
          <p className="text-gray-400 text-sm font-medium mb-1">Total Card Funding (Recent)</p>
          <h3 className="text-3xl font-bold text-rose-400 tracking-tight">₦{stats.cardFunding.toLocaleString()}</h3>
        </div>
        <div className="glass-panel rounded-2xl p-6 border border-forest-500/30 bg-forest-500/5">
          <p className="text-forest-400 text-sm font-medium mb-1">Revenue Fees (Recent)</p>
          <h3 className="text-3xl font-bold text-forest-400 tracking-tight">₦{stats.revenueFees.toLocaleString()}</h3>
        </div>
      </div>

      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-4 border-b border-white/5 bg-white/5">
          <div className="relative max-w-md">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input 
              type="text" 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search reference or user ID..." 
              className="w-full bg-white/5 border border-white/10 rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-white/10 transition-all"
            />
          </div>
        </div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Transaction</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">User ID</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Amount</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Date</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {filteredTransactions.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-8 text-center text-gray-500">No transactions found.</td>
                </tr>
              ) : (
                filteredTransactions.map((tx) => (
                  <tr key={tx.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className={`w-10 h-10 rounded-full flex items-center justify-center ${tx.isDebit ? 'bg-rose-500/10' : 'bg-emerald-500/10'}`}>
                          {tx.isDebit ? <ArrowUpRight className="w-5 h-5 text-rose-400" /> : <ArrowDownRight className="w-5 h-5 text-emerald-400" />}
                        </div>
                        <div>
                          <p className="text-sm font-medium text-white capitalize">{tx.type.replace('_', ' ')}</p>
                          <p className="text-xs text-gray-500">Ref: {tx.reference}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-4">
                      <p className="text-gray-300 font-mono text-xs truncate max-w-[100px]">{tx.userId}</p>
                    </td>
                    <td className="p-4">
                      <span className={`text-sm font-bold ${tx.isDebit ? 'text-white' : 'text-emerald-400'}`}>
                        {tx.isDebit ? '-' : '+'}₦{tx.amount.toLocaleString()}
                      </span>
                    </td>
                    <td className="p-4">
                      <span className="text-sm text-gray-400">{tx.createdAt}</span>
                    </td>
                    <td className="p-4">
                      <span className={`px-2 py-1 rounded-full text-xs font-medium border ${
                        tx.status === 'success' ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20' : 
                        tx.status === 'pending' ? 'bg-amber-500/10 text-amber-400 border-amber-500/20' : 
                        'bg-rose-500/10 text-rose-400 border-rose-500/20'
                      }`}>
                        {tx.status}
                      </span>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
