const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const { sendEmail } = require("./emailService");

/**
 * Triggered when a new user document is created in /users/{userId}.
 * - Normalises required fields (id, type, active_account_id)
 * - Idempotently initialises the user's wallet subcollection
 */
exports.onUserCreated = onDocumentCreated(
  { document: "users/{userId}", region: "us-central1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const userId = event.params.userId;
    const data = snap.data();

    // ── 1. Normalise top-level user fields ──────────────────────────────────
    const updates = {};
    if (!data.id)   updates.id   = userId;
    if (!data.type) updates.type = "individual";

    // Ensure server-side created_at is set (client may have sent epoch ms)
    if (!data.created_at) updates.created_at = FieldValue.serverTimestamp();

    // Initialise active_account_id to null if not already present
    if (data.active_account_id === undefined) {
      updates.active_account_id = null;
    }

    if (Object.keys(updates).length > 0) {
      await snap.ref.update(updates);
    }

    // ── 2. Idempotently initialise wallet balance doc ───────────────────────
    const walletRef = snap.ref.collection("wallet").doc("balance");
    const walletSnap = await walletRef.get();
    if (!walletSnap.exists) {
      await walletRef.set({
        user_id: userId,
        balance: 0,
        currency: "NGN",
        created_at: FieldValue.serverTimestamp(),
      });
    }

    // ── 3. Send Welcome Email ───────────────────────────────────────────────
    if (data.email) {
      const emailHtml = `
        <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; line-height: 1.6; color: #333;">
          <h1 style="color: #1a1a1a;">Welcome to Gatekipa! 🚀</h1>
          <p>Hi ${data.display_name || data.name || "there"},</p>
          <p>Welcome to <strong>Gatekipa</strong>! We're thrilled to have you join us.</p>
          <p>Your wallet has been successfully initialized and you're ready to start taking control of your subscriptions.</p>
          <div style="background: #f4f4f5; padding: 20px; border-radius: 12px; margin: 20px 0;">
            <p style="margin: 0;">If you have any questions or need help exploring the platform, simply reply to this email or visit our help center.</p>
          </div>
          <p>Best regards,<br/><strong>The Gatekipa Team</strong></p>
        </div>
      `;
      
      // Dispatch non-blocking email
      sendEmail({
        to: data.email,
        subject: "Welcome to Gatekipa! 🎉",
        html: emailHtml,
      }).catch(err => console.error("Failed to send welcome email:", err));
    }
  }
);
