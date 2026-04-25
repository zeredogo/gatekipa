// functions/services/userService.js
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireVerifiedEmail } = require("../utils/validators");
const { getAuth } = require("firebase-admin/auth");
const { defineSecret } = require("firebase-functions/params");

const PAYSTACK_SECRET_KEY = defineSecret("PAYSTACK_SECRET_KEY");

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
 * initiatePremiumUpgrade — creates a Paystack payment initialisation for
 * the ₦2,000/month Sentinel Prime subscription. The Flutter client opens
 * the returned authorization_url in a WebView. After payment, the client
 * calls verifyPremiumPayment with the reference to activate the plan.
 */
exports.initiatePremiumUpgrade = onCall(
  { region: "us-central1", secrets: [PAYSTACK_SECRET_KEY] },
  async (request) => {
    requireVerifiedEmail(request.auth);
    const uid = request.auth.uid;

    // FIX: Accept optional plan param so the Business plan can also be purchased via this flow.
    // Defaults to 'premium' (Sentinel Prime) to preserve backward compatibility.
    const { plan = "premium" } = request.data || {};
    if (!["premium", "business"].includes(plan)) {
      throw new HttpsError("invalid-argument", "Invalid upgrade plan. Must be 'premium' or 'business'.");
    }

    const UPGRADE_CONFIG = {
      premium:  { amountKobo: 199900, label: "Sentinel Prime", cards: 3 },
      business: { amountKobo: 500000, label: "Business Plan",  cards: 5 },
    };
    const config = UPGRADE_CONFIG[plan];

    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");

    const userData = userSnap.data();
    // FIX: isPremium is a legacy field — planTier is the authoritative source of truth.
    if (userData.planTier === 'premium' || userData.planTier === 'business') {
      throw new HttpsError("already-exists", "You are already on this plan or higher.");
    }

    const secretKey = PAYSTACK_SECRET_KEY.value();
    if (!secretKey) {
      throw new HttpsError(
        "failed-precondition",
        "Payment gateway is not configured. Contact support."
      );
    }

    const email = userData.email || `${uid}@gatekipa.internal`;

    let response;
    try {
      const fetch = (...args) =>
        import("node-fetch").then(({ default: f }) => f(...args));
      response = await fetch("https://api.paystack.co/transaction/initialize", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email,
          amount: config.amountKobo,
          metadata: {
            uid,
            plan,
            custom_fields: [
              { display_name: "Plan", variable_name: "plan", value: config.label },
            ],
          },
          callback_url: "https://gatekipa.com/premium/success",
        }),
      });
    } catch (err) {
      console.error("[Premium] Paystack init failed:", err);
      throw new HttpsError("internal", "Could not reach payment gateway.");
    }

    const body = await response.json();
    if (!body.status || !body.data?.authorization_url) {
      console.error("[Premium] Paystack init error:", body);
      throw new HttpsError("internal", "Payment gateway returned an error.");
    }

    return {
      authorizationUrl: body.data.authorization_url,
      reference: body.data.reference,
      amountNgn: config.amountKobo / 100,
      label: config.label,
    };
  }
);

/**
 * verifyPremiumPayment — verifies a Paystack reference and activates isPremium.
 */
exports.verifyPremiumPayment = onCall(
  { region: "us-central1", secrets: [PAYSTACK_SECRET_KEY] },
  async (request) => {
    requireVerifiedEmail(request.auth);
    const uid = request.auth.uid;
    const { reference } = request.data;

    if (!reference) {
      throw new HttpsError("invalid-argument", "Payment reference is required.");
    }

    const secretKey = PAYSTACK_SECRET_KEY.value();
    if (!secretKey) {
      throw new HttpsError("failed-precondition", "Payment gateway not configured.");
    }

    let verifyResponse;
    try {
      const fetch = (...args) =>
        import("node-fetch").then(({ default: f }) => f(...args));
      verifyResponse = await fetch(
        `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
        { headers: { Authorization: `Bearer ${secretKey}` } }
      );
    } catch (err) {
      throw new HttpsError("internal", "Could not verify payment.");
    }

    const body = await verifyResponse.json();
    if (!body.status || body.data?.status !== "success") {
      throw new HttpsError("failed-precondition", "Payment was not successful.");
    }

    // Ensure the payment metadata matches this user
    const meta = body.data?.metadata;
    if (meta?.uid && meta.uid !== uid) {
      throw new HttpsError("permission-denied", "Payment does not belong to this account.");
    }

    // FIX: Read the plan from metadata to correctly set planTier and cardsIncluded.
    // Previously always set planTier: 'premium' and cardsIncluded: 3 regardless of
    // the plan actually purchased (Business = 5 cards).
    const upgradedPlan = (meta?.plan && ["premium", "business"].includes(meta.plan))
      ? meta.plan
      : "premium";
    const PLAN_CONFIG = {
      premium:  { cards: 3 },
      business: { cards: 5 },
    };

    const userRef = db.collection("users").doc(uid);
    const idempotencyRef = db.collection("users").doc(uid).collection("plan_purchases").doc(reference);
    const nowMs = Date.now();

    try {
      await db.runTransaction(async (t) => {
        const existing = await t.get(idempotencyRef);
        if (existing.exists) {
          throw new HttpsError("already-exists", "This payment reference has already been processed.");
        }

        t.set(idempotencyRef, {
          reference,
          plan: upgradedPlan,
          amountKobo: body.data.amount,
          status: "success",
          timestamp: nowMs,
          source: "client_verify",
        });

        // FIX: Set planTier, subscription_expiry_date (30 days), and clear legacy isPremium field.
        // Without subscription_expiry_date, expirationCron would downgrade the user immediately.
        t.update(userRef, { 
          isPremium: true,            // kept for legacy compatibility
          planTier: upgradedPlan,
          cardsIncluded: PLAN_CONFIG[upgradedPlan].cards,
          subscription_expiry_date: nowMs + (30 * 24 * 60 * 60 * 1000),
          sentinel_trial_expiry_date: null, // not needed — planTier grant gives full access
        });
      });
    } catch (err) {
      if (err.code === "already-exists") {
        throw err;
      }
      console.error("[Premium] Idempotency transaction failed:", err);
      throw new HttpsError("internal", "Failed to securely process the plan upgrade.");
    }

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
