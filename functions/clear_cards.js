const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

process.env.GOOGLE_APPLICATION_CREDENTIALS = "gatekipa.json";

try {
  initializeApp();
} catch (e) {
  // Ignore error if already initialized by application default credentials
  console.log("Using default credentials");
}

const db = getFirestore();

async function clearCards() {
  try {
    const snap = await db.collection("cards").get();
    console.log("Found " + snap.docs.length + " cards to delete.");
    
    // Using batch for efficiency
    let batch = db.batch();
    let count = 0;
    
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      count++;
      
      // Also delete any rules associated with this card
      const rulesSnap = await db.collection("rules").where("card_id", "==", doc.id).get();
      for (const ruleDoc of rulesSnap.docs) {
         batch.delete(ruleDoc.ref);
         count++;
      }
      
      if (count >= 400) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }
    
    if (count > 0) {
      await batch.commit();
    }
    
    console.log("Successfully cleared all cards and their rules from Firestore.");
  } catch (e) {
    console.error("Error clearing cards:", e);
  }
}

clearCards();
