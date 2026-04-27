"use client";

import React, { useState, useTransition } from "react";
import { CreditCard, Search, Filter, Snowflake, CheckCircle, Loader2 } from "lucide-react";
import { toggleCardFreeze } from "@/app/actions/adminActions";

export default function CardsClient({ initialCards }: { initialCards: any[] }) {
  const [searchTerm, setSearchTerm] = useState("");
  const [cards, setCards] = useState(initialCards);
  const [pendingCardId, setPendingCardId] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const handleToggleStatus = (cardId: string, currentStatus: string) => {
    setPendingCardId(cardId);
    startTransition(async () => {
      const result = await toggleCardFreeze(cardId, currentStatus);
      if (result.success) {
        setCards(cards.map(c => c.id === cardId ? { ...c, status: result.status } : c));
      } else {
        alert("Failed to update card status");
      }
      setPendingCardId(null);
    });
  };

  const filteredCards = cards.filter(c => 
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
    c.last4.includes(searchTerm) ||
    c.id.includes(searchTerm)
  );

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Virtual Cards</h1>
          <p className="text-gray-400 mt-1">Monitor issued Bridgecard virtual cards, status, and associated risks.</p>
        </div>
        <div className="flex gap-3">
          <button className="flex items-center gap-2 bg-white/5 hover:bg-white/10 text-white px-4 py-2 rounded-xl transition-colors border border-white/10">
            <Filter className="w-4 h-4" />
            Filter
          </button>
        </div>
      </div>

      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-4 border-b border-white/5 bg-white/5 flex gap-4">
          <div className="relative max-w-md flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input 
              type="text" 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search by Card Name or Last 4 digits..." 
              className="w-full bg-white/5 border border-white/10 rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-white/10 transition-all"
            />
          </div>
        </div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Card Details</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Owner ID</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Balance</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {filteredCards.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-8 text-center text-gray-500">No cards found.</td>
                </tr>
              ) : (
                filteredCards.map((card) => (
                  <tr key={card.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className={`w-12 h-8 rounded flex items-center justify-center border border-white/10 ${card.status === 'active' ? 'bg-linear-to-tr from-forest-600 to-forest-400' : 'bg-linear-to-tr from-gray-600 to-gray-400 opacity-70'}`}>
                          <span className="text-[10px] font-bold text-white tracking-widest">****</span>
                        </div>
                        <div>
                          <p className="text-sm font-medium text-white">{card.name}</p>
                          <p className="text-xs text-gray-500">**** {card.last4}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-4">
                      <p className="text-gray-300 font-mono text-xs truncate max-w-[100px]">{card.ownerId}</p>
                    </td>
                    <td className="p-4">
                      {card.status === "active" ? (
                        <span className="inline-flex items-center gap-1 px-2 py-1 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-full text-xs font-medium">
                          <CheckCircle className="w-3 h-3" />
                          Active
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2 py-1 bg-forest-500/10 text-forest-400 border border-forest-500/20 rounded-full text-xs font-medium">
                          <Snowflake className="w-3 h-3" />
                          Frozen
                        </span>
                      )}
                    </td>
                    <td className="p-4">
                      <span className="text-sm font-medium text-white">₦{card.balance.toLocaleString()}</span>
                    </td>
                    <td className="p-4">
                      <button 
                        onClick={() => handleToggleStatus(card.id, card.status)}
                        disabled={pendingCardId === card.id}
                        className={`text-sm font-medium flex items-center gap-1 disabled:opacity-50 ${card.status === 'active' ? 'text-rose-400 hover:text-rose-300' : 'text-emerald-400 hover:text-emerald-300'}`}
                      >
                        {pendingCardId === card.id ? (
                          <Loader2 className="w-4 h-4 animate-spin" />
                        ) : (
                          card.status === 'active' ? <><Snowflake className="w-4 h-4" /> Freeze</> : <><CheckCircle className="w-4 h-4" /> Unfreeze</>
                        )}
                      </button>
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
