"use client";

import React, { useState, useTransition } from "react";
import { 
  Users, Search, Filter, X, Check, Ban, Send, 
  Smartphone, MapPin, CreditCard, Calendar, ShieldCheck, ShieldAlert, Loader2 
} from "lucide-react";
import { approveKyc, toggleUserBlockStatus, sendInAppNotification, dispatchAdminBroadcast } from "@/app/actions/adminActions";

interface UserData {
  id: string;
  displayName: string;
  email: string;
  isVerified: boolean;
  planTier: string;
  createdAt: string;
  phoneNumber?: string;
  address?: string;
  kycStatus?: string;
  selfieUrl?: string;
  documentUrl?: string;
  idNumber?: string;
  spendingLock?: boolean;
  nightLockdown?: boolean;
  geoFence?: boolean;
  fcmToken?: string;
}

export default function UsersClient({ initialUsers }: { initialUsers: UserData[] }) {
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedUser, setSelectedUser] = useState<UserData | null>(null);
  const [notifTitle, setNotifTitle] = useState("");
  const [notifBody, setNotifBody] = useState("");
  const [sendingNotif, setSendingNotif] = useState(false);

  // KYC Filter State
  const [kycFilter, setKycFilter] = useState<"all" | "verified" | "pending_review" | "pending">("all");
  const [showFilterDropdown, setShowFilterDropdown] = useState(false);

  // Broadcast Modal State
  const [showBroadcastModal, setShowBroadcastModal] = useState(false);
  const [broadcastTitle, setBroadcastTitle] = useState("");
  const [broadcastBody, setBroadcastBody] = useState("");
  const [broadcastChannels, setBroadcastChannels] = useState({
    push: true,
    inApp: true,
    email: false,
    whatsapp: false,
  });
  const [sendingBroadcast, setSendingBroadcast] = useState(false);
  
  const [isPending, startTransition] = useTransition();

  const filteredUsers = initialUsers.filter(u => {
    const matchesSearch = 
      u.displayName?.toLowerCase().includes(searchTerm.toLowerCase()) || 
      u.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      u.id?.toLowerCase().includes(searchTerm.toLowerCase());
      
    const matchesKyc = 
      kycFilter === "all" ||
      (kycFilter === "verified" && u.isVerified) ||
      (kycFilter === "pending_review" && u.kycStatus === "pending_review") ||
      (kycFilter === "pending" && !u.isVerified && u.kycStatus !== "pending_review");

    return matchesSearch && matchesKyc;
  });

  const handleExportUsers = () => {
    const headers = ["User ID", "Name", "Email", "Phone", "KYC Status", "Plan Tier", "Joined Date"];
    const rows = filteredUsers.map(u => [
      u.id,
      u.displayName,
      u.email,
      u.phoneNumber || "",
      u.kycStatus || "pending",
      u.planTier,
      u.createdAt
    ]);

    const csvContent = "data:text/csv;charset=utf-8," 
      + [headers.join(","), ...rows.map(e => e.map(val => `"${val.replace(/"/g, '""')}"`).join(","))].join("\n");
      
    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `gatekipa_users_export_${new Date().toISOString().split('T')[0]}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleApproveKyc = (userId: string) => {
    startTransition(async () => {
      const res = await approveKyc(userId);
      if (res.success) {
        alert("KYC approved successfully!");
        if (selectedUser && selectedUser.id === userId) {
          setSelectedUser({
            ...selectedUser,
            isVerified: true,
            kycStatus: "verified"
          });
        }
      } else {
        alert(res.error || "Failed to approve KYC.");
      }
    });
  };

  const handleToggleBlock = (userId: string, currentStatus: string) => {
    startTransition(async () => {
      const res = await toggleUserBlockStatus(userId, currentStatus);
      if (res.success) {
        alert(`User status is now ${res.status}`);
        if (selectedUser && selectedUser.id === userId) {
          setSelectedUser({
            ...selectedUser,
            kycStatus: res.status
          });
        }
      } else {
        alert(res.error || "Failed to update block status.");
      }
    });
  };

  const handleSendNotification = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser || !notifTitle || !notifBody) return;
    
    setSendingNotif(true);
    try {
      const res = await sendInAppNotification(selectedUser.id, notifTitle, notifBody);
      if (res.success) {
        alert("Notification sent successfully!");
        setNotifTitle("");
        setNotifBody("");
      } else {
        alert(res.error || "Failed to send notification.");
      }
    } catch (err) {
      console.error(err);
      alert("Error sending notification.");
    } finally {
      setSendingNotif(false);
    }
  };

  const handleSendBroadcast = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!broadcastTitle || !broadcastBody) return;
    
    // Warn if no channels are selected
    if (!broadcastChannels.push && !broadcastChannels.inApp && !broadcastChannels.email && !broadcastChannels.whatsapp) {
      alert("Please select at least one channel for the broadcast.");
      return;
    }

    setSendingBroadcast(true);
    try {
      const res = await dispatchAdminBroadcast(broadcastChannels, broadcastTitle, broadcastBody);
      if (res.success) {
        alert(`Broadcast sent successfully!\n- Notifications dispatched: ${res.notifCount}\n- Emails sent: ${res.emailCount}`);
        setBroadcastTitle("");
        setBroadcastBody("");
        setShowBroadcastModal(false);
      } else {
        alert(res.error || "Failed to dispatch broadcast.");
      }
    } catch (err: any) {
      alert("Error sending broadcast: " + err.message);
    } finally {
      setSendingBroadcast(false);
    }
  };

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Users & KYC</h1>
          <p className="text-gray-400 mt-1">Manage platform users, verify identities, and review account statuses.</p>
        </div>
        <div className="flex gap-3 relative">
          <div className="relative">
            <button 
              onClick={() => setShowFilterDropdown(!showFilterDropdown)}
              className="flex items-center gap-2 bg-white/5 hover:bg-white/10 text-white px-4 py-2 rounded-xl transition-colors border border-white/10 cursor-pointer"
            >
              <Filter className="w-4 h-4" />
              Filter: {kycFilter === "all" ? "All" : kycFilter === "verified" ? "Verified" : kycFilter === "pending_review" ? "Pending Review" : "Pending"}
            </button>
            {showFilterDropdown && (
              <div className="absolute right-0 mt-2 w-48 rounded-xl bg-neutral-900 border border-white/10 shadow-lg z-50 p-1.5 space-y-1">
                <button 
                  onClick={() => { setKycFilter("all"); setShowFilterDropdown(false); }}
                  className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium cursor-pointer transition-colors ${kycFilter === "all" ? "bg-forest-500 text-white-literal" : "text-gray-400 hover:bg-white/5 hover:text-white"}`}
                >
                  All Users
                </button>
                <button 
                  onClick={() => { setKycFilter("verified"); setShowFilterDropdown(false); }}
                  className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium cursor-pointer transition-colors ${kycFilter === "verified" ? "bg-forest-500 text-white-literal" : "text-gray-400 hover:bg-white/5 hover:text-white"}`}
                >
                  Verified KYC
                </button>
                <button 
                  onClick={() => { setKycFilter("pending_review"); setShowFilterDropdown(false); }}
                  className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium cursor-pointer transition-colors ${kycFilter === "pending_review" ? "bg-forest-500 text-white-literal" : "text-gray-400 hover:bg-white/5 hover:text-white"}`}
                >
                  Pending Review KYC
                </button>
                <button 
                  onClick={() => { setKycFilter("pending"); setShowFilterDropdown(false); }}
                  className={`w-full text-left px-3 py-2 rounded-lg text-xs font-medium cursor-pointer transition-colors ${kycFilter === "pending" ? "bg-forest-500 text-white-literal" : "text-gray-400 hover:bg-white/5 hover:text-white"}`}
                >
                  Pending KYC
                </button>
              </div>
            )}
          </div>
          <button 
            onClick={() => setShowBroadcastModal(true)}
            className="flex items-center gap-2 bg-forest-600 hover:bg-forest-700 text-white-literal px-4 py-2 rounded-xl transition-colors font-medium cursor-pointer"
          >
            <Send className="w-4 h-4" />
            Send Broadcast
          </button>
          <button 
            onClick={handleExportUsers}
            className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white-literal px-4 py-2 rounded-xl transition-colors font-medium cursor-pointer"
          >
            <Users className="w-4 h-4" />
            Export Users
          </button>
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
              placeholder="Search by name, email, or UID..." 
              className="w-full bg-white/5 border border-white/10 rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-white/10 transition-all"
            />
          </div>
        </div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-white/10 bg-white/5">
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">User</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">KYC Status</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Plan Tier</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Joined</th>
                <th className="p-4 text-xs font-semibold text-gray-400 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {filteredUsers.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-8 text-center text-gray-500">No users found.</td>
                </tr>
              ) : (
                filteredUsers.map((user) => (
                  <tr key={user.id} className="hover:bg-white/5 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-linear-to-br from-forest-600 to-forest-400 flex items-center justify-center font-bold text-white-literal uppercase">
                          {user.displayName.charAt(0)}
                        </div>
                        <div>
                          <p className="text-sm font-medium text-white">{user.displayName}</p>
                          <p className="text-xs text-gray-500">{user.email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="p-4">
                      {user.isVerified ? (
                        <span className="px-2 py-1 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-full text-xs font-medium">Verified</span>
                      ) : user.kycStatus === "pending_review" ? (
                        <span className="px-2 py-1 bg-amber-500/10 text-amber-400 border border-amber-500/20 rounded-full text-xs font-medium">Pending Review</span>
                      ) : (
                        <span className="px-2 py-1 bg-white/5 text-gray-400 border border-white/10 rounded-full text-xs font-medium">Pending</span>
                      )}
                    </td>
                    <td className="p-4">
                      <span className="text-sm text-gray-300 capitalize">{user.planTier}</span>
                    </td>
                    <td className="p-4">
                      <span className="text-sm text-gray-400">{user.createdAt}</span>
                    </td>
                    <td className="p-4">
                      <button 
                        onClick={() => setSelectedUser(user)}
                        className="text-forest-400 hover:text-forest-300 text-sm font-medium cursor-pointer"
                      >
                        View Details
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Slide-out details drawer */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs z-50 flex justify-end">
          <div className="w-full max-w-2xl bg-white dark:bg-[#0d100e] h-full shadow-2xl border-l border-gray-200 dark:border-white/10 flex flex-col relative animate-in slide-in-from-right duration-250 overflow-hidden">
            
            {/* Sticky Header Bar */}
            <div className="flex justify-between items-center p-6 border-b border-gray-200 dark:border-white/10 bg-gray-50 dark:bg-[#080a09] shrink-0 z-10">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-linear-to-br from-forest-600 to-forest-400 flex items-center justify-center font-bold text-white-literal text-lg uppercase shadow-lg shadow-forest-500/10">
                  {selectedUser.displayName.charAt(0)}
                </div>
                <div>
                  <h2 className="text-lg font-bold text-gray-900 dark:text-white leading-tight">{selectedUser.displayName}</h2>
                  <p className="text-xs text-gray-500 dark:text-gray-400">{selectedUser.email}</p>
                </div>
              </div>
              <button 
                onClick={() => setSelectedUser(null)}
                className="p-2 rounded-xl bg-gray-100 dark:bg-white/5 hover:bg-gray-200 dark:hover:bg-white/10 text-gray-700 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors cursor-pointer flex items-center gap-1.5 text-xs font-semibold border border-gray-200 dark:border-white/10"
              >
                <X className="w-4 h-4" />
                Close
              </button>
            </div>

            {/* Scrollable Content Container */}
            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              
              {/* UID Info Summary */}
              <div className="flex items-center justify-between text-xs text-gray-500 font-mono bg-gray-50 dark:bg-white/5 px-4 py-2.5 rounded-xl border border-gray-200 dark:border-white/5">
                <span>User Identifier (UID)</span>
                <span>{selectedUser.id}</span>
              </div>

              {/* Account Profile Fields */}
              <div className="grid grid-cols-2 gap-4 bg-gray-50 dark:bg-white/5 p-5 rounded-2xl border border-gray-200 dark:border-white/10">
                <div className="flex items-start gap-3">
                  <Smartphone className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block font-medium">Phone Number</span>
                    <span className="text-sm font-medium text-white">{selectedUser.phoneNumber || "—"}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3">
                  <CreditCard className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block font-medium">Plan Tier</span>
                    <span className="text-sm font-medium text-white capitalize">{selectedUser.planTier}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3 col-span-2">
                  <MapPin className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block font-medium">Residential Address</span>
                    <span className="text-sm font-medium text-white leading-relaxed">{selectedUser.address || "—"}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3 col-span-2">
                  <Calendar className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block font-medium">Member Since</span>
                    <span className="text-sm font-medium text-white">{selectedUser.createdAt}</span>
                  </div>
                </div>
              </div>

              {/* KYC Information Section */}
              <div className="space-y-4">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">KYC & Identity Verification</h3>
                <div className="bg-gray-50 dark:bg-white/5 p-5 rounded-2xl border border-gray-200 dark:border-white/10 space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <span className="text-xs text-gray-400 block">ID Document Number (BVN/NIN)</span>
                      <span className="text-sm font-mono text-white font-medium">{selectedUser.idNumber || "—"}</span>
                    </div>
                    {selectedUser.isVerified ? (
                      <span className="flex items-center gap-1.5 px-3 py-1 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-full text-xs font-semibold">
                        <ShieldCheck className="w-4 h-4" /> Verified
                      </span>
                    ) : (
                      <span className="flex items-center gap-1.5 px-3 py-1 bg-amber-500/10 text-amber-400 border border-amber-500/20 rounded-full text-xs font-semibold">
                        <ShieldAlert className="w-4 h-4" /> {selectedUser.kycStatus === "pending_review" ? "Pending Review" : "Pending Approval"}
                      </span>
                    )}
                  </div>

                  {/* Selfie & ID Document side-by-side comparison */}
                  <div className="grid grid-cols-2 gap-4">
                    {selectedUser.selfieUrl ? (
                      <div className="space-y-2">
                        <span className="text-xs text-gray-500 dark:text-gray-400 block font-medium">Liveness Selfie</span>
                        <div className="relative aspect-square rounded-xl overflow-hidden border border-gray-200 dark:border-white/10 bg-gray-100 dark:bg-black/40 flex items-center justify-center">
                          <img 
                            src={selectedUser.selfieUrl} 
                            alt="KYC Liveness Selfie" 
                            className="max-h-full max-w-full object-contain"
                          />
                        </div>
                      </div>
                    ) : (
                      <div className="p-4 rounded-xl bg-gray-100 dark:bg-black/20 text-center text-xs text-gray-500 border border-dashed border-gray-200 dark:border-white/10 flex items-center justify-center aspect-square">
                        No selfie captured yet.
                      </div>
                    )}

                    {selectedUser.documentUrl ? (
                      <div className="space-y-2">
                        <span className="text-xs text-gray-500 dark:text-gray-400 block font-medium">Government ID Document</span>
                        <div className="relative aspect-square rounded-xl overflow-hidden border border-gray-200 dark:border-white/10 bg-gray-100 dark:bg-black/40 flex items-center justify-center font-mono">
                          <img 
                            src={selectedUser.documentUrl} 
                            alt="Government ID" 
                            className="max-h-full max-w-full object-contain"
                          />
                        </div>
                      </div>
                    ) : (
                      <div className="p-4 rounded-xl bg-gray-100 dark:bg-black/20 text-center text-xs text-gray-500 border border-dashed border-gray-200 dark:border-white/10 flex items-center justify-center aspect-square">
                        No government ID uploaded.
                      </div>
                    )}
                  </div>

                  {!selectedUser.isVerified && (
                    <button 
                      onClick={() => handleApproveKyc(selectedUser.id)}
                      disabled={isPending}
                      className="w-full flex items-center justify-center gap-2 bg-emerald-500 hover:bg-emerald-600 text-white-literal font-bold py-3 px-4 rounded-xl transition-all shadow-lg shadow-emerald-500/10 disabled:opacity-50 cursor-pointer"
                    >
                      {isPending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Check className="w-5 h-5" />}
                      Approve Manual KYC
                    </button>
                  )}
                </div>
              </div>

              {/* Administrative Actions */}
              <div className="space-y-4">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">Administrative Operations</h3>
                <div className="bg-gray-50 dark:bg-white/5 p-5 rounded-2xl border border-gray-200 dark:border-white/10 space-y-5">
                  
                  {/* Account Status / Blocking */}
                  <div className="flex items-center justify-between">
                    <div>
                      <span className="text-sm font-medium text-white block">Account Block Status</span>
                      <span className="text-xs text-gray-400 mt-0.5 block">Suspend this user from all virtual card transaction processing.</span>
                    </div>
                    <button 
                      onClick={() => handleToggleBlock(selectedUser.id, selectedUser.kycStatus || "active")}
                      disabled={isPending}
                      className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition-all disabled:opacity-50 cursor-pointer
                        ${selectedUser.kycStatus === "blocked"
                          ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 hover:bg-emerald-500/20"
                          : "bg-rose-500/10 text-rose-400 border border-rose-500/20 hover:bg-rose-500/20"
                        }`}
                    >
                      {isPending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Ban className="w-4 h-4" />}
                      {selectedUser.kycStatus === "blocked" ? "Unblock Account" : "Block Account"}
                    </button>
                  </div>

                  <hr className="border-gray-200 dark:border-white/5" />

                  {/* Send Direct System / Push Notification */}
                  <form onSubmit={handleSendNotification} className="space-y-3">
                    <span className="text-sm font-medium text-white block">Send Custom Direct Notification</span>
                    <input 
                      type="text"
                      required
                      value={notifTitle}
                      onChange={(e) => setNotifTitle(e.target.value)}
                      placeholder="Notification Title (e.g. Account Ready!)"
                      className="w-full bg-white dark:bg-black/20 border border-gray-200 dark:border-white/10 rounded-xl px-4 py-2.5 text-xs text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:border-forest-500/50"
                    />
                    <textarea 
                      required
                      rows={3}
                      value={notifBody}
                      onChange={(e) => setNotifBody(e.target.value)}
                      placeholder="Compose notification message body..."
                      className="w-full bg-white dark:bg-black/20 border border-gray-200 dark:border-white/10 rounded-xl px-4 py-2.5 text-xs text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:border-forest-500/50 resize-none"
                    />
                    <button 
                      type="submit"
                      disabled={sendingNotif || !notifTitle || !notifBody}
                      className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white-literal text-xs font-bold px-4 py-2 rounded-xl transition-all shadow-md shadow-forest-500/10 disabled:opacity-50 cursor-pointer ml-auto"
                    >
                      {sendingNotif ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
                      Dispatch Notification
                    </button>
                  </form>

                </div>
              </div>

            </div>
          </div>
        </div>
      )}

      {/* Broadcast Message Modal */}
      {showBroadcastModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-xs flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-[#0d100e] w-full max-w-lg rounded-2xl border border-gray-200 dark:border-white/10 overflow-hidden shadow-2xl animate-in fade-in zoom-in-95 duration-150">
            {/* Modal Header */}
            <div className="p-6 border-b border-gray-200 dark:border-white/5 flex items-center justify-between bg-gray-50 dark:bg-white/5">
              <div>
                <h3 className="text-xl font-bold text-white flex items-center gap-2">
                  <Send className="w-5 h-5 text-forest-400" />
                  System-Wide Broadcast
                </h3>
                <p className="text-xs text-gray-400 mt-1">Send a broadcast message to all users on selected channels.</p>
              </div>
              <button 
                onClick={() => setShowBroadcastModal(false)}
                className="w-8 h-8 rounded-lg bg-gray-100 dark:bg-white/5 hover:bg-gray-200 dark:hover:bg-white/10 flex items-center justify-center text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors cursor-pointer"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Modal Body / Form */}
            <form onSubmit={handleSendBroadcast} className="p-6 space-y-6">
              {/* Channel Selector */}
              <div className="space-y-3">
                <span className="text-sm font-medium text-white block">Channels</span>
                <div className="grid grid-cols-2 gap-4">
                  <label className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-white/5 border border-gray-200 dark:border-white/10 cursor-pointer hover:bg-gray-100 dark:hover:bg-white/10 transition-colors">
                    <input 
                      type="checkbox" 
                      checked={broadcastChannels.inApp}
                      onChange={(e) => setBroadcastChannels({ ...broadcastChannels, inApp: e.target.checked })}
                      className="accent-forest-500 w-4 h-4"
                    />
                    <div>
                      <span className="text-xs font-semibold text-gray-900 dark:text-white block">In-App Inbox</span>
                      <span className="text-[10px] text-gray-500 dark:text-gray-400">Render in notifications center</span>
                    </div>
                  </label>

                  <label className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-white/5 border border-gray-200 dark:border-white/10 cursor-pointer hover:bg-gray-100 dark:hover:bg-white/10 transition-colors">
                    <input 
                      type="checkbox" 
                      checked={broadcastChannels.push}
                      onChange={(e) => setBroadcastChannels({ ...broadcastChannels, push: e.target.checked })}
                      className="accent-forest-500 w-4 h-4"
                    />
                    <div>
                      <span className="text-xs font-semibold text-gray-900 dark:text-white block">FCM Push</span>
                      <span className="text-[10px] text-gray-500 dark:text-gray-400">Deliver push notification</span>
                    </div>
                  </label>

                  <label className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-white/5 border border-gray-200 dark:border-white/10 cursor-pointer hover:bg-gray-100 dark:hover:bg-white/10 transition-colors">
                    <input 
                      type="checkbox" 
                      checked={broadcastChannels.email}
                      onChange={(e) => setBroadcastChannels({ ...broadcastChannels, email: e.target.checked })}
                      className="accent-forest-500 w-4 h-4"
                    />
                    <div>
                      <span className="text-xs font-semibold text-gray-900 dark:text-white block">Email Address</span>
                      <span className="text-[10px] text-gray-500 dark:text-gray-400">Send transactional email</span>
                    </div>
                  </label>

                  <label className="flex items-center gap-3 p-3 rounded-xl bg-gray-50 dark:bg-white/5 border border-gray-200 dark:border-white/10 cursor-pointer hover:bg-gray-100 dark:hover:bg-white/10 transition-colors">
                    <input 
                      type="checkbox" 
                      checked={broadcastChannels.whatsapp}
                      onChange={(e) => setBroadcastChannels({ ...broadcastChannels, whatsapp: e.target.checked })}
                      className="accent-forest-500 w-4 h-4"
                    />
                    <div>
                      <span className="text-xs font-semibold text-gray-900 dark:text-white block">WhatsApp</span>
                      <span className="text-[10px] text-gray-500 dark:text-gray-400">Tabi.Africa template message</span>
                    </div>
                  </label>
                </div>
              </div>

              {/* Title & Message inputs */}
              <div className="space-y-4">
                <div className="space-y-2">
                  <label className="text-sm font-medium text-gray-900 dark:text-white block">Message Title</label>
                  <input 
                    type="text"
                    required
                    value={broadcastTitle}
                    onChange={(e) => setBroadcastTitle(e.target.value)}
                    placeholder="Broadcast Subject (e.g. System Maintenance Update)"
                    className="w-full bg-white dark:bg-white/5 border border-gray-200 dark:border-white/10 rounded-xl px-4 py-2.5 text-sm text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-gray-50 dark:focus:bg-white/10 transition-all"
                  />
                </div>

                <div className="space-y-2">
                  <label className="text-sm font-medium text-gray-900 dark:text-white block">Message Content</label>
                  <textarea 
                    required
                    rows={5}
                    value={broadcastBody}
                    onChange={(e) => setBroadcastBody(e.target.value)}
                    placeholder="Compose your broadcast message here..."
                    className="w-full bg-white dark:bg-white/5 border border-gray-200 dark:border-white/10 rounded-xl px-4 py-2.5 text-sm text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-gray-50 dark:focus:bg-white/10 transition-all resize-none"
                  />
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex justify-end gap-3 pt-4 border-t border-gray-200 dark:border-white/5">
                <button 
                  type="button"
                  onClick={() => setShowBroadcastModal(false)}
                  className="px-4 py-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-colors cursor-pointer"
                >
                  Cancel
                </button>
                <button 
                  type="submit"
                  disabled={sendingBroadcast || !broadcastTitle || !broadcastBody}
                  className="flex items-center gap-2 bg-forest-600 hover:bg-forest-700 text-white-literal text-sm font-semibold px-5 py-2 rounded-xl transition-all shadow-md shadow-forest-600/10 disabled:opacity-50 cursor-pointer"
                >
                  {sendingBroadcast ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      Broadcasting...
                    </>
                  ) : (
                    <>
                      <Send className="w-4 h-4" />
                      Dispatch Broadcast
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
