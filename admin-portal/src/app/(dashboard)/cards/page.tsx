import { db } from "@/lib/firebaseAdmin";
import CardsClient from "./CardsClient";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
  const cardsSnapshot = await db.collection("cards").orderBy("created_at", "desc").limit(100).get();
  
  const cards = cardsSnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name || data.cardName || "Virtual Card",
      last4: data.last4 ? data.last4 : "PEND",
      ownerId: data.created_by || data.userId || "Unknown",
      status: data.local_status || data.status || "frozen",
      balance: data.allocated_amount || data.balance || 0,
      createdAt: data.created_at ? new Date(data.created_at.toDate ? data.created_at.toDate() : data.created_at).toLocaleDateString() : "Unknown"
    };
  });

  return <CardsClient initialCards={cards} />;
}
