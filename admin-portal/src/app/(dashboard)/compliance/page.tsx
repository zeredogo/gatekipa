"use client";

import React from "react";
import { ShieldCheck, Search, Filter } from "lucide-react";

export default function CompliancePage() {
  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Compliance & KYC Inbox</h1>
          <p className="text-gray-400 mt-1">Review flagged accounts and manual identity verification requests.</p>
        </div>
      </div>

      <div className="glass-panel rounded-2xl overflow-hidden p-8 flex flex-col items-center justify-center text-center min-h-[400px]">
        <div className="w-16 h-16 rounded-full bg-forest-500/10 flex items-center justify-center mb-4">
          <ShieldCheck className="w-8 h-8 text-forest-400" />
        </div>
        <h3 className="text-xl font-bold text-white mb-2">Inbox Zero</h3>
        <p className="text-gray-400 max-w-md">There are no pending manual KYC reviews. All active users have successfully completed automated identity verification via QoreID.</p>
      </div>
    </div>
  );
}
