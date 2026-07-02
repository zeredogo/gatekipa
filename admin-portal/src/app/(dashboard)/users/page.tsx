import { db } from "@/lib/firebaseAdmin";
import UsersClient from "./UsersClient";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const usersSnapshot = await db.collection("users").orderBy("created_at", "desc").limit(25).get();
  const users = usersSnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      displayName: data.displayName || `${data.firstName || ''} ${data.lastName || ''}`.trim() || "Unknown User",
      email: data.email || "",
      isVerified: data.kycStatus === "verified" || data.isVerified || false,
      planTier: data.planTier || "Instant",
      createdAt: data.created_at ? new Date(data.created_at.toDate ? data.created_at.toDate() : data.created_at).toLocaleDateString() : "Unknown",
      phoneNumber: data.phoneNumber || "",
      address: `${data.houseNumber || ''} ${data.address || ''}, ${data.city || ''}, ${data.state || ''} ${data.postalCode || ''}`.trim().replace(/^,|,$/g, '').trim(),
      kycStatus: data.kycStatus || "pending",
      selfieUrl: data.kycMeta?.selfie || "",
      documentUrl: data.kycMeta?.documentUrl || "",
      idNumber: data.kycMeta?.idNumber || "",
      spendingLock: data.spending_lock || false,
      nightLockdown: data.nightLockdown || false,
      geoFence: data.geoFence || false,
      fcmToken: data.fcm_token || "",
    };
  });

  return <UsersClient initialUsers={users} />;
}
