"use client";

import React, { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { 
  Users, 
  CreditCard, 
  Activity, 
  Search,
  Bell,
  Menu,
  Wallet,
  ShieldCheck,
  AlertTriangle,
  Power,
  HeartPulse,
  Cpu,
  Webhook,
  LogOut,
  Settings
} from "lucide-react";
import { motion } from "framer-motion";
import { removeSession } from "@/app/actions/auth";

export default function DashboardLayoutClient({
  children,
  adminEmail,
}: {
  children: React.ReactNode;
  adminEmail: string;
}) {
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const pathname = usePathname();

  const handleLogout = async () => {
    await removeSession();
    window.location.href = "/login";
  };

  const navigation = [
    { name: "Overview", href: "/", icon: Activity },
    { name: "Users", href: "/users", icon: Users },
    { name: "Cards", href: "/cards", icon: CreditCard },
    { name: "Transactions", href: "/transactions", icon: Wallet },
    { name: "Reconciliation", href: "/reconciliation", icon: Search },
    { name: "Compliance", href: "/compliance", icon: ShieldCheck },
    { name: "Fraud", href: "/fraud", icon: AlertTriangle },
    { name: "Global Freeze", href: "/freeze", icon: Power },
    { name: "Health", href: "/health", icon: HeartPulse },
    { name: "Rules", href: "/rules", icon: Cpu },
    { name: "Webhooks", href: "/webhooks", icon: Webhook },
  ];

  return (
    <div className="min-h-screen flex bg-background overflow-hidden selection:bg-primary/30">
      {/* Sidebar */}
      <motion.aside 
        initial={{ width: 280 }}
        animate={{ width: sidebarOpen ? 280 : 80 }}
        className="h-screen glass-panel border-r border-white/5 flex flex-col relative z-20 transition-all duration-300 ease-in-out"
      >
        <div className="p-6 flex items-center justify-between shrink-0">
          {sidebarOpen ? (
            <Link href="/" className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-forest-500 flex items-center justify-center">
                <ShieldCheck className="w-5 h-5 text-white" />
              </div>
              <span className="font-bold text-lg tracking-wide text-white">Gatekipa</span>
            </Link>
          ) : (
            <Link href="/" className="w-full flex justify-center">
              <div className="w-8 h-8 rounded-lg bg-forest-500 flex items-center justify-center">
                <ShieldCheck className="w-5 h-5 text-white" />
              </div>
            </Link>
          )}
        </div>

        <nav className="flex-1 px-4 py-6 space-y-1 overflow-y-auto scrollbar-hide">
          {navigation.map((item) => {
            const isActive = pathname === item.href || (item.href !== "/" && pathname?.startsWith(item.href));
            
            // Special styling for Global Freeze
            const isFreeze = item.name === "Global Freeze";
            const activeColor = isFreeze ? "text-rose-400 bg-rose-500/10 border-rose-500/20" : "bg-forest-500/10 text-forest-400 border-forest-500/20";
            const hoverColor = isFreeze ? "hover:bg-rose-500/5 group-hover:text-rose-400" : "hover:bg-white/5 group-hover:text-white";

            return (
              <Link 
                key={item.name}
                href={item.href}
                className={`w-full flex items-center gap-4 px-4 py-2.5 rounded-xl transition-all duration-200 group border border-transparent
                  ${isActive ? activeColor : `text-gray-400 ${hoverColor}`}
                `}
              >
                <item.icon className={`w-5 h-5 shrink-0 ${isActive ? (isFreeze ? 'text-rose-400' : 'text-forest-400') : `text-gray-400 ${isFreeze ? 'group-hover:text-rose-400' : 'group-hover:text-white'} transition-colors`}`} />
                {sidebarOpen && <span className="font-medium whitespace-nowrap text-sm">{item.name}</span>}
              </Link>
            );
          })}
        </nav>

        <div className="p-4 border-t border-white/5 shrink-0">
          <button onClick={handleLogout} className="w-full flex items-center gap-4 px-4 py-3 rounded-xl text-gray-400 hover:bg-rose-500/10 hover:text-rose-400 transition-all duration-200 group">
            <LogOut className="w-5 h-5 shrink-0 group-hover:text-rose-400 transition-colors" />
            {sidebarOpen && <span className="font-medium text-sm">Logout</span>}
          </button>
        </div>
      </motion.aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col h-screen overflow-hidden relative">
        {/* Topbar */}
        <header className="h-20 glass-panel border-b border-white/5 flex items-center justify-between px-8 z-10 shrink-0">
          <div className="flex items-center gap-6">
            <button 
              onClick={() => setSidebarOpen(!sidebarOpen)}
              className="p-2 rounded-lg hover:bg-white/5 text-gray-400 hover:text-white transition-colors"
            >
              <Menu className="w-5 h-5" />
            </button>
            <div className="relative group hidden md:block">
              <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 group-focus-within:text-forest-400 transition-colors" />
              <input 
                type="text" 
                placeholder="Search across platform..." 
                className="w-96 bg-white/5 border border-white/10 rounded-full pl-10 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-forest-500/50 focus:bg-white/10 transition-all"
              />
            </div>
          </div>
          
          <div className="flex items-center gap-4">
            <button className="relative p-2 rounded-full hover:bg-white/5 text-gray-400 hover:text-white transition-colors">
              <Bell className="w-5 h-5" />
              <span className="absolute top-1 right-1 w-2 h-2 bg-rose-500 rounded-full"></span>
            </button>
            <div className="h-8 w-px bg-white/10 mx-2"></div>
            <div className="flex items-center gap-3 cursor-pointer hover:bg-white/5 py-1 px-2 rounded-lg transition-colors">
              <div className="text-right hidden md:block">
                <p className="text-sm font-semibold text-white">{adminEmail}</p>
                <p className="text-xs text-gray-400">Super Administrator</p>
              </div>
              <div className="w-10 h-10 rounded-full bg-linear-to-tr from-forest-500 to-purple-500 border-2 border-white/10 flex items-center justify-center font-bold text-white uppercase">{adminEmail.charAt(0)}</div>
            </div>
          </div>
        </header>

        {/* Dynamic Page Content */}
        <div className="flex-1 overflow-auto relative z-0">
          {/* Ambient Background Glows */}
          <div className="absolute top-0 left-1/4 w-96 h-96 bg-forest-500/10 rounded-full blur-[120px] pointer-events-none"></div>
          <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-purple-500/10 rounded-full blur-[120px] pointer-events-none"></div>

          <div className="p-8 relative z-10 max-w-7xl mx-auto min-h-full">
            {children}
          </div>
        </div>
      </main>
    </div>
  );
}
