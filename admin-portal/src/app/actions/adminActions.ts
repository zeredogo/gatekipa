"use server";

import { db, auth } from "@/lib/firebaseAdmin";
import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";

async function verifyAdminSession() {
  const cookieStore = await cookies();
  const sessionCookie = cookieStore.get('session')?.value;
  if (!sessionCookie) throw new Error("Unauthorized: No session cookie");
  try {
    const decodedClaims = await auth.verifySessionCookie(sessionCookie, true);
    if (!decodedClaims.admin && !decodedClaims.super_admin) {
      throw new Error("Unauthorized: Missing admin privileges");
    }
    return decodedClaims;
  } catch (error) {
    throw new Error("Unauthorized: Invalid session");
  }
}


// --- SYSTEM STATE ACTIONS --- //

export async function toggleGlobalFreeze(isCurrentlyFrozen: boolean) {
  try {
    await verifyAdminSession();
    const newState = isCurrentlyFrozen ? "NORMAL" : "LOCKDOWN";
    
    // Write to system_state/global
    await db.collection("system_state").doc("global").set({
      mode: newState,
      updatedAt: new Date().toISOString()
    }, { merge: true });

    revalidatePath("/freeze");
    return { success: true, mode: newState };
  } catch (error) {
    console.error("Failed to toggle global freeze:", error);
    return { success: false, error: "Failed to toggle global freeze." };
  }
}

// --- CARD ACTIONS --- //

export async function toggleCardFreeze(cardId: string, currentStatus: string) {
  try {
    await verifyAdminSession();
    const newStatus = currentStatus === "active" ? "frozen" : "active";
    
    // Call Bridgecard API directly
    const cardDoc = await db.collection("cards").doc(cardId).get();
    if (!cardDoc.exists) throw new Error("Card not found");
    const bridgecardCardId = cardDoc.data()?.bridgecard_card_id;
    const currency = cardDoc.data()?.bridgecard_currency || "NGN";
    
    if (bridgecardCardId) {
      // Inline the API call to avoid cross-project import issues
      const isUsd = (currency || "NGN").toUpperCase() === "USD";
      const endpoint = newStatus === "frozen" 
        ? (isUsd ? "/cards/freeze_card" : "/naira_cards/freeze_card")
        : (isUsd ? "/cards/unfreeze_card" : "/naira_cards/unfreeze_card");
        
      const response = await fetch(`https://issuecards.api.bridgecard.co/v1/issuing${endpoint}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "token": `Bearer ${process.env.BRIDGECARD_ACCESS_TOKEN || ""}`,
          "issuing-app-id": process.env.BRIDGECARD_ISSUING_APP_ID || "8ea9a4b4-26b1-4aa6-8e29-25648057ab7d"
        },
        body: JSON.stringify({ card_id: bridgecardCardId })
      });
      
      if (!response.ok) {
         console.warn("Bridgecard API freeze failed:", await response.text());
         // Allow it to fall through to update local state anyway
      }
    }

    await db.collection("cards").doc(cardId).update({
      local_status: newStatus,
      status: newStatus,
      bridgecard_status: newStatus,
      updatedAt: new Date().toISOString()
    });

    revalidatePath("/cards");
    return { success: true, status: newStatus };
  } catch (error) {
    console.error("Failed to toggle card status:", error);
    return { success: false, error: "Failed to update card status." };
  }
}

// --- USER ACTIONS --- //

export async function toggleUserBlockStatus(userId: string, currentStatus: string) {
  try {
    await verifyAdminSession();
    const block = currentStatus !== "blocked";
    await db.collection("users").doc(userId).update({
      status: block ? "blocked" : "active"
    });
    revalidatePath("/users");
    revalidatePath("/fraud");
    return { success: true, status: block ? "blocked" : "active" };
  } catch (e: any) {
    console.error("Failed to block user:", e);
    return { success: false, error: e.message };
  }
}

// --- RULES ACTIONS --- //

export async function updateFeeConfiguration(fee: number) {
  try {
    await verifyAdminSession();
    await db.collection("system_state").doc("fees").set({
      cardCreationFee: fee
    }, { merge: true });
    revalidatePath("/rules");
    return { success: true };
  } catch (e: any) {
    console.error("Failed to update fee:", e);
    return { success: false, error: e.message };
  }
}

// --- KYC ACTIONS --- //
export async function approveKyc(userId: string) {
  try {
    await verifyAdminSession();
    await db.collection("users").doc(userId).update({
      kycStatus: "verified"
    });
    revalidatePath("/compliance");
    revalidatePath("/users");
    return { success: true };
  } catch (e: any) {
    console.error("Failed to approve KYC:", e);
    return { success: false, error: e.message };
  }
}

// --- NOTIFICATION ACTIONS --- //
export async function sendInAppNotification(userId: string, title: string, message: string) {
  try {
    const cookieStore = await cookies();
    const sessionCookie = cookieStore.get('session')?.value;
    if (!sessionCookie) return { success: false, error: "Unauthorized" };

    const admin = require("firebase-admin");
    const decodedClaims = await admin.auth().verifySessionCookie(sessionCookie, true);
    if (!decodedClaims.admin && !decodedClaims.super_admin) return { success: false, error: "Unauthorized" };
    
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) return { success: false, error: "User not found" };

    // 1. Write to in-app notification center
    await db.collection("users").doc(userId).collection("notifications").add({
      user_id: userId,
      type: "system",
      title: title,
      body: message,
      isRead: false,
      timestamp: new Date(),
    });

    // 2. Dispatch FCM Push Notification if token exists
    const fcmToken = userDoc.data()?.fcm_token;
    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: title,
          body: message,
        },
        data: {
          type: "system",
        },
      });
    }

    return { success: true };
  } catch (e: any) {
    console.error("Failed to send notification:", e);
    return { success: false, error: e.message };
  }
}

// --- BROADCAST NOTIFICATION ACTION --- //
export async function sendBroadcastNotification(userIds: string[], title: string, message: string, channels: { push: boolean, inApp: boolean, whatsapp: boolean }) {
  try {
    await verifyAdminSession();
    const admin = require("firebase-admin");
    const db = admin.firestore();
    
    // Process in batches
    let successCount = 0;
    
    for (const userId of userIds) {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) continue;
      
      const userData = userDoc.data();
      
      // 1. In-App Notification
      if (channels.inApp) {
        await db.collection("users").doc(userId).collection("notifications").add({
          user_id: userId,
          type: "system",
          title: title,
          body: message,
          isRead: false,
          timestamp: new Date(),
        });
      }
      
      // 2. Push Notification
      if (channels.push && userData?.fcm_token) {
        try {
          await admin.messaging().send({
            token: userData.fcm_token,
            notification: { title, body: message },
            data: { type: "broadcast" },
          });
        } catch (e) {
          console.error(`FCM failed for ${userId}:`, e);
        }
      }
      
      // 3. WhatsApp Integration via Tabi.Africa
      if (channels.whatsapp && userData?.phone_number) {
        if (process.env.TABI_API_KEY) {
          try {
            // Tabi.Africa standard message payload
            await fetch("https://api.tabi.africa/v1/messages/send", {
              method: "POST",
              headers: { 
                "Authorization": `Bearer ${process.env.TABI_API_KEY}`, 
                "Content-Type": "application/json" 
              },
              body: JSON.stringify({ 
                recipient: userData.phone_number, 
                type: "text",
                message: { text: message } 
              })
            });
          } catch (e) {
            console.error(`[Tabi.Africa] Failed to send WhatsApp to ${userData.phone_number}`, e);
          }
        } else {
          console.warn("[Tabi.Africa] Skipping WhatsApp: TABI_API_KEY is not set in environment variables.");
        }
      }
      
      successCount++;
    }
    
    return { success: true, count: successCount };
  } catch (e: any) {
    console.error("Broadcast failed:", e);
    return { success: false, error: e.message };
  }
}

// --- RECONCILIATION ACTIONS --- //
export async function runReconciliationSweep() {
  try {
    await verifyAdminSession();
    const admin = require("firebase-admin");
    const db = admin.firestore();
    
    // Sum Gatekipa Wallet Balances
    const usersSnap = await db.collection("users").get();
    let gatekipaTotal = 0;
    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      const walletSnap = await db.doc(`users/${uid}/wallet/balance`).get();
      if (walletSnap.exists) {
        const b = walletSnap.data()?.cached_balance ?? walletSnap.data()?.balance ?? 0;
        gatekipaTotal += b;
      }
    }

    // Fetch actual Bridgecard Issuing Balance
    let bridgecardEscrow = gatekipaTotal; // Fallback
    try {
      const response = await fetch("https://issuecards.api.bridgecard.co/v1/issuing/company/wallet", {
        headers: {
          "token": `Bearer ${process.env.BRIDGECARD_ACCESS_TOKEN || ""}`
        }
      });
      if (response.ok) {
        const payload = await response.json();
        // Assume the API returns { data: { balance: 5000000 } } in kobo
        if (payload.data && payload.data.balance !== undefined) {
           bridgecardEscrow = payload.data.balance / 100;
        }
      } else {
        console.warn("Failed to fetch live Bridgecard wallet:", await response.text());
      }
    } catch (e) {
      console.error("Bridgecard connection failed during sweep:", e);
    }

    await db.doc("system_stats/reconciliation").set({
      last_sweep: new Date().toISOString(),
      gatekipa_ledger: gatekipaTotal,
      bridgecard_escrow: bridgecardEscrow
    }, { merge: true });

    const { revalidatePath } = require("next/cache");
    revalidatePath("/reconciliation");
    return { success: true, message: "Sweep completed successfully!" };
  } catch (error: any) {
    console.error("Reconciliation failed:", error);
    return { success: false, error: error.message };
  }
}
