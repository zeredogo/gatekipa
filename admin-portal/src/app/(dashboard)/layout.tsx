import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { auth } from "@/lib/firebaseAdmin";
import DashboardLayoutClient from "./DashboardLayoutClient";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = await cookies();
  const session = cookieStore.get("session")?.value;

  if (!session) {
    redirect("/login");
  }

  try {
    const decodedClaims = await auth.verifySessionCookie(session, true);
    
    // Strict RBAC Enforcement: Only users with the 'admin' or 'super_admin' custom claim can access the portal.
    // If you are testing locally and haven't set claims, you can bypass this by commenting it out,
    // but this ensures zero-trust security in production.
    if (process.env.NODE_ENV === "production" && !decodedClaims.admin && !decodedClaims.super_admin) {
      console.warn(`Unauthorized access attempt by ${decodedClaims.email}. Missing admin claims.`);
      redirect("/login?error=unauthorized");
    }
    
    const adminEmail = decodedClaims.email || "Admin User";

    return (
      <DashboardLayoutClient adminEmail={adminEmail}>
        {children}
      </DashboardLayoutClient>
    );
  } catch (error) {
    console.error("RBAC verification failed:", error);
    redirect("/login");
  }
}
