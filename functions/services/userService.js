// functions/services/userService.js
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail } = require("../utils/validators");
const { getAuth } = require("firebase-admin/auth");
const { defineSecret } = require("firebase-functions/params");


/**
 * deleteUserAccount — permanently deletes the calling user's entire profile.
 *
 * Cascade order:
 *  1. All rules for all cards on all owned accounts
 *  2. All cards on all owned accounts
 *  3. All team_member records for all owned accounts
 *  4. All owned account documents
 *  5. Wallet balance sub-document
 *  6. User document (/users/{uid})
 *  7. Firebase Auth user record
 *
 * The caller must send { confirm: true } to prevent accidental deletions.
 */
exports.deleteUserAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    requireVerifiedEmail(request.auth);
    const uid = request.auth.uid;

    if (request.data?.confirm !== true) {
      throw new HttpsError(
        "invalid-argument",
        "You must send { confirm: true } to delete your account."
      );
    }

    const refsToDelete = [];
    const amlSnapshot = {
      uid: uid,
      deleted_at: Date.now(),
      user_profile: null,
      wallet_balance: 0,
      accounts: [],
      cards: [],
      team_members: [],
    };

    // 1. Fetch User Record
    const userDoc = await db.collection("users").doc(uid).get();
    if (userDoc.exists) {
       amlSnapshot.user_profile = userDoc.data();
    }

    // 2. Fetch Wallet
    const walletRef = db.collection("users").doc(uid).collection("wallet").doc("balance");
    const walletDoc = await walletRef.get();
    if (walletDoc.exists) {
       amlSnapshot.wallet_balance = walletDoc.data().balance || 0;
    }
    refsToDelete.push(walletRef);

    // 3. Find all accounts owned by this user
    const accountsSnap = await db
      .collection("accounts")
      .where("owner_user_id", "==", uid)
      .get();

    for (const accDoc of accountsSnap.docs) {
      const accountId = accDoc.id;

      // 3a. Rules for each card
      const cardsSnap = await db
        .collection("cards")
        .where("account_id", "==", accountId)
        .get();

      for (const cardDoc of cardsSnap.docs) {
        amlSnapshot.cards.push({ id: cardDoc.id, ...cardDoc.data() });
        const rulesSnap = await db
          .collection("rules")
          .where("card_id", "==", cardDoc.id)
          .get();
        rulesSnap.docs.forEach((ruleDoc) => refsToDelete.push(ruleDoc.ref));
        refsToDelete.push(cardDoc.ref);
      }

      // 3b. Team members
      const tmSnap = await db
        .collection("team_members")
        .where("account_id", "==", accountId)
        .get();
      tmSnap.docs.forEach((tmDoc) => {
         amlSnapshot.team_members.push({ id: tmDoc.id, ...tmDoc.data() });
         refsToDelete.push(tmDoc.ref);
      });

      // 3c. Account doc itself
      amlSnapshot.accounts.push({ id: accDoc.id, ...accDoc.data() });
      refsToDelete.push(accDoc.ref);
    }

    // 4. User doc
    refsToDelete.push(db.collection("users").doc(uid));

    // 5. SECURE COMPLIANCE BACKUP to AML Archive
    // Retains KYC, history layout, and identity vectors strictly before destructive cascade.
    await db.collection("aml_backups").doc(uid).set(amlSnapshot);

    // 6. Batch-delete all Firestore documents (max 500 per batch)
    for (let i = 0; i < refsToDelete.length; i += 500) {
      const batch = db.batch();
      refsToDelete.slice(i, i + 500).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }

    // 5. Delete the Firebase Auth user record last
    await getAuth().deleteUser(uid);

    return { success: true };
  }
);



/**
 * setTransactionPin — Cryptographically hashes and sets the user's Transaction PIN.
 * This ensures the raw PIN is never stored on the backend, only a salted hash.
 */
exports.setTransactionPin = onCall(
  { region: "us-central1" },
  async (request) => {
    requireVerifiedEmail(request.auth);
    const uid = request.auth.uid;
    const { pin, oldPin } = request.data;

    if (!pin || pin.length < 4) {
      throw new HttpsError("invalid-argument", "PIN must be at least 4 characters.");
    }

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    const security = userDoc.data()?.security || {};

    const crypto = require("crypto");

    // If changing an existing PIN, require the old one (prevent session hijacking)
    if (security.pinHash) {
      if (!oldPin) {
        throw new HttpsError("permission-denied", "You must provide your current PIN to change it.");
      }
      const [oldSalt, oldStoredHash] = security.pinHash.split(":");
      const hashAttempt = crypto.scryptSync(oldPin, oldSalt, 64).toString("hex");
      if (hashAttempt !== oldStoredHash) {
        throw new HttpsError("permission-denied", "Current PIN is incorrect.");
      }
    }

    // Generate new salted hash
    const newSalt = crypto.randomBytes(16).toString("hex");
    const newHash = crypto.scryptSync(pin, newSalt, 64).toString("hex");

    await userRef.update({
      "security.pinHash": `${newSalt}:${newHash}`,
      "security.pinUpdatedAt": Date.now(),
    });

    return { success: true };
  }
);
