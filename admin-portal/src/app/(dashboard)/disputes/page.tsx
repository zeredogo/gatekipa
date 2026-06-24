"use client";

import React, { useEffect, useState } from "react";
import { Flag, CheckCircle2, XCircle } from "lucide-react";
import { collection, query, orderBy, onSnapshot, doc, updateDoc } from "firebase/firestore";
import { db } from "@/lib/firebaseClient";

interface Dispute {
  id: string;
  transaction_id: string;
  card_id: string;
  user_id: string;
  amount: number;
  merchant: string;
  reason: string;
  description: string;
  status: "open" | "resolved" | "rejected";
  provider_reference?: string;
  created_at: { toDate: () => Date };
}

export default function DisputesPage() {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<"all" | "open" | "resolved" | "rejected">("open");

  useEffect(() => {
    const q = query(collection(db, "disputes"), orderBy("created_at", "desc"));
    const unsub = onSnapshot(q, (snap) => {
      const data: Dispute[] = [];
      snap.forEach((doc) => {
        data.push({ id: doc.id, ...doc.data() } as Dispute);
      });
      setDisputes(data);
      setLoading(false);
    });
    return () => unsub();
  }, []);

  const handleUpdateStatus = async (id: string, newStatus: "resolved" | "rejected") => {
    try {
      await updateDoc(doc(db, "disputes", id), {
        status: newStatus,
        updated_at: new Date()
      });
    } catch (err) {
      console.error("Failed to update dispute status", err);
      alert("Failed to update status.");
    }
  };

  const filtered = disputes.filter(d => filter === "all" || d.status === filter);

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Disputes</h1>
          <p className="text-gray-400 mt-1">Review and manage user-reported transaction disputes.</p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-2 overflow-x-auto pb-2">
        {["open", "resolved", "rejected", "all"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f as "all" | "open" | "resolved" | "rejected")}
            className={`px-4 py-2 rounded-xl text-sm font-medium transition-colors whitespace-nowrap ${
              filter === f
                ? "bg-forest-500 text-white"
                : "bg-surface-800 text-gray-400 hover:text-white hover:bg-surface-700"
            }`}
          >
            {f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-12">
          <div className="w-8 h-8 border-4 border-forest-500 border-t-transparent rounded-full animate-spin"></div>
        </div>
      ) : filtered.length === 0 ? (
        <div className="glass-panel rounded-2xl p-8 flex flex-col items-center justify-center text-center min-h-[300px]">
          <div className="w-16 h-16 rounded-full bg-forest-500/10 flex items-center justify-center mb-4">
            <Flag className="w-8 h-8 text-forest-400" />
          </div>
          <h3 className="text-xl font-bold text-white mb-2">No {filter !== "all" ? filter : ""} disputes found</h3>
          <p className="text-gray-400 max-w-md">All clear! Users haven&apos;t reported any unauthorized or duplicate charges.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filtered.map((d) => (
            <div key={d.id} className="glass-panel p-6 rounded-2xl flex flex-col lg:flex-row gap-6 lg:items-center justify-between">
              <div className="space-y-3 flex-1">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-3 mb-1">
                      <span className={`px-2.5 py-1 text-xs font-bold rounded-md ${
                        d.status === 'open' ? 'bg-amber-500/20 text-amber-400' :
                        d.status === 'resolved' ? 'bg-forest-500/20 text-forest-400' :
                        'bg-red-500/20 text-red-400'
                      }`}>
                        {d.status.toUpperCase()}
                      </span>
                      <span className="text-gray-400 text-sm">{new Date(d.created_at?.toDate()).toLocaleString()}</span>
                    </div>
                    <h3 className="text-xl font-bold text-white">{d.merchant}</h3>
                    <p className="text-gray-300 font-medium">{d.reason}</p>
                  </div>
                  <div className="text-right">
                    <div className="text-xl font-bold text-red-400">-₦{d.amount.toLocaleString()}</div>
                  </div>
                </div>

                {d.description && (
                  <div className="bg-surface-900/50 p-3 rounded-xl border border-white/5">
                    <p className="text-sm text-gray-400">{d.description}</p>
                  </div>
                )}

                <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 pt-2">
                  <div>
                    <div className="text-xs text-gray-500 mb-1">User ID</div>
                    <div className="text-sm text-gray-300 font-mono truncate">{d.user_id}</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500 mb-1">Card ID</div>
                    <div className="text-sm text-gray-300 font-mono truncate">{d.card_id}</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500 mb-1">Transaction ID</div>
                    <div className="text-sm text-gray-300 font-mono truncate">{d.transaction_id}</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500 mb-1">Provider Ref</div>
                    <div className="text-sm text-gray-300 font-mono truncate">{d.provider_reference || "N/A"}</div>
                  </div>
                </div>
              </div>

              {d.status === "open" && (
                <div className="flex flex-row lg:flex-col gap-2 shrink-0 border-t border-white/5 lg:border-t-0 pt-4 lg:pt-0">
                  <button 
                    onClick={() => handleUpdateStatus(d.id, "resolved")}
                    className="flex-1 lg:flex-none flex items-center justify-center gap-2 bg-forest-500/20 hover:bg-forest-500/30 text-forest-400 px-4 py-2.5 rounded-xl transition-colors font-medium text-sm"
                  >
                    <CheckCircle2 className="w-4 h-4" /> Resolve
                  </button>
                  <button 
                    onClick={() => handleUpdateStatus(d.id, "rejected")}
                    className="flex-1 lg:flex-none flex items-center justify-center gap-2 bg-red-500/20 hover:bg-red-500/30 text-red-400 px-4 py-2.5 rounded-xl transition-colors font-medium text-sm"
                  >
                    <XCircle className="w-4 h-4" /> Reject
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
