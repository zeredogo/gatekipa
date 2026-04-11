const { db } = require("./utils/firebase");

async function migrate() {
  const tmSnap = await db.collection("team_members").get();
  for (const doc of tmSnap.docs) {
    const data = doc.data();
    const newId = `${data.account_id}_${data.user_id}`;
    if (doc.id !== newId) {
      console.log(`Migrating ${doc.id} -> ${newId}`);
      await db.collection("team_members").doc(newId).set({
        ...data,
        id: newId
      });
      await doc.ref.delete();
    }
  }
  console.log("Migration complete.");
}

migrate().catch(console.error);
