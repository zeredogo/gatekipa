const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAuth, requireFields } = require("../utils/validators");


exports.createAccount = onCall({ region: "us-central1" }, async (request) => {

  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { name, type } = request.data;

  requireFields(request.data, ["name", "type"]);

  const accountRef = db.collection("accounts").doc();
  const now = Date.now();

  const account = {
    id: accountRef.id,
    owner_user_id: uid,
    name: name.trim(),
    type: type,
    created_at: now
  };

  await accountRef.set(account);

  const userDoc = await db.collection("users").doc(uid).get();
  const userName = userDoc.exists ? userDoc.data().displayName || userDoc.data().firstName || "Owner" : "Owner";

  // Auto-add owner as admin in team_members as explicitly demanded by architecture
  const tmRef = db.collection("team_members").doc(`${accountRef.id}_${uid}`);
  await tmRef.set({
    id: tmRef.id,
    account_id: accountRef.id,
    user_id: uid,
    user_name: userName,
    role: "owner",
    invited_at: now
  });

  return { success: true, accountId: accountRef.id, account };
});

exports.inviteTeamMember = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { account_id, target_user_id, role, spend_limit } = request.data;

  requireFields(request.data, ["account_id", "target_user_id", "role"]);

  if (role === 'owner') {
    throw new HttpsError("invalid-argument", "Cannot invite a member as the account owner.");
  }

  // Need to ensure the inviter owns the account or is an admin
  const accSnap = await db.collection("accounts").doc(account_id).get();
  if (!accSnap.exists) throw new HttpsError("not-found", "Account not found");
  
  // Verify Business Tier
  const ownerDoc = await db.collection("users").doc(accSnap.data().owner_user_id).get();
  if (!ownerDoc.exists || ownerDoc.data().planTier !== "business") {
    throw new HttpsError("permission-denied", "Team access requires the Business Plan upgrade.");
  }
  
  if (accSnap.data().owner_user_id !== uid) {
    const myTmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
    if (!myTmSnap.exists || myTmSnap.data().role !== "admin") {
      throw new HttpsError("permission-denied", "Only owner and admins can invite.");
    }
  }

  let finalUserId = target_user_id;
  let targetEmail = null;
  let targetName = null;

  // Resolve email to user ID if necessary
  if (finalUserId.includes("@")) {
    const { admin } = require("../utils/firebase");
    try {
      const userRecord = await admin.auth().getUserByEmail(finalUserId);
      finalUserId = userRecord.uid;
      targetEmail = userRecord.email;
      targetName = userRecord.displayName;
    } catch (error) {
      // User not found in Firebase Auth, allow pending invite
      targetEmail = finalUserId.trim().toLowerCase();
      targetName = 'Pending Invite';
      finalUserId = targetEmail;
    }
  }

  // Fetch the target user's document to get their most up-to-date name
  if (!finalUserId.includes("@")) {
    const targetUserDoc = await db.collection("users").doc(finalUserId).get();
    if (targetUserDoc.exists) {
      const data = targetUserDoc.data();
      targetEmail = targetEmail || data.email;
      targetName = data.displayName || data.firstName ? `${data.firstName || ''} ${data.lastName || ''}`.trim() : null;
    }
  }

  const tmId = `${account_id}_${finalUserId}`;
  const tmRef = db.collection("team_members").doc(tmId);
  await tmRef.set({
    id: tmRef.id,
    account_id,
    user_id: finalUserId,
    user_email: targetEmail || finalUserId,
    user_name: targetName || 'Team Member',
    role: role,
    spend_limit: spend_limit ? Number(spend_limit) : null,
    invited_at: Date.now()
  });

  return { success: true };
});

exports.removeTeamMember = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { account_id, target_user_id } = request.data;
  
  requireFields(request.data, ["account_id", "target_user_id"]);

  // Only the account owner or admins can remove team members.
  // We'll trust the owner. Alternatively, the user can remove themselves.
  const accSnap = await db.collection("accounts").doc(account_id).get();
  if (!accSnap.exists) throw new HttpsError("not-found", "Account not found");
  
  if (accSnap.data().owner_user_id !== uid && target_user_id !== uid) {
    // If not the owner and not removing self, check if the active user is an admin
    const myTmSnap = await db.collection("team_members").doc(`${account_id}_${uid}`).get();
    if (!myTmSnap.exists || myTmSnap.data().role !== "admin") {
      throw new HttpsError("permission-denied", "You don't have permission to remove members.");
    }
    
    // An admin cannot remove the owner
    if (target_user_id === accSnap.data().owner_user_id) {
      throw new HttpsError("permission-denied", "Admins cannot remove the account owner.");
    }
  }

  const tmId = `${account_id}_${target_user_id}`;
  await db.collection("team_members").doc(tmId).delete();

  return { success: true };
});

exports.renameAccount = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { account_id, new_name } = request.data;
  
  requireFields(request.data, ["account_id", "new_name"]);

  const accSnap = await db.collection("accounts").doc(account_id).get();
  if (!accSnap.exists) throw new HttpsError("not-found", "Account not found");
  if (accSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Only owner can rename.");
  }

  await db.collection("accounts").doc(account_id).update({
    name: new_name.trim()
  });

  return { success: true };
});

exports.deleteAccount = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { account_id, confirm_delete } = request.data;
  requireFields(request.data, ["account_id"]);

  const accSnap = await db.collection("accounts").doc(account_id).get();
  if (!accSnap.exists) throw new HttpsError("not-found", "Account not found");
  if (accSnap.data().owner_user_id !== uid) {
    throw new HttpsError("permission-denied", "Only the account owner can delete this account.");
  }

  // Guardrail: Check for active cards before allowing deletion
  const activeCardsSnap = await db.collection("cards")
    .where("account_id", "==", account_id)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (!activeCardsSnap.empty && !confirm_delete) {
    throw new HttpsError(
      "failed-precondition",
      "This account has active virtual cards. Please block all cards before deleting the account, or pass confirm_delete: true to force-delete."
    );
  }

  // To avoid exceeding Firestore's 500 operations per batch limit,
  // we push all the refs to be deleted into an array and chunk them.
  const refsToDelete = [];

  // 1. Collect all cards and their associated rules
  const cardsSnap = await db.collection("cards").where("account_id", "==", account_id).get();
  for (const cardDoc of cardsSnap.docs) {
    const rulesSnap = await db.collection("rules").where("card_id", "==", cardDoc.id).get();
    rulesSnap.docs.forEach(ruleDoc => refsToDelete.push(ruleDoc.ref));
    refsToDelete.push(cardDoc.ref);
  }

  // 2. Collect all team members
  const tmSnap = await db.collection("team_members").where("account_id", "==", account_id).get();
  tmSnap.docs.forEach(tmDoc => refsToDelete.push(tmDoc.ref));

  // 3. Collect account ref
  refsToDelete.push(accSnap.ref);

  // Chunk and commit
  for (let i = 0; i < refsToDelete.length; i += 500) {
    const batch = db.batch();
    const chunk = refsToDelete.slice(i, i + 500);
    chunk.forEach(ref => batch.delete(ref));
    await batch.commit();
  }

  return { success: true };
});

exports.switchActiveAccount = onCall({ region: "us-central1" }, async (request) => {
  requireAuth(request.auth);
  const uid = request.auth.uid;
  const { account_id } = request.data;
  requireFields(request.data, ["account_id"]);

  // We are assuming the user must be a member or owner of the account
  const tmSnap = await db.collection("team_members")
    .where("account_id", "==", account_id)
    .where("user_id", "==", uid)
    .limit(1).get();

  const accSnap = await db.collection("accounts").doc(account_id).get();

  if (!accSnap.exists) throw new HttpsError("not-found", "Account not found");
  
  if (accSnap.data().owner_user_id !== uid && tmSnap.empty) {
    throw new HttpsError("permission-denied", "Not a member of this account.");
  }

  // Update their context in users collection
  await db.collection("users").doc(uid).set({
    active_account_id: account_id
  }, { merge: true });

  return { success: true };
});
