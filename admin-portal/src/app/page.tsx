import { getDashboardStats, getRecentTransactions } from "./actions";
import DashboardClient from "./DashboardClient";

export const dynamic = 'force-dynamic';

export default async function AdminDashboard() {
  const [stats, transactions] = await Promise.all([
    getDashboardStats(),
    getRecentTransactions()
  ]);

  return (
    <DashboardClient 
      initialIsLockdown={stats.isLockdown} 
      stats={stats} 
      transactions={transactions} 
    />
  );
}
