import React from "react";
import { db } from "@/lib/firebaseAdmin";
import FraudClient from "./FraudClient";

export const dynamic = "force-dynamic";

export default async function FraudPage() {
  // 1. Fetch recent transactions
  const txnsSnap = await db.collection("transactions")
    .orderBy("created_at", "desc")
    .limit(100)
    .get();

  const rawTxns = txnsSnap.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      user_id: data.user_id || "",
      card_id: data.card_id || data.metadata?.cardId || "",
      amount: data.amount || 0,
      status: data.status || "PENDING",
      merchant_name: data.merchant_name || data.metadata?.merchantName || "Unknown Merchant",
      decline_reason: data.decline_reason || null,
      risk_score: data.risk_score !== undefined ? data.risk_score : (data.metadata?.risk_score ?? null),
      risk_reasons: data.risk_reasons || data.metadata?.risk_reasons || [],
      created_at: data.created_at ? (data.created_at.toDate ? data.created_at.toDate().toISOString() : new Date(data.created_at).toISOString()) : new Date().toISOString(),
    };
  });

  // 2. Fetch users to map name/email/status
  const userIds = Array.from(new Set(rawTxns.map(t => t.user_id).filter(Boolean)));
  const userMap: Record<string, { email: string; name: string; status: string }> = {};

  if (userIds.length > 0) {
    const chunks = [];
    for (let i = 0; i < userIds.length; i += 30) {
      chunks.push(userIds.slice(i, i + 30));
    }

    await Promise.all(
      chunks.map(async (chunk) => {
        const usersSnap = await db.collection("users").where("__name__", "in", chunk).get();
        usersSnap.docs.forEach(doc => {
          const u = doc.data();
          userMap[doc.id] = {
            email: u.email || "",
            name: `${u.firstName || ""} ${u.lastName || ""}`.trim() || u.email || "Unknown User",
            status: u.status || "active",
          };
        });
      })
    );
  }

  // 3. Map card local_status
  const cardIds = Array.from(new Set(rawTxns.map(t => t.card_id).filter(Boolean)));
  const cardMap: Record<string, { status: string }> = {};

  if (cardIds.length > 0) {
    const cardChunks = [];
    for (let i = 0; i < cardIds.length; i += 30) {
      cardChunks.push(cardIds.slice(i, i + 30));
    }

    await Promise.all(
      cardChunks.map(async (chunk) => {
        const cardsSnap = await db.collection("cards").where("__name__", "in", chunk).get();
        cardsSnap.docs.forEach(doc => {
          const c = doc.data();
          cardMap[doc.id] = {
            status: c.local_status || c.status || "active"
          };
        });
      })
    );
  }

  // Combine data
  const transactions = rawTxns.map(t => ({
    ...t,
    user_email: userMap[t.user_id]?.email || "",
    user_name: userMap[t.user_id]?.name || "Unknown User",
    user_status: userMap[t.user_id]?.status || "active",
    local_status: cardMap[t.card_id]?.status || "active"
  }));

  return <FraudClient initialTransactions={transactions} />;
}
