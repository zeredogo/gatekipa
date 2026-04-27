import { db } from "@/lib/firebaseAdmin";
import CardsClient from "./CardsClient";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
  const cardsSnapshot = await db.collection("cards").orderBy("createdAt", "desc").limit(25).get();
  
  const cards = cardsSnapshot.docs.map(doc => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.cardName || "Virtual Card",
      last4: data.last4 || "****",
      ownerId: data.userId || "Unknown",
      status: data.local_status || "frozen",
      balance: data.balance || 0,
      createdAt: data.createdAt ? new Date(data.createdAt).toLocaleDateString() : "Unknown"
    };
  });

  return <CardsClient initialCards={cards} />;
}
