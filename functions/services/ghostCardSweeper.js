// functions/services/ghostCardSweeper.js
//
// Phase 3: Ghost Card Auto-Reconciliation (Two-Phase Commit Fix)
//
// Problem: If the Firebase server crashes or loses network exactly AFTER Sudo
// creates a card but BEFORE `cards/{id}` is written to Firestore, the user's fee
// is deducted and the card exists at Sudo — but the Gatekipa app sees nothing.
// We call this a "Ghost Card".
//
// Solution: A Dead-Letter Queue (DLQ) pattern.
//   1. A pre-flight lock is written to `card_provisioning_queue/{uuid}` with
//      status: "PENDING" before we hit the Sudo API.
//   2. On success, the queue item is marked "COMPLETED".
//   3. This sweeper runs every 15 minutes, queries for items stuck in PENDING
//      for > 5 minutes, then either auto-heals or auto-refunds.
//
// NOTE: The `card_provisioning_queue` document must be written at the START of
// `createSudoCard` (in sudoService.js) using the pattern documented at
// the bottom of this file.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");

// Removed Bridgecard environment variables

const SUDO_API_KEY = defineSecret("SUDO_API_KEY");
const SUDO_BASE_URL = process.env.SUDO_BASE_URL || "https://api.sudo.africa";

// Lazy-load to prevent circular dependency
let _processTransactionInternal;
function getOrchestrator() {
  if (!_processTransactionInternal) {
    _processTransactionInternal = require("./transactionService").processTransactionInternal;
  }
  return _processTransactionInternal;
}

// ─────────────────────────────────────────────────────────────────────────────
// ghostCardSweeper — runs every 15 minutes
// ─────────────────────────────────────────────────────────────────────────────
exports.ghostCardSweeper = onSchedule(
  { schedule: "every 15 minutes", secrets: [SUDO_API_KEY] },
  async () => {
    logger.info("[GhostCardSweeper] Starting sweep...");

    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;

    const stuckSnap = await db.collection("card_provisioning_queue")
      .where("status", "==", "PENDING")
      .where("created_at", "<=", fiveMinutesAgo)
      .get();

    if (stuckSnap.empty) {
      logger.info("[GhostCardSweeper] No stuck provisioning requests found.");
      return;
    }

    logger.warn(`[GhostCardSweeper] Found ${stuckSnap.size} stuck provisioning requests.`);

    for (const queueDoc of stuckSnap.docs) {
      const q = queueDoc.data();
      const { uid, card_id, cardholder_id, fee_deducted_kobo, card_currency = "NGN" } = q;
      const provider = "sudo";

      logger.warn(`[GhostCardSweeper] Processing stuck ${provider} item: ${queueDoc.id} (card_id=${card_id}, uid=${uid})`);

      try {
        let orphanedCardId = null;
        let orphanedCardDetails = null;

        // ── Sudo Africa Query Logic ──
        const userSnap = await db.collection("users").doc(uid).get();
        const sudoCustomerId = userSnap.data()?.sudo_customer_id;

        if (sudoCustomerId) {
          const client = axios.create({
            baseURL: SUDO_BASE_URL,
            headers: {
              Authorization: `Bearer ${SUDO_API_KEY.value().trim()}`,
              "Content-Type": "application/json",
            },
            timeout: 30_000,
          });

          const sudoRes = await client.get(`/cards?customerId=${sudoCustomerId}`);
          const sudoCards = sudoRes.data?.data || [];
          const tenMinsWindow = 10 * 60 * 1000;

          const orphaned = sudoCards.find(sc => {
            const scCreated = new Date(sc.createdAt).getTime();
            return Math.abs(scCreated - q.created_at) < tenMinsWindow;
          });

          if (orphaned) {
            orphanedCardId = orphaned._id;
            // Sudo vault reveal would be needed for full details, 
            // but for auto-heal we can at least recover the ID and basic status.
            orphanedCardDetails = {
              sudo_card_id: orphaned._id,
              sudo_currency: card_currency,
              sudo_status: orphaned.status === "active" ? "active" : "frozen",
              status: "active",
              last4: orphaned.maskedPan ? orphaned.maskedPan.slice(-4) : "0000",
              masked_number: `**** **** **** ${orphaned.last4 || "0000"}`,
            };
          }
        }

        const cardSnap = await db.collection("cards").doc(card_id).get();

        if (orphanedCardId) {
          // ── AUTO-HEAL: Card exists at provider ──
          logger.info(`[GhostCardSweeper] Found orphaned ${provider} card ${orphanedCardId} — auto-healing Firestore.`);

          await db.collection("cards").doc(card_id).set({
            ...orphanedCardDetails,
            local_status: "active",
            status: "active",
            updated_at: FieldValue.serverTimestamp(),
          }, { merge: true });

          await queueDoc.ref.set({
            status: "AUTO_HEALED",
            healed_at: FieldValue.serverTimestamp(),
            recovered_card_id: orphanedCardId,
            provider
          }, { merge: true });

          // Notify the user
          await db.collection("users").doc(uid).collection("notifications").add({
            title: "Your card is ready!",
            body: "We recovered your card from a provisioning hiccup. It is now active.",
            timestamp: new Date(),
            isRead: false,
            type: "card_healed",
          });

        } else {
          // ── AUTO-REFUND: Card doesn't exist at provider ──
          logger.error(`[GhostCardSweeper] Card ${card_id} not found at ${provider} — issuing automatic refund for UID ${uid}.`);

          if (fee_deducted_kobo > 0) {
            const refundAmountNgn = fee_deducted_kobo / 100;
            try {
              await getOrchestrator()({
                type: "wallet_funding",
                userId: uid,
                amount: refundAmountNgn,
                idempotencyKey: `ghost_card_refund:${queueDoc.id}`,
                metadata: {
                  source: "ghost_card_auto_refund",
                  provider,
                  original_queue_id: queueDoc.id,
                },
                correlationId: `ghostCardSweeper:${queueDoc.id}`,
              });
              logger.info(`[GhostCardSweeper] Refunded ₦${refundAmountNgn} to UID ${uid}`);
            } catch (refundErr) {
              logger.error(`[GhostCardSweeper] CRITICAL: Refund failed for UID ${uid}:`, refundErr.message);
            }
          }

          if (cardSnap.exists) {
            await db.collection("cards").doc(card_id).update({
              local_status: "provisioning_failed",
              status: "provisioning_failed",
              updated_at: FieldValue.serverTimestamp(),
            });
          }

          await queueDoc.ref.set({
            status: "AUTO_REFUNDED",
            refunded_at: FieldValue.serverTimestamp(),
            refund_amount_kobo: fee_deducted_kobo,
            provider
          }, { merge: true });

          // Notify the user
          await db.collection("users").doc(uid).collection("notifications").add({
            title: "Card creation failed — refund issued",
            body: `We could not complete your card setup. A refund of ₦${(fee_deducted_kobo / 100).toLocaleString()} has been credited to your vault.`,
            timestamp: new Date(),
            isRead: false,
            type: "card_refunded",
          });
        }

      } catch (err) {
        logger.error(`[GhostCardSweeper] Error processing queue item ${queueDoc.id}:`, err.message);
        await queueDoc.ref.set({
          status: "SWEEP_ERROR",
          error: err.message,
          updated_at: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }

    logger.info(`[GhostCardSweeper] Sweep complete. Processed ${stuckSnap.size} items.`);
  }
);

/*
 * ─── HOW TO INSTRUMENT createSudoCard (sudoService.js) ───────────────
 *
 * BEFORE hitting the Sudo API, write a pre-flight lock:
 *
 *   const queueId = `cpq_${card_id}_${Date.now()}`;
 *   await db.collection("card_provisioning_queue").doc(queueId).set({
 *     queue_id: queueId,
 *     uid,
 *     card_id,
 *     fee_deducted_kobo: feeToDeductNGN * 100,
 *     status: "PENDING",
 *     created_at: Date.now(),
 *   });
 *
 * AFTER the API responds with a card_id, mark it COMPLETED:
 *
 *   await db.collection("card_provisioning_queue").doc(queueId)
 *     .set({ status: "COMPLETED", sudo_card_id }, { merge: true });
 */
