"use client";

import React, { useState } from "react";
import { 
  AlertOctagon, CheckCircle2, ShieldAlert, UserX, UserCheck, 
  Smartphone, Monitor, Eye, X, Activity, CreditCard
} from "lucide-react";
import { toggleUserBlockStatus, toggleCardFreeze } from "@/app/actions/adminActions";
import { useRouter } from "next/navigation";

interface Transaction {
  id: string;
  user_id: string;
  user_email?: string;
  user_name?: string;
  user_status?: string;
  card_id?: string;
  local_status?: string;
  amount: number;
  status: string;
  merchant_name: string;
  decline_reason?: string;
  risk_score: number | null;
  risk_reasons: string[];
  created_at: string;
}

export default function FraudClient({
  initialTransactions
}: {
  initialTransactions: Transaction[];
}) {
  const router = useRouter();
  const [txns, setTxns] = useState<Transaction[]>(initialTransactions);
  const [selectedTxn, setSelectedTxn] = useState<Transaction | null>(null);
  const [activeTab, setActiveTab] = useState<"aml" | "all">("aml");
  const [isProcessing, setIsProcessing] = useState(false);

  // Filter transactions
  const amlQueue = txns.filter(t => (t.risk_score && t.risk_score >= 50) || t.status === "DECLINED");
  const currentList = activeTab === "aml" ? amlQueue : txns;

  const handleUserToggleBlock = async (userId: string, currentStatus: string) => {
    setIsProcessing(true);
    try {
      const res = await toggleUserBlockStatus(userId, currentStatus);
      if (res.success) {
        // Update local state
        setTxns(prev => prev.map(t => {
          if (t.user_id === userId) {
            return { ...t, user_status: res.status };
          }
          return t;
        }));
        if (selectedTxn && selectedTxn.user_id === userId) {
          setSelectedTxn(prev => prev ? { ...prev, user_status: res.status } : null);
        }
        alert(`User is now ${res.status}`);
      } else {
        alert("Action failed: " + res.error);
      }
    } catch (e) {
      alert("Error executing action");
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCardToggleFreeze = async (cardId: string, currentStatus: string) => {
    if (!cardId) return;
    setIsProcessing(true);
    try {
      const res = await toggleCardFreeze(cardId, currentStatus || "active");
      if (res.success) {
        // Update local state
        setTxns(prev => prev.map(t => {
          if (t.card_id === cardId) {
            return { ...t, local_status: res.status };
          }
          return t;
        }));
        if (selectedTxn && selectedTxn.card_id === cardId) {
          setSelectedTxn(prev => prev ? { ...prev, local_status: res.status } : null);
        }
        alert(`Card is now ${res.status}`);
      } else {
        alert("Action failed: " + res.error);
      }
    } catch (e) {
      alert("Error executing action");
    } finally {
      setIsProcessing(false);
    }
  };

  // Stats
  const highRiskCount = txns.filter(t => t.risk_score && t.risk_score >= 80).length;
  const blockedUsersCount = Array.from(new Set(txns.filter(t => t.user_status === "blocked").map(t => t.user_id))).length;
  const totalDeclines = txns.filter(t => t.status === "DECLINED").length;

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Fraud Operations &amp; AML Console</h1>
          <p className="text-gray-400 mt-1">Real-time algorithmic risk scoring, JIT rule violations, and compromised accounts management.</p>
        </div>
      </div>

      {/* Metrics Row */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-rose-500 flex justify-between items-center">
          <div>
            <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">High-Risk Alerts (&ge;80%)</h3>
            <p className="text-3xl font-bold text-rose-400">{highRiskCount}</p>
          </div>
          <div className="w-12 h-12 bg-rose-500/10 rounded-full flex items-center justify-center">
            <ShieldAlert className="w-6 h-6 text-rose-400" />
          </div>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-amber-500 flex justify-between items-center">
          <div>
            <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">Frozen Account Reviews</h3>
            <p className="text-3xl font-bold text-amber-400">{blockedUsersCount}</p>
          </div>
          <div className="w-12 h-12 bg-amber-500/10 rounded-full flex items-center justify-center">
            <UserX className="w-6 h-6 text-amber-400" />
          </div>
        </div>
        <div className="glass-panel rounded-2xl p-6 border-l-4 border-l-violet-500 flex justify-between items-center">
          <div>
            <h3 className="text-sm font-bold text-gray-400 uppercase tracking-wider mb-1">Sentinel Rule Blocks</h3>
            <p className="text-3xl font-bold text-violet-400">{totalDeclines}</p>
          </div>
          <div className="w-12 h-12 bg-violet-500/10 rounded-full flex items-center justify-center">
            <Activity className="w-6 h-6 text-violet-400" />
          </div>
        </div>
      </div>

      {/* Tabs Layout */}
      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="border-b border-white/5 bg-white/2 px-6 py-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex gap-2">
            <button 
              onClick={() => setActiveTab("aml")}
              className={`px-4 py-2 rounded-xl text-sm font-medium transition-colors ${activeTab === "aml" ? "bg-rose-500/20 text-rose-400 border border-rose-500/30" : "text-gray-400 hover:text-white"}`}>
              AML Flagged Queue ({amlQueue.length})
            </button>
            <button 
              onClick={() => setActiveTab("all")}
              className={`px-4 py-2 rounded-xl text-sm font-medium transition-colors ${activeTab === "all" ? "bg-white/10 text-white border border-white/10" : "text-gray-400 hover:text-white"}`}>
              All Transactions ({txns.length})
            </button>
          </div>
        </div>

        {/* Queue Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">User</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Merchant &amp; Type</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Amount</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Risk Rating</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {currentList.length === 0 ? (
                <tr>
                  <td colSpan={6} className="p-8 text-center text-gray-500 text-sm">
                    No transactions found matching active criteria.
                  </td>
                </tr>
              ) : currentList.map(t => {
                const isDeclined = t.status === "DECLINED";
                const isBlockedUser = t.user_status === "blocked";
                const risk = t.risk_score ?? 0;
                
                let scoreColor = "text-emerald-400 bg-emerald-500/10 border-emerald-500/20";
                if (risk >= 75) scoreColor = "text-rose-400 bg-rose-500/10 border-rose-500/20";
                else if (risk >= 40) scoreColor = "text-amber-400 bg-amber-500/10 border-amber-500/20";

                return (
                  <tr key={t.id} className={`hover:bg-white/5 transition-colors ${isBlockedUser ? "bg-rose-950/10" : ""}`}>
                    <td className="p-4">
                      <div>
                        <div className="font-semibold text-white">{t.user_name || "Unknown User"}</div>
                        <div className="text-xs text-gray-400">{t.user_email || "—"}</div>
                      </div>
                    </td>
                    <td className="p-4">
                      <div>
                        <div className="text-sm font-medium text-white">{t.merchant_name}</div>
                        <div className="text-xs text-gray-400 font-mono">{t.id}</div>
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="font-bold text-white">₦{t.amount.toLocaleString()}</div>
                      <div className="text-xs text-gray-400">{new Date(t.created_at).toLocaleTimeString()}</div>
                    </td>
                    <td className="p-4">
                      {t.risk_score !== null ? (
                        <span className={`px-2 py-1 rounded-full text-xs border font-bold ${scoreColor}`}>
                          {risk}% Risk
                        </span>
                      ) : (
                        <span className="text-gray-500 text-xs">—</span>
                      )}
                    </td>
                    <td className="p-4">
                      <span className={`px-2 py-1 rounded-full text-xs font-semibold border ${
                        t.status === "SUCCESS" ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/20" :
                        isDeclined ? "bg-rose-500/10 text-rose-400 border-rose-500/20" :
                        "bg-amber-500/10 text-amber-400 border-amber-500/20"
                      }`}>
                        {t.status}
                      </span>
                    </td>
                    <td className="p-4">
                      <button 
                        onClick={() => setSelectedTxn(t)}
                        className="flex items-center gap-1 bg-white/5 hover:bg-white/10 text-xs text-white px-3 py-1.5 rounded-lg border border-white/10 transition-colors font-medium">
                        <Eye className="w-3.5 h-3.5" />
                        Audit
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Details Side Drawer Modal */}
      {selectedTxn && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex justify-end">
          <div className="w-full max-w-xl bg-slate-900 border-l border-white/10 h-full flex flex-col shadow-2xl animate-in slide-in-from-right duration-200">
            {/* Drawer Header */}
            <div className="p-6 border-b border-white/10 flex items-center justify-between bg-white/2">
              <div>
                <h2 className="text-xl font-bold text-white">Transaction Audit Details</h2>
                <p className="text-xs text-gray-400 font-mono mt-1">ID: {selectedTxn.id}</p>
              </div>
              <button 
                onClick={() => setSelectedTxn(null)}
                className="text-gray-400 hover:text-white bg-white/5 p-2 rounded-xl transition-colors">
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Drawer Content */}
            <div className="p-6 space-y-6 overflow-y-auto flex-1">
              {/* Risk Analytics Card */}
              <div className="glass-panel p-6 rounded-2xl border-l-4 border-l-rose-500 space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-bold text-gray-400 uppercase tracking-wider">Sentinel Risk Report</span>
                  {selectedTxn.risk_score !== null && (
                    <span className={`px-3 py-1 rounded-full text-sm font-bold border ${
                      (selectedTxn.risk_score ?? 0) >= 70 ? "bg-rose-500/10 text-rose-400 border-rose-500/20" : "bg-amber-500/10 text-amber-400 border-amber-500/20"
                    }`}>
                      {selectedTxn.risk_score}% Risk Score
                    </span>
                  )}
                </div>

                {selectedTxn.risk_reasons && selectedTxn.risk_reasons.length > 0 ? (
                  <div className="space-y-2">
                    <h4 className="text-xs font-bold text-gray-400 uppercase tracking-wider">Flagged Risk Factors:</h4>
                    <div className="flex flex-wrap gap-2">
                      {selectedTxn.risk_reasons.map((r, i) => (
                        <span key={i} className="flex items-center gap-1.5 px-3 py-1 rounded-lg text-xs bg-rose-500/10 text-rose-400 border border-rose-500/20 font-medium">
                          <AlertOctagon className="w-3.5 h-3.5" />
                          {r}
                        </span>
                      ))}
                    </div>
                  </div>
                ) : (
                  <p className="text-sm text-gray-400 flex items-center gap-2">
                    <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                    No major risk indicators triggered by the Sentinel Risk Model.
                  </p>
                )}

                {selectedTxn.decline_reason && (
                  <div className="bg-rose-500/5 border border-rose-500/10 rounded-xl p-3">
                    <span className="text-xs text-rose-400 font-bold uppercase tracking-wider block mb-1">Decline Reason:</span>
                    <p className="text-sm text-white">{selectedTxn.decline_reason}</p>
                  </div>
                )}
              </div>

              {/* User profile */}
              <div className="glass-panel p-5 rounded-2xl space-y-4">
                <h3 className="text-sm font-bold text-white border-b border-white/5 pb-2">User Profile &amp; KYC</h3>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <span className="text-xs text-gray-400 block">Name:</span>
                    <span className="text-sm font-medium text-white">{selectedTxn.user_name || "—"}</span>
                  </div>
                  <div>
                    <span className="text-xs text-gray-400 block">Email Address:</span>
                    <span className="text-sm font-medium text-white">{selectedTxn.user_email || "—"}</span>
                  </div>
                  <div>
                    <span className="text-xs text-gray-400 block">UID:</span>
                    <span className="text-xs font-mono text-white break-all">{selectedTxn.user_id}</span>
                  </div>
                  <div>
                    <span className="text-xs text-gray-400 block">Status:</span>
                    <span className={`px-2 py-0.5 rounded-full text-xs font-semibold border ${
                      selectedTxn.user_status === "blocked" ? "bg-rose-500/10 text-rose-400 border-rose-500/20" : "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
                    }`}>
                      {selectedTxn.user_status || "active"}
                    </span>
                  </div>
                </div>
              </div>

              {/* Action Buttons Panel */}
              <div className="flex flex-col sm:flex-row gap-4 border-t border-white/10 pt-6">
                <button
                  onClick={() => handleUserToggleBlock(selectedTxn.user_id, selectedTxn.user_status || "active")}
                  disabled={isProcessing}
                  className={`flex-1 flex items-center justify-center gap-2 px-4 py-3 rounded-xl font-bold transition-colors text-sm ${
                    selectedTxn.user_status === "blocked" 
                      ? "bg-emerald-500 hover:bg-emerald-600 text-white" 
                      : "bg-rose-500 hover:bg-rose-600 text-white"
                  }`}>
                  {selectedTxn.user_status === "blocked" ? (
                    <>
                      <UserCheck className="w-4 h-4" />
                      Restore User Account
                    </>
                  ) : (
                    <>
                      <UserX className="w-4 h-4" />
                      Freeze User Account (AML Lock)
                    </>
                  )}
                </button>

                {selectedTxn.card_id && (
                  <button
                    onClick={() => handleCardToggleFreeze(selectedTxn.card_id!, selectedTxn.local_status || "active")}
                    disabled={isProcessing}
                    className={`flex-1 flex items-center justify-center gap-2 px-4 py-3 rounded-xl font-bold border text-sm transition-colors ${
                      selectedTxn.local_status === "frozen"
                        ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/30 hover:bg-emerald-500/20"
                        : "bg-amber-500/10 text-amber-400 border-amber-500/30 hover:bg-amber-500/20"
                    }`}>
                    <CreditCard className="w-4 h-4" />
                    {selectedTxn.local_status === "frozen" ? "Unfreeze Card" : "Freeze Issuing Card"}
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
