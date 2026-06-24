import React from "react";
import {
  Webhook, CheckCircle2, XCircle, AlertTriangle,
  Zap, ShieldCheck, Clock, ArrowDownToLine, RefreshCw
} from "lucide-react";
import { db } from "@/lib/firebaseAdmin";

export const dynamic = "force-dynamic";

// ── Helpers ──────────────────────────────────────────────────────────────────

function formatTs(val: { toDate?: () => Date } | string | number | Date | null | undefined | unknown): string {
  if (!val) return "—";
  try {
    const d = (val as { toDate?: () => Date })?.toDate ? (val as { toDate: () => Date }).toDate() : new Date(val as string | number | Date);
    return d.toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" });
  } catch { return "—"; }
}

function sourceLabel(source: string) {
  if (source?.includes("sudo"))      return { label: "Sudo Africa", color: "text-violet-400" };
  if (source?.includes("paystack"))  return { label: "Paystack",    color: "text-emerald-400" };
  if (source?.includes("bridgecard"))return { label: "Bridgecard",  color: "text-sky-400"     };
  return { label: source ?? "Unknown", color: "text-gray-400" };
}

function statusBadge(status: string) {
  const s = (status ?? "").toLowerCase();
  if (["completed", "approved", "received", "settled"].includes(s))
    return "bg-emerald-500/10 text-emerald-400 border-emerald-500/20";
  if (["processing", "reserved"].includes(s))
    return "bg-amber-500/10 text-amber-400 border-amber-500/20";
  if (["failed", "declined", "sweep_error"].includes(s))
    return "bg-rose-500/10 text-rose-400 border-rose-500/20";
  return "bg-white/5 text-gray-400 border-white/10";
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default async function WebhooksPage() {

  // ── 1. Recent webhook events ───────────────────────────────────────────────
  const webhooksSnap = await db.collection("webhook_events")
    .orderBy("created_at", "desc")
    .limit(50)
    .get();

  const webhooks = webhooksSnap.docs.map(doc => {
    const d = doc.data();
    return {
      id:     doc.id,
      event:  d.event_type || d.event || d.type || doc.id,
      source: d.source || "unknown",
      time:   formatTs(d.created_at),
      status: d.status || "Received",
    };
  });

  // ── 2. JIT Authorization stats (last 200 wallet_ledger entries) ───────────
  const jitSnap = await db.collection("wallet_ledger")
    .where("source", "==", "sudo_jit_auth")
    .orderBy("created_at", "desc")
    .limit(200)
    .get();

  let jitApproved = 0, jitReserved = 0;
  let jitTotalKobo = 0;

  jitSnap.docs.forEach(doc => {
    const d = doc.data();
    jitTotalKobo += d.amount_kobo ?? 0;
    if (d.status === "reserved") jitReserved++;
    else if (d.status === "settled") { jitApproved++; }
    else jitApproved++;
  });

  // ── 3. Recent JIT declines ─────────────────────────────────────────────────
  const declinesSnap = await db.collection("transactions")
    .where("status", "==", "DECLINED")
    .where("source", "==", "sudo_jit_auth")
    .orderBy("created_at", "desc")
    .limit(20)
    .get();

  const declines = declinesSnap.docs.map(doc => {
    const d = doc.data();
    return {
      id:       doc.id,
      merchant: d.merchant_name ?? "Unknown",
      reason:   d.decline_reason ?? "Unknown",
      amount:   d.amount ?? 0,
      time:     formatTs(d.created_at),
    };
  });

  const jitTotal    = jitApproved + declines.length;
  const approvalRate = jitTotal > 0 ? Math.round((jitApproved / jitTotal) * 100) : 100;
  const declineRate  = 100 - approvalRate;

  // ── 4. Ghost card queue status ─────────────────────────────────────────────
  const queueSnap = await db.collection("card_provisioning_queue")
    .orderBy("created_at", "desc")
    .limit(20)
    .get();

  const queue = queueSnap.docs.map(doc => {
    const d = doc.data();
    return {
      id:       doc.id,
      uid:      d.uid ?? "—",
      card_id:  d.card_id ?? "—",
      currency: d.card_currency ?? "NGN",
      status:   d.status ?? "PENDING",
      time:     formatTs(d.created_at ? new Date(d.created_at) : null),
    };
  });

  return (
    <div className="space-y-8">

      {/* ── Header ─────────────────────────────────────────────────────── */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">
            Webhook &amp; JIT Monitor
          </h1>
          <p className="text-gray-400 mt-1">
            Real-time JIT authorization health, decline analysis, and provider event feed.
          </p>
        </div>
        <div className="flex items-center gap-2 text-xs text-gray-500 bg-white/5 border border-white/10 rounded-xl px-4 py-2">
          <RefreshCw className="w-3 h-3" />
          Live · force-dynamic
        </div>
      </div>

      {/* ── JIT Stats Row ──────────────────────────────────────────────── */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="glass-panel rounded-2xl p-5">
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-400" />
            <span className="text-xs text-gray-400 font-medium uppercase tracking-wider">Approved</span>
          </div>
          <p className="text-3xl font-bold text-white">{jitApproved}</p>
          <p className="text-xs text-emerald-400 mt-1">{approvalRate}% approval rate</p>
        </div>
        <div className="glass-panel rounded-2xl p-5">
          <div className="flex items-center gap-2 mb-2">
            <XCircle className="w-4 h-4 text-rose-400" />
            <span className="text-xs text-gray-400 font-medium uppercase tracking-wider">Declined</span>
          </div>
          <p className="text-3xl font-bold text-white">{declines.length}</p>
          <p className="text-xs text-rose-400 mt-1">{declineRate}% decline rate</p>
        </div>
        <div className="glass-panel rounded-2xl p-5">
          <div className="flex items-center gap-2 mb-2">
            <Clock className="w-4 h-4 text-amber-400" />
            <span className="text-xs text-gray-400 font-medium uppercase tracking-wider">Reserved</span>
          </div>
          <p className="text-3xl font-bold text-white">{jitReserved}</p>
          <p className="text-xs text-amber-400 mt-1">Awaiting settlement</p>
        </div>
        <div className="glass-panel rounded-2xl p-5">
          <div className="flex items-center gap-2 mb-2">
            <Zap className="w-4 h-4 text-violet-400" />
            <span className="text-xs text-gray-400 font-medium uppercase tracking-wider">JIT Volume</span>
          </div>
          <p className="text-3xl font-bold text-white">₦{(jitTotalKobo / 100).toLocaleString()}</p>
          <p className="text-xs text-violet-400 mt-1">Total authorised</p>
        </div>
      </div>

      {/* ── Recent Declines ────────────────────────────────────────────── */}
      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-4 border-b border-white/5 flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 text-rose-400" />
          <h2 className="text-sm font-semibold text-white">Recent JIT Declines</h2>
          <span className="ml-auto text-xs text-gray-500">Sudo Africa · NGN Cards</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Merchant</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Amount</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Reason</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Time</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {declines.length === 0 ? (
                <tr><td colSpan={4} className="p-8 text-center text-gray-500 text-sm">No recent declines — system is healthy ✓</td></tr>
              ) : declines.map(d => (
                <tr key={d.id} className="hover:bg-white/5 transition-colors">
                  <td className="p-4 text-sm text-white font-medium">{d.merchant}</td>
                  <td className="p-4 text-sm text-rose-400 font-bold">₦{d.amount.toLocaleString()}</td>
                  <td className="p-4">
                    <span className="px-2 py-1 rounded-full text-xs border bg-rose-500/10 text-rose-400 border-rose-500/20">
                      {d.reason}
                    </span>
                  </td>
                  <td className="p-4 text-sm text-gray-400">{d.time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Ghost Card Queue ───────────────────────────────────────────── */}
      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-4 border-b border-white/5 flex items-center gap-2">
          <ShieldCheck className="w-4 h-4 text-sky-400" />
          <h2 className="text-sm font-semibold text-white">Card Provisioning Queue</h2>
          <span className="ml-auto text-xs text-gray-500">Ghost Card Sweeper · DLQ</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Card ID</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">UID</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Provider</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Time</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {queue.length === 0 ? (
                <tr><td colSpan={5} className="p-8 text-center text-gray-500 text-sm">Queue is empty.</td></tr>
              ) : queue.map(q => (
                <tr key={q.id} className="hover:bg-white/5 transition-colors">
                  <td className="p-4 font-mono text-xs text-gray-300 truncate max-w-[120px]">{q.card_id}</td>
                  <td className="p-4 font-mono text-xs text-gray-400 truncate max-w-[100px]">{q.uid}</td>
                  <td className="p-4">
                    <span className={`text-xs font-medium ${q.currency === "USD" ? "text-sky-400" : "text-violet-400"}`}>
                      {q.currency === "USD" ? "Bridgecard" : "Sudo Africa"}
                    </span>
                  </td>
                  <td className="p-4">
                    <span className={`px-2 py-1 rounded-full text-xs border ${statusBadge(q.status)}`}>
                      {q.status}
                    </span>
                  </td>
                  <td className="p-4 text-sm text-gray-400">{q.time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Raw Webhook Event Feed ─────────────────────────────────────── */}
      <div className="glass-panel rounded-2xl overflow-hidden">
        <div className="p-4 border-b border-white/5 flex items-center gap-2">
          <Webhook className="w-4 h-4 text-gray-400" />
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
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {webhooks.length === 0 ? (
                <tr><td colSpan={4} className="p-8 text-center text-gray-500">No recent webhooks found.</td></tr>
              ) : webhooks.map(hook => {
                const { label, color } = sourceLabel(hook.source);
                return (
                  <tr key={hook.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <ArrowDownToLine className="w-4 h-4 text-gray-500 shrink-0" />
                        <code className="text-xs text-gray-300 break-all">{hook.event}</code>
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
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

    </div>
  );
}
