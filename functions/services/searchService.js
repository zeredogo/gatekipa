const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");

exports.searchEntities = onCall({ region: "us-central1", enforceAppCheck: true }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { query } = request.data;

  requireFields(request.data, ["query"]);

  if (!query || query.trim().length === 0) {
    return { accounts: [], cards: [] };
  }

  const q = query.trim().toLowerCase();

  // 1. Fetch accounts this user OWNS
  const ownedSnap = await db.collection("accounts").where("owner_user_id", "==", uid).get();

  // 2. Fetch accounts this user is a MEMBER of
  const tmSnap = await db.collection("team_members").where("user_id", "==", uid).get();
  const memberAccountIds = tmSnap.docs.map(d => d.data().account_id).filter(Boolean);

  // 3. Build a unified map of all accessible accounts (by doc ID)
  const accountsById = {};
  ownedSnap.docs.forEach(doc => {
    accountsById[doc.id] = { id: doc.id, ...doc.data() };
  });

  // Fetch member accounts in chunks of 10
  const uniqueMemberIds = [...new Set(memberAccountIds)].filter(id => !accountsById[id]);
  for (let i = 0; i < uniqueMemberIds.length; i += 10) {
    const chunk = uniqueMemberIds.slice(i, i + 10);
    // Fetch accounts one by one or by Promise.all
    const refs = chunk.map(id => db.collection("accounts").doc(id));
    const docs = await Promise.all(refs.map(r => r.get()));
    docs.forEach(doc => {
      if (doc.exists) {
        accountsById[doc.id] = { id: doc.id, ...doc.data() };
      }
    });
  }

  const allValidAccountIds = Object.keys(accountsById);

  if (allValidAccountIds.length === 0) {
    return { accounts: [], cards: [] };
  }

  // 4. Filter accounts matching query
  const matchingAccounts = Object.values(accountsById).filter(acc =>
    acc.name && acc.name.toLowerCase().includes(q)
  );

  // 5. Fetch cards for all accessible accounts (chunked by 10)
  const matchingCards = [];
  for (let i = 0; i < allValidAccountIds.length; i += 10) {
    const chunk = allValidAccountIds.slice(i, i + 10);
    const cardSnap = await db.collection("cards").where("account_id", "in", chunk).get();
    cardSnap.docs.forEach(doc => {
      const data = { id: doc.id, ...doc.data() };
      if (data.name && data.name.toLowerCase().includes(q)) {
        const acc = accountsById[data.account_id];
        matchingCards.push({
          ...data,
          _account_name: acc ? acc.name : "Unknown Account",
        });
      }
    });
  }

  return {
    accounts: matchingAccounts,
    cards: matchingCards,
  };
});
