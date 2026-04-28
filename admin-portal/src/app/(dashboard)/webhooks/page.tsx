import React from "react";
import { Webhook, ArrowDownToLine } from "lucide-react";
import { db } from "@/lib/firebaseAdmin";

export const dynamic = "force-dynamic";

export default async function WebhooksPage() {
  const webhooksSnapshot = await db.collection("webhook_events").orderBy("created_at", "desc").limit(25).get();
  
  const webhooks = webhooksSnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      event: data.event_type || data.event || doc.id,
      source: data.source || (data.event?.includes('card') ? 'bridgecard_webhook' : 'paystack_webhook'),
      time: data.created_at ? new Date(data.created_at.toDate ? data.created_at.toDate() : data.created_at).toLocaleString() : "Unknown",
      status: data.status || "Processed"
    };
  });

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
              {webhooks.length === 0 ? (
                <tr>
                  <td colSpan={4} className="p-8 text-center text-gray-500">No recent webhooks found.</td>
                </tr>
              ) : (
                webhooks.map((hook) => (
                  <tr key={hook.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <ArrowDownToLine className="w-4 h-4 text-gray-400" />
                        <code className="text-sm text-gray-300">{hook.event}</code>
                      </div>
                    </td>
                    <td className="p-4">
                      <span className={`text-sm font-medium capitalize ${hook.source.includes('paystack') ? 'text-emerald-400' : 'text-forest-400'}`}>
                        {hook.source.replace('_webhook', '')}
                      </span>
                    </td>
                    <td className="p-4"><span className="text-sm text-gray-400">{hook.time}</span></td>
                    <td className="p-4">
                      <span className={`px-2 py-1 ${hook.status.toLowerCase() === 'failed' ? 'bg-rose-500/10 text-rose-400 border-rose-500/20' : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'} border rounded-full text-xs font-medium`}>
                        {hook.status}
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
