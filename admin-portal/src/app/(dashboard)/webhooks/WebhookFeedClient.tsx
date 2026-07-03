"use client";

import React, { useState } from "react";
import { ArrowDownToLine, RefreshCw, AlertCircle, CheckCircle2, Play } from "lucide-react";
import { retryWebhookPayload } from "@/app/actions/adminActions";

interface WebhookEvent {
  id: string;
  event: string;
  source: string;
  time: string;
  status: string;
  retry_count?: number;
  retry_error?: string | null;
  last_retry?: string | null;
}

export default function WebhookFeedClient({
  initialWebhooks
}: {
  initialWebhooks: WebhookEvent[];
}) {
  const [webhooks, setWebhooks] = useState<WebhookEvent[]>(initialWebhooks);
  const [retryingId, setRetryingId] = useState<string | null>(null);

  const handleRetry = async (id: string) => {
    setRetryingId(id);
    try {
      const res = await retryWebhookPayload(id);
      if (res.success) {
        alert(res.message || "Webhook payload successfully retried and processed!");
        // Update local state status to Received (or let client router refresh)
        setWebhooks(prev => prev.map(w => {
          if (w.id === id) {
            return {
              ...w,
              status: "Received",
              retry_count: (w.retry_count || 0) + 1,
              retry_error: null
            };
          }
          return w;
        }));
      } else {
        alert("Retry Failed: " + res.error);
        setWebhooks(prev => prev.map(w => {
          if (w.id === id) {
            return {
              ...w,
              status: "Failed",
              retry_count: (w.retry_count || 0) + 1,
              retry_error: res.error
            };
          }
          return w;
        }));
      }
    } catch (e) {
      alert("Error retrying webhook");
    } finally {
      setRetryingId(null);
    }
  };

  const sourceLabel = (source: string) => {
    if (source?.includes("sudo"))      return { label: "Sudo Africa", color: "text-violet-400" };
    if (source?.includes("paystack"))  return { label: "Paystack",    color: "text-emerald-400" };
    if (source?.includes("bridgecard"))return { label: "Bridgecard",  color: "text-sky-400"     };
    return { label: source ?? "Unknown", color: "text-gray-400" };
  };

  const statusBadge = (status: string) => {
    const s = (status ?? "").toLowerCase();
    if (["completed", "approved", "received", "settled"].includes(s))
      return "bg-emerald-500/10 text-emerald-400 border-emerald-500/20";
    if (["processing", "reserved"].includes(s))
      return "bg-amber-500/10 text-amber-400 border-amber-500/20";
    if (["failed", "declined", "sweep_error"].includes(s))
      return "bg-rose-500/10 text-rose-400 border-rose-500/20";
    return "bg-white/5 text-gray-400 border-white/10";
  };

  return (
    <div className="glass-panel rounded-2xl overflow-hidden">
      <div className="p-4 border-b border-white/5 flex items-center gap-2">
        <RefreshCw className="w-4 h-4 text-violet-400" />
        <h2 className="text-sm font-semibold text-white">Incoming Webhook Feed</h2>
        <span className="ml-auto text-xs text-gray-500">Last 50 events · all providers</span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left">
          <thead>
            <tr className="border-b border-white/10 bg-white/5">
              <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Event</th>
              <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Provider</th>
              <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Time</th>
              <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
              <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {webhooks.length === 0 ? (
              <tr>
                <td colSpan={5} className="p-8 text-center text-gray-500">No recent webhooks found.</td>
              </tr>
            ) : webhooks.map(hook => {
              const { label, color } = sourceLabel(hook.source);
              const isRetrying = retryingId === hook.id;
              const hasFailed = (hook.status ?? "").toLowerCase().includes("fail");

              return (
                <tr key={hook.id} className="hover:bg-white/5 transition-colors">
                  <td className="p-4">
                    <div className="flex items-center gap-3">
                      <ArrowDownToLine className="w-4 h-4 text-gray-500 shrink-0" />
                      <div>
                        <code className="text-xs text-gray-300 break-all">{hook.event}</code>
                        {hook.retry_count && hook.retry_count > 0 ? (
                          <div className="text-[10px] text-amber-400 mt-0.5">
                            Retried {hook.retry_count}x {hook.last_retry ? `(Last: ${hook.last_retry})` : ""}
                          </div>
                        ) : null}
                        {hook.retry_error ? (
                          <div className="text-[10px] text-rose-400 mt-0.5 font-mono max-w-xs truncate">
                            Error: {hook.retry_error}
                          </div>
                        ) : null}
                      </div>
                    </div>
                  </td>
                  <td className="p-4">
                    <span className={`text-sm font-medium ${color}`}>{label}</span>
                  </td>
                  <td className="p-4 text-sm text-gray-400 whitespace-nowrap">{hook.time}</td>
                  <td className="p-4">
                    <span className={`px-2 py-1 rounded-full text-xs border ${statusBadge(hook.status)}`}>
                      {hook.status}
                    </span>
                  </td>
                  <td className="p-4 text-right">
                    <button
                      onClick={() => handleRetry(hook.id)}
                      disabled={isRetrying}
                      title="Re-execute this webhook payload"
                      className="inline-flex items-center gap-1 bg-violet-500 hover:bg-violet-600 disabled:opacity-50 text-xs text-white px-3 py-1.5 rounded-lg transition-colors font-medium">
                      <Play className={`w-3 h-3 ${isRetrying ? "animate-spin" : ""}`} />
                      {isRetrying ? "Retrying..." : "Retry Payload"}
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
