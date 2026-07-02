"use client";

import React, { useState, useTransition } from "react";
import { 
  Users, Search, Filter, X, Check, Ban, Send, 
  Smartphone, MapPin, CreditCard, Calendar, ShieldCheck, ShieldAlert, Loader2 
} from "lucide-react";
import { approveKyc, toggleUserBlockStatus, sendInAppNotification } from "@/app/actions/adminActions";

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
  
  const [isPending, startTransition] = useTransition();

  const filteredUsers = initialUsers.filter(u => 
    u.displayName?.toLowerCase().includes(searchTerm.toLowerCase()) || 
    u.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
    u.id?.toLowerCase().includes(searchTerm.toLowerCase())
  );

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

  return (
    <div className="space-y-8">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-white tracking-tight">Users & KYC</h1>
          <p className="text-gray-400 mt-1">Manage platform users, verify identities, and review account statuses.</p>
        </div>
        <div className="flex gap-3">
          <button className="flex items-center gap-2 bg-white/5 hover:bg-white/10 text-white px-4 py-2 rounded-xl transition-colors border border-white/10 cursor-pointer">
            <Filter className="w-4 h-4" />
            Filter
          </button>
          <button className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white px-4 py-2 rounded-xl transition-colors font-medium cursor-pointer">
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
                        <div className="w-10 h-10 rounded-full bg-linear-to-br from-forest-500 to-indigo-500 flex items-center justify-center font-bold text-white uppercase">
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
          <div className="w-full max-w-2xl bg-[#0f172a] h-full shadow-2xl p-8 overflow-y-auto border-l border-white/10 flex flex-col relative animate-in slide-in-from-right duration-250">
            <button 
              onClick={() => setSelectedUser(null)}
              className="absolute top-6 right-6 p-2 rounded-xl bg-white/5 hover:bg-white/10 text-gray-400 hover:text-white transition-colors cursor-pointer"
            >
              <X className="w-5 h-5" />
            </button>

            {/* Profile Overview */}
            <div className="flex items-center gap-4 mb-8">
              <div className="w-16 h-16 rounded-2xl bg-linear-to-br from-forest-500 to-indigo-500 flex items-center justify-center font-bold text-white text-2xl uppercase shadow-lg shadow-forest-500/10">
                {selectedUser.displayName.charAt(0)}
              </div>
              <div>
                <h2 className="text-2xl font-bold text-white">{selectedUser.displayName}</h2>
                <p className="text-sm text-gray-400">{selectedUser.email}</p>
                <p className="text-xs text-gray-500 font-mono mt-1">UID: {selectedUser.id}</p>
              </div>
            </div>

            <div className="space-y-8 flex-1">
              {/* Account Profile Fields */}
              <div className="grid grid-cols-2 gap-4 bg-white/5 p-5 rounded-2xl border border-white/10">
                <div className="flex items-start gap-3">
                  <Smartphone className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block">Phone Number</span>
                    <span className="text-sm font-medium text-white">{selectedUser.phoneNumber || "—"}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3">
                  <CreditCard className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block">Plan Tier</span>
                    <span className="text-sm font-medium text-white capitalize">{selectedUser.planTier}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3 col-span-2">
                  <MapPin className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block">Residential Address</span>
                    <span className="text-sm font-medium text-white leading-relaxed">{selectedUser.address || "—"}</span>
                  </div>
                </div>

                <div className="flex items-start gap-3 col-span-2">
                  <Calendar className="w-5 h-5 text-gray-500 shrink-0 mt-0.5" />
                  <div>
                    <span className="text-xs text-gray-400 block">Member Since</span>
                    <span className="text-sm font-medium text-white">{selectedUser.createdAt}</span>
                  </div>
                </div>
              </div>

              {/* KYC Information Section */}
              <div className="space-y-4">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-400">KYC & Identity Verification</h3>
                <div className="bg-white/5 p-5 rounded-2xl border border-white/10 space-y-4">
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
                        <span className="text-xs text-gray-400 block font-medium">Liveness Selfie</span>
                        <div className="relative aspect-square rounded-xl overflow-hidden border border-white/10 bg-black/40 flex items-center justify-center">
                          <img 
                            src={selectedUser.selfieUrl} 
                            alt="KYC Liveness Selfie" 
                            className="max-h-full max-w-full object-contain"
                          />
                        </div>
                      </div>
                    ) : (
                      <div className="p-4 rounded-xl bg-black/20 text-center text-xs text-gray-500 border border-dashed border-white/10 flex items-center justify-center aspect-square">
                        No selfie captured yet.
                      </div>
                    )}

                    {selectedUser.documentUrl ? (
                      <div className="space-y-2">
                        <span className="text-xs text-gray-400 block font-medium">Government ID Document</span>
                        <div className="relative aspect-square rounded-xl overflow-hidden border border-white/10 bg-black/40 flex items-center justify-center font-mono">
                          <img 
                            src={selectedUser.documentUrl} 
                            alt="Government ID" 
                            className="max-h-full max-w-full object-contain"
                          />
                        </div>
                      </div>
                    ) : (
                      <div className="p-4 rounded-xl bg-black/20 text-center text-xs text-gray-500 border border-dashed border-white/10 flex items-center justify-center aspect-square">
                        No government ID uploaded.
                      </div>
                    )}
                  </div>

                  {!selectedUser.isVerified && (
                    <button 
                      onClick={() => handleApproveKyc(selectedUser.id)}
                      disabled={isPending}
                      className="w-full flex items-center justify-center gap-2 bg-emerald-500 hover:bg-emerald-600 text-white font-bold py-3 px-4 rounded-xl transition-all shadow-lg shadow-emerald-500/10 disabled:opacity-50 cursor-pointer"
                    >
                      {isPending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Check className="w-5 h-5" />}
                      Approve Manual KYC
                    </button>
                  )}
                </div>
              </div>

              {/* Administrative Actions */}
              <div className="space-y-4">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-400">Administrative Operations</h3>
                <div className="bg-white/5 p-5 rounded-2xl border border-white/10 space-y-5">
                  
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

                  <hr className="border-white/5" />

                  {/* Send Direct System / Push Notification */}
                  <form onSubmit={handleSendNotification} className="space-y-3">
                    <span className="text-sm font-medium text-white block">Send Custom Direct Notification</span>
                    <input 
                      type="text"
                      required
                      value={notifTitle}
                      onChange={(e) => setNotifTitle(e.target.value)}
                      placeholder="Notification Title (e.g. Account Ready!)"
                      className="w-full bg-black/20 border border-white/10 rounded-xl px-4 py-2.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-forest-500/50"
                    />
                    <textarea 
                      required
                      rows={3}
                      value={notifBody}
                      onChange={(e) => setNotifBody(e.target.value)}
                      placeholder="Compose notification message body..."
                      className="w-full bg-black/20 border border-white/10 rounded-xl px-4 py-2.5 text-xs text-white placeholder-gray-600 focus:outline-none focus:border-forest-500/50 resize-none"
                    />
                    <button 
                      type="submit"
                      disabled={sendingNotif || !notifTitle || !notifBody}
                      className="flex items-center gap-2 bg-forest-500 hover:bg-forest-600 text-white text-xs font-bold px-4 py-2 rounded-xl transition-all shadow-md shadow-forest-500/10 disabled:opacity-50 cursor-pointer ml-auto"
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
    </div>
  );
}
