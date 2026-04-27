import { db } from "@/lib/firebaseAdmin";
import UsersClient from "./UsersClient";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const usersSnapshot = await db.collection("users").orderBy("createdAt", "desc").limit(25).get();
  const users = usersSnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      displayName: data.displayName || data.firstName || "Unknown User",
      email: data.email || "",
      isVerified: data.isVerified || false,
      planTier: data.planTier || "Instant",
      createdAt: data.createdAt ? new Date(data.createdAt).toLocaleDateString() : "Unknown",
    };
  });

  return <UsersClient initialUsers={users} />;
}
