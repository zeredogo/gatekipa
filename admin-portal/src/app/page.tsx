import { getDashboardStats, getRecentTransactions } from "./actions";
import DashboardClient from "./DashboardClient";

export const dynamic = 'force-dynamic';

export default async function AdminDashboard() {
  const stats = await getDashboardStats();
  const transactions = await getRecentTransactions();

  return (
    <DashboardClient 
      initialIsLockdown={stats.isLockdown} 
      stats={stats} 
      transactions={transactions} 
    />
  );
}
