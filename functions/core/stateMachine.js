// functions/core/stateMachine.js
//
// Enforces valid card lifecycle transitions on the backend.
// NO client code or admin panel may bypass this — all card status changes
// MUST call assertValidTransition before writing to Firestore.
//
// Valid state machine:
//
//   pending_issuance ──→ issued ──→ active ──→ frozen ──→ terminated
//                   └─────────────────────────────────→ terminated
//                                         └──→ active (unfreeze)
//
// Transitions NOT in this map are hard errors, not soft warnings.

const VALID_TRANSITIONS = {
  pending_issuance: ["issued", "terminated"],
  issued:           ["active", "terminated"],
  active:           ["frozen", "terminated"],
  frozen:           ["active", "terminated"],   // active = unfreeze
  terminated:       [],                          // terminal — no further transitions
};

/**
 * Asserts that a card status transition is valid.
 * Throws if the transition is not permitted.
 *
 * @param {string} from - Current card localStatus.
 * @param {string} to   - Desired target status.
 * @throws {Error} If the transition is invalid.
 */
function assertValidTransition(from, to) {
  const allowed = VALID_TRANSITIONS[from];

  if (allowed === undefined) {
    throw new Error(`INVALID_STATUS: Unknown source status '${from}'.`);
  }

  if (!allowed.includes(to)) {
    throw new Error(
      `INVALID_TRANSITION: Cannot move card from '${from}' to '${to}'. ` +
      `Allowed: [${allowed.join(", ") || "none — terminal state"}].`
    );
  }
}

/**
 * Returns the valid next statuses from a given status.
 * Used by admin tools to show permitted actions.
 *
 * @param {string} status - Current card status.
 * @returns {string[]}
 */
function getAllowedTransitions(status) {
  return VALID_TRANSITIONS[status] || [];
}

module.exports = { assertValidTransition, getAllowedTransitions };
