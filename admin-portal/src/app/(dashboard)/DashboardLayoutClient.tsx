"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { 
  Users, 
  CreditCard, 
  Activity, 
  Search,
  Menu,
  Wallet,
  ShieldCheck,
  AlertTriangle,
  Power,
  HeartPulse,
  Cpu,
  Webhook,
  LogOut,
  Flag,
  Sun,
  Moon
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
  const [theme, setTheme] = useState<"light" | "dark">("dark");

  useEffect(() => {
    const savedTheme = localStorage.getItem("theme") as "light" | "dark" | null;
    const initialTheme = savedTheme || "dark";
    setTheme(initialTheme);
    document.documentElement.setAttribute("data-theme", initialTheme);
    document.documentElement.classList.toggle("dark", initialTheme === "dark");
  }, []);

  const toggleTheme = () => {
    const newTheme = theme === "light" ? "dark" : "light";
    setTheme(newTheme);
    localStorage.setItem("theme", newTheme);
    document.documentElement.setAttribute("data-theme", newTheme);
    document.documentElement.classList.toggle("dark", newTheme === "dark");
  };

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
    { name: "Disputes", href: "/disputes", icon: Flag },
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
              <div className="w-8 h-8 rounded-lg overflow-hidden bg-forest-600 border border-white/10 flex items-center justify-center shrink-0">
                <img src="/logo.png" alt="Gatekipa Logo" className="w-full h-full object-cover" />
              </div>
              <span className="font-bold text-lg tracking-wide text-white">Gatekipa</span>
            </Link>
          ) : (
            <Link href="/" className="w-full flex justify-center">
              <div className="w-8 h-8 rounded-lg overflow-hidden bg-forest-600 border border-white/10 flex items-center justify-center">
                <img src="/logo.png" alt="Gatekipa Logo" className="w-full h-full object-cover" />
              </div>
            </Link>
          )}
        </div>

        <nav className="flex-1 px-4 py-6 space-y-1 overflow-y-auto scrollbar-hide">
          {navigation.map((item) => {
            const isActive = pathname === item.href || (item.href !== "/" && pathname?.startsWith(item.href));
            
            // Special styling for Global Freeze
            const isFreeze = item.name === "Global Freeze";
            const activeColor = isFreeze ? "text-rose-400 bg-rose-500/10 border-rose-500/20" : "bg-forest-500/10 text-stat-forest border-forest-500/20";
            const hoverColor = isFreeze ? "hover:bg-rose-500/5 group-hover:text-rose-400" : "hover:bg-white/5 group-hover:text-white";

            return (
              <Link 
                key={item.name}
                href={item.href}
                className={`w-full flex items-center gap-4 px-4 py-2.5 rounded-xl transition-all duration-200 group border border-transparent
                  ${isActive ? activeColor : `text-gray-400 ${hoverColor}`}
                `}
              >
                <item.icon className={`w-5 h-5 shrink-0 ${isActive ? (isFreeze ? 'text-rose-400' : 'text-stat-forest') : `text-gray-400 ${isFreeze ? 'group-hover:text-rose-400' : 'group-hover:text-white'} transition-colors`}`} />
                {sidebarOpen && <span className="font-medium whitespace-nowrap text-sm">{item.name}</span>}
              </Link>
            );
          })}
        </nav>

        {/* Profile info above Logout button */}
        <div className="px-3 py-2 border-t border-white/5 shrink-0">
          <div className="flex items-center gap-3 px-3 py-2 rounded-xl bg-white/5 border border-white/5">
            <div className="w-8 h-8 rounded-full bg-linear-to-tr from-forest-600 to-forest-400 border border-white/10 flex items-center justify-center font-bold text-white uppercase text-xs shrink-0">
              {adminEmail.charAt(0)}
            </div>
            {sidebarOpen && (
              <div className="text-left overflow-hidden">
                <p className="text-xs font-semibold text-white truncate" title={adminEmail}>
                  {adminEmail}
                </p>
                <p className="text-[10px] text-gray-400 font-medium">Super Administrator</p>
              </div>
            )}
          </div>
        </div>

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
            <button 
              onClick={toggleTheme}
              className="p-2 rounded-xl bg-white/5 hover:bg-forest-500/10 text-gray-400 hover:text-forest-500 transition-colors border border-white/10 dark:border-white/10 cursor-pointer flex items-center justify-center"
              title={theme === "light" ? "Switch to Dark Mode" : "Switch to Light Mode"}
            >
              {theme === "light" ? (
                <Moon className="w-5 h-5" />
              ) : (
                <Sun className="w-5 h-5" />
              )}
            </button>
          </div>
        </header>

        {/* Dynamic Page Content */}
        <div className="flex-1 overflow-auto relative">
          {/* Ambient Background Glows */}
          <div className="absolute top-0 left-1/4 w-96 h-96 bg-forest-500/10 rounded-full blur-[120px] pointer-events-none"></div>
          <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-forest-600/5 rounded-full blur-[120px] pointer-events-none"></div>

          <div className="p-8 relative z-10 max-w-7xl mx-auto min-h-full">
            {children}
          </div>
        </div>
      </main>
    </div>
  );
}
