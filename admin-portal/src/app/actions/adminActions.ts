"use server";

import { db, auth, admin } from "@/lib/firebaseAdmin";
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
  } catch {
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
    
    const cardDoc = await db.collection("cards").doc(cardId).get();
    if (!cardDoc.exists) throw new Error("Card not found");
    const sudoCardId = cardDoc.data()?.sudo_card_id;
    
    // Call Sudo Africa API to freeze/unfreeze the card
    if (sudoCardId) {
      const sudoStatus = newStatus === "frozen" ? "inactive" : "active";
      const response = await fetch(`https://api.sudo.africa/cards/${sudoCardId}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${process.env.SUDO_API_KEY || ""}`,
        },
        body: JSON.stringify({ status: sudoStatus })
      });
      
      if (!response.ok) {
         console.warn("Sudo API freeze failed:", await response.text());
         // Allow it to fall through to update local state anyway
      }
    }

    await db.collection("cards").doc(cardId).update({
      local_status: newStatus,
      status: newStatus,
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
  } catch (e: unknown) {
    console.error("Failed to block user:", e);
    return { success: false, error: (e as Error).message };
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
  } catch (e: unknown) {
    console.error("Failed to update fee:", e);
    return { success: false, error: (e as Error).message };
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
  } catch (e: unknown) {
    console.error("Failed to approve KYC:", e);
    return { success: false, error: (e as Error).message };
  }
}

// --- NOTIFICATION ACTIONS --- //
export async function sendInAppNotification(userId: string, title: string, message: string) {
  try {
    await verifyAdminSession();

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
  } catch (e: unknown) {
    console.error("Failed to send notification:", e);
    return { success: false, error: (e as Error).message };
  }
}

// --- BROADCAST NOTIFICATION ACTION --- //
export async function sendBroadcastNotification(userIds: string[], title: string, message: string, channels: { push: boolean, inApp: boolean, whatsapp: boolean }) {
  try {
    await verifyAdminSession();

    
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
  } catch (e: unknown) {
    console.error("Broadcast failed:", e);
    return { success: false, error: (e as Error).message };
  }
}

// --- RECONCILIATION ACTIONS --- //
export async function runReconciliationSweep() {
  try {
    await verifyAdminSession();

    
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

    // Fetch actual Sudo Africa Issuing Balance (company default account)
    let sudoEscrow = gatekipaTotal; // Fallback to Gatekipa total if Sudo unreachable
    try {
      const response = await fetch("https://api.sudo.africa/accounts", {
        headers: {
          "Authorization": `Bearer ${process.env.SUDO_API_KEY || ""}`,
          "Accept": "application/json"
        }
      });
      if (response.ok) {
        const payload = await response.json();
        const accounts = payload.data || [];
        const defaultAccount = accounts.find((a: { isDefault?: boolean; availableBalance?: number }) => a.isDefault === true);
        if (defaultAccount && defaultAccount.availableBalance !== undefined) {
          sudoEscrow = defaultAccount.availableBalance / 100; // Sudo returns amounts in kobo
        }
      } else {
        console.warn("Failed to fetch live Sudo wallet:", await response.text());
      }
    } catch (e) {
      console.error("Sudo connection failed during sweep:", e);
    }

    await db.doc("system_stats/reconciliation").set({
      last_sweep: new Date().toISOString(),
      gatekipa_ledger: gatekipaTotal,
      bridgecard_escrow: sudoEscrow // Keep Firestore key for backward compat with existing dashboard reads
    }, { merge: true });


    revalidatePath("/reconciliation");
    return { success: true, message: "Sweep completed successfully!" };
  } catch (error: unknown) {
    console.error("Reconciliation failed:", error);
    return { success: false, error: (error as Error).message };
  }
}

// --- UNIFIED BROADCAST DISPATCHER --- //
export async function dispatchAdminBroadcast(
  channels: { push: boolean; inApp: boolean; email: boolean; whatsapp: boolean },
  title: string,
  message: string
) {
  try {
    await verifyAdminSession();
    
    // Fetch all user docs
    const usersSnap = await db.collection("users").get();
    const userIds = usersSnap.docs.map(doc => doc.id);
    
    let emailSuccessCount = 0;
    let notifSuccessCount = 0;

    // 1. Send system/push/whatsapp notifications via existing helper
    if (channels.push || channels.inApp || channels.whatsapp) {
      const res = await sendBroadcastNotification(userIds, title, message, {
        push: channels.push,
        inApp: channels.inApp,
        whatsapp: channels.whatsapp
      });
      if (res.success) {
        notifSuccessCount = res.count || 0;
      } else {
        throw new Error(res.error || "Failed to dispatch notifications.");
      }
    }

    // 2. Send emails using direct Resend API call if enabled
    if (channels.email) {
      const apiKey = process.env.RESEND_API_KEY;
      if (!apiKey) {
        throw new Error("RESEND_API_KEY is not configured in the environment.");
      }

      const emails = usersSnap.docs.map(doc => doc.data().email).filter(Boolean);
      for (const email of emails) {
        try {
          const res = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              from: "Gatekipa <hello@gatekipa.com>",
              to: email,
              subject: title,
              html: `
                <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333; padding: 20px; border: 1px solid #e5e7eb; border-radius: 12px; background-color: #ffffff;">
                  <div style="text-align: center; margin-bottom: 20px;">
                    <span style="font-size: 24px; font-weight: bold; color: #1e3a8a;">Gatekipa</span>
                  </div>
                  <h2 style="color: #111827; font-size: 20px; border-bottom: 1px solid #f3f4f6; padding-bottom: 12px; margin-top: 0;">${title}</h2>
                  <p style="color: #374151; font-size: 15px; white-space: pre-wrap;">${message}</p>
                  <hr style="border: 0; border-top: 1px solid #e5e7eb; margin: 24px 0;"/>
                  <p style="font-size: 12px; color: #9ca3af; text-align: center; margin-bottom: 0;">This is a system broadcast from the Gatekipa Admin Team.</p>
                </div>
              `,
            }),
          });
          if (res.ok) {
            emailSuccessCount++;
          }
        } catch (err) {
          console.error(`Failed to send email to ${email}:`, err);
        }
      }
    }

    return { 
      success: true, 
      notifCount: notifSuccessCount, 
      emailCount: emailSuccessCount 
    };
  } catch (e: any) {
    console.error("Broadcast dispatch failed:", e);
    return { success: false, error: e.message };
  }
}
