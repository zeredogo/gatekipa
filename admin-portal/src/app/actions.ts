'use server';

import { getAdminDb } from '@/lib/firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import { revalidatePath } from 'next/cache';

export async function getDashboardStats() {
  const db = getAdminDb();
  
  // Fetch all stats concurrently to avoid network waterfalls
  const [globalRef, statsRef, cardsSnap, webhooksSnap] = await Promise.all([
    db.doc('system_state/global').get(),
    db.doc('system_stats/summary').get(),
    db.collection('cards').count().get(),
    db.collection('webhook_events').count().get()
  ]);

  const isLockdown = globalRef.exists ? globalRef.data()?.mode === 'LOCKDOWN' : false;
  const totalBalance = statsRef.exists ? (statsRef.data()?.total_balance ?? 0) : 0;
  const cardsCount = cardsSnap.data().count;
  const webhooksCount = webhooksSnap.data().count;

  return {
    isLockdown,
    totalBalance,
    activeCards: cardsCount,
    webhookEvents: webhooksCount
  };
}

export async function getRecentTransactions() {
  const db = getAdminDb();
  
  // We can fetch recent webhook events
  const snapshot = await db.collection('webhook_events')
    .orderBy('received_at', 'desc')
    .limit(10)
    .get();

  return snapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id.slice(0, 10) + '...',
      type: data.event || 'Unknown',
      status: data.status || 'Pending',
      time: data.received_at ? new Date(data.received_at.toMillis()).toLocaleString() : 'N/A'
    };
  });
}

export async function toggleLockdown(currentState: boolean) {
  const db = getAdminDb();
  const newMode = currentState ? 'NORMAL' : 'LOCKDOWN';
  
  await db.doc('system_state/global').set({ mode: newMode }, { merge: true });
  
  revalidatePath('/');
  return newMode === 'LOCKDOWN';
}

export async function rejectWithdrawal(withdrawalId: string, reason: string) {
  const db = getAdminDb();
  const withdrawalRef = db.collection('withdrawal_requests').doc(withdrawalId);
  
  try {
    await db.runTransaction(async (t) => {
      const doc = await t.get(withdrawalRef);
      if (!doc.exists) throw new Error("Withdrawal request not found");
      
      const data = doc.data()!;
      if (data.status !== "PENDING_ADMIN_APPROVAL") {
        throw new Error(`Cannot reject withdrawal in status: ${data.status}`);
      }
      
      const uid = data.user_id;
      const amount = data.amount;
      
      const walletRef = db.doc(`users/${uid}/wallet/balance`);
      const ledgerRef = db.collection("wallet_ledger").doc();
      
      const walletDoc = await t.get(walletRef);
      const currentBalance = walletDoc.exists ? (walletDoc.data()?.cached_balance ?? walletDoc.data()?.balance ?? 0) : 0;
      
      // 1. Refund Wallet
      t.set(walletRef, { 
        cached_balance: FieldValue.increment(amount),
        balance: FieldValue.increment(amount)
      }, { merge: true });
      
      // 2. Ledger Refund Entry
      t.set(ledgerRef, {
        user_id: uid,
        type: "credit",
        amount,
        reference: withdrawalId,
        balance_after: currentBalance + amount,
        source: "withdrawal_rejected_refund",
        created_at: FieldValue.serverTimestamp(),
      });
      
      // 3. Mark Rejected
      t.update(withdrawalRef, {
        status: "REJECTED",
        reject_reason: reason,
        updated_at: FieldValue.serverTimestamp()
      });
    });
    
    // We would ideally dispatch FCM here using admin.messaging()
    revalidatePath('/escrow');
    revalidatePath('/');
    return { success: true };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}

export async function approveWithdrawal(withdrawalId: string) {
  const db = getAdminDb();
  const withdrawalRef = db.collection('withdrawal_requests').doc(withdrawalId);
  
  try {
    let data: any = null;
    await db.runTransaction(async (t) => {
      const doc = await t.get(withdrawalRef);
      if (!doc.exists) throw new Error("Withdrawal request not found");
      
      data = doc.data()!;
      if (data.status !== "PENDING_ADMIN_APPROVAL") {
        throw new Error(`Cannot approve withdrawal in status: ${data.status}`);
      }
      
      // Atomically lock the withdrawal request to prevent double-spending
      t.update(withdrawalRef, {
        status: "PROCESSING_APPROVAL",
        updated_at: FieldValue.serverTimestamp()
      });
    });
    
    const { amount, bank_code, account_number, account_name, user_id } = data;
    const secretKey = process.env.PAYSTACK_SECRET_KEY;
    
    if (!secretKey) {
      throw new Error("PAYSTACK_SECRET_KEY is not configured on the admin portal.");
    }

    // 1. Create Transfer Recipient
    const recipientRes = await fetch("https://api.paystack.co/transferrecipient", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${secretKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        type: "nuban",
        name: account_name,
        account_number: account_number,
        bank_code: bank_code,
        currency: "NGN"
      })
    });
    
    const recipientData = await recipientRes.json();
    if (!recipientData.status) {
      throw new Error(`Failed to create recipient: ${recipientData.message}`);
    }
    const recipientCode = recipientData.data.recipient_code;
    
    // 2. Initiate Transfer
    // Note: Paystack amounts are in kobo. amount * 100
    const transferRes = await fetch("https://api.paystack.co/transfer", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${secretKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        source: "balance",
        amount: Math.round(amount * 100),
        recipient: recipientCode,
        reason: "Gatekeeper Withdrawal",
        reference: `withdraw_${withdrawalId}_${Date.now()}`
      })
    });
    
    const transferData = await transferRes.json();
    if (!transferData.status) {
      // Revert status on API failure
      await withdrawalRef.update({
        status: "PENDING_ADMIN_APPROVAL",
        updated_at: FieldValue.serverTimestamp()
      });
      throw new Error(`Transfer failed: ${transferData.message}`);
    }
    
    // 3. Mark Approved
    await withdrawalRef.update({
      status: "APPROVED",
      paystack_transfer_code: transferData.data.transfer_code,
      paystack_reference: transferData.data.reference,
      updated_at: FieldValue.serverTimestamp()
    });
    
    revalidatePath('/escrow');
    revalidatePath('/');
    return { success: true };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}
