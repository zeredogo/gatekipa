// functions/core/systemState.js
//
// Reads the global system operating mode from system_state/global.
// Called at the start of every financial Cloud Function to enforce fail-closed behavior.
//
// Modes:
//   NORMAL   → All operations permitted.
//   DEGRADED → External APIs unstable; warn but allow (configurable).
//   LOCKDOWN → All financial ops rejected immediately.
//
// The document is written ONLY by:
//   1. Admin Portal Kill Switch  (api/kill-switch/route.ts)
//   2. adminSetSystemMode Cloud Function (admin-only)

const { db } = require("../utils/firebase");
const logger = require("firebase-functions/logger");

/**
 * Reads the current system mode.
 * @returns {Promise<'NORMAL'|'DEGRADED'|'LOCKDOWN'>}
 */
async function getSystemMode() {
  try {
    const snap = await db.doc("system_state/global").get();
    if (!snap.exists) return "NORMAL";
    return snap.data().mode || "NORMAL";
  } catch (e) {
    // If we can't read system state, fail OPEN for reads but log critical error.
    // Financial mutation functions will handle this themselves.
    logger.error("[SystemState] Failed to read system_state/global:", e.message);
    return "NORMAL";
  }
}

/**
 * Throws an error if the system mode does not permit financial operations.
 * Call this at the VERY START of every financial Cloud Function.
 *
 * @param {string} mode - Result of getSystemMode()
 * @throws {Error} If mode is LOCKDOWN or DEGRADED.
 */
function assertSystemAllowsFinancialOps(mode) {
  if (mode === "LOCKDOWN") {
    throw new Error("SYSTEM_LOCKDOWN: All financial operations are suspended. Please contact support.");
  }
  if (mode === "DEGRADED") {
    throw new Error("SYSTEM_DEGRADED: Operations are temporarily limited. Please try again shortly.");
  }
}

module.exports = { getSystemMode, assertSystemAllowsFinancialOps };
