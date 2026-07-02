import { db, admin } from "@/lib/firebaseAdmin";
import UsersClient from "./UsersClient";

export const dynamic = "force-dynamic";

async function getSecureStorageUrl(publicUrl: string): Promise<string> {
  if (!publicUrl) return "";
  if (!publicUrl.includes("firebasestorage.googleapis.com")) return publicUrl;
  
  try {
    const urlObj = new URL(publicUrl);
    const pathParts = urlObj.pathname.split("/o/");
    if (pathParts.length < 2) return publicUrl;
    
    const bucketName = pathParts[0].split("/b/")[1];
    const filePath = decodeURIComponent(pathParts[1]);
    
    // Fallback to default bucket if bucketName is not parsed
    const bucket = admin.storage().bucket(bucketName || "gatekipa-bbd1c.firebasestorage.app");
    const file = bucket.file(filePath);
    
    const [signedUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 15 * 60 * 1000, // 15 mins
    });
    return signedUrl;
  } catch (err) {
    console.error("Error generating secure signed URL:", err);
    return publicUrl;
  }
}

export default async function UsersPage() {
  const usersSnapshot = await db.collection("users").orderBy("created_at", "desc").limit(25).get();
  
  const users = await Promise.all(usersSnapshot.docs.map(async (doc) => {
    const data = doc.data();
    
    // Secure the liveness selfie and document URLs dynamically on load
    const selfieUrl = await getSecureStorageUrl(data.kycMeta?.selfie || "");
    const documentUrl = await getSecureStorageUrl(data.kycMeta?.documentUrl || "");

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
      selfieUrl,
      documentUrl,
      idNumber: data.kycMeta?.idNumber || "",
      spendingLock: data.spending_lock || false,
      nightLockdown: data.nightLockdown || false,
      geoFence: data.geoFence || false,
      fcmToken: data.fcm_token || "",
    };
  }));

  return <UsersClient initialUsers={users} />;
}
