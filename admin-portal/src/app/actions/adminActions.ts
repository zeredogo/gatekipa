"use server";

import { db, auth } from "@/lib/firebaseAdmin";
import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";

// --- SYSTEM STATE ACTIONS --- //

export async function toggleGlobalFreeze(isCurrentlyFrozen: boolean) {
  try {
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
    const newStatus = currentStatus === "active" ? "frozen" : "active";
    
    // In a real scenario, this should also hit the Bridgecard API to actually freeze the card.
    // We will update the Firestore state which the mobile app listens to.
    await db.collection("cards").doc(cardId).update({
      local_status: newStatus,
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
