// functions/services/systemService.js
//
// Admin-only Cloud Functions for system mode management.
// These are the ONLY write paths to system_state/global.
//
// The Next.js admin portal's Kill Switch API also writes to this document,
// so both paths converge on the same atomic gate.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { requireAdmin } = require("../utils/validators");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const VALID_MODES = ["NORMAL", "DEGRADED", "LOCKDOWN"];

/**
 * adminSetSystemMode — admin-only Cloud Function.
 * Sets the global system operating mode.
 *
 * Callable by: Admin Panel (enforceAppCheck: false) OR Flutter admin user.
 *
 * @param {object} data
 * @param {string} data.mode   - 'NORMAL' | 'DEGRADED' | 'LOCKDOWN'
 * @param {string} data.reason - Human-readable reason for the change.
 */
exports.adminSetSystemMode = onCall({ region: "us-central1", enforceAppCheck: false }, async (request) => {
  requireAdmin(request.auth);

  const { mode, reason = "No reason provided" } = request.data;

  if (!VALID_MODES.includes(mode)) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid mode '${mode}'. Must be one of: ${VALID_MODES.join(", ")}.`
    );
  }

  const prevSnap = await db.doc("system_state/global").get();
  const prevMode = prevSnap.data()?.mode || "NORMAL";

  await db.doc("system_state/global").set({
    mode,
    reason,
    previous_mode: prevMode,
    updated_by: request.auth.uid,
    updated_at: FieldValue.serverTimestamp(),
  });

  // Write a state change log for auditability
  await db.collection("system_state_log").add({
    from_mode: prevMode,
    to_mode: mode,
    reason,
    changed_by: request.auth.uid,
    changed_at: FieldValue.serverTimestamp(),
  });

  logger.info(`[SystemMode] ${prevMode} → ${mode} by ${request.auth.uid}. Reason: ${reason}`);

  return { success: true, mode, previous_mode: prevMode };
});

/**
 * adminGetSystemMode — read the current mode.
 * Open to any authenticated admin.
 */
exports.adminGetSystemMode = onCall({ region: "us-central1", enforceAppCheck: false }, async (request) => {
  requireAdmin(request.auth);

  const snap = await db.doc("system_state/global").get();
  if (!snap.exists) return { mode: "NORMAL", reason: "No record — defaulting to NORMAL" };

  return { ...snap.data(), updated_at: snap.data().updated_at?.toDate()?.toISOString() };
});
