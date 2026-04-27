// functions/services/ghostCardSweeper.js
//
// Phase 3: Ghost Card Auto-Reconciliation (Two-Phase Commit Fix)
//
// Problem: If the Firebase server crashes or loses network exactly AFTER Bridgecard
// creates a card but BEFORE `cards/{id}` is written to Firestore, the user's fee
// is deducted and the card exists at Bridgecard — but the Gatekipa app sees nothing.
// We call this a "Ghost Card".
//
// Solution: A Dead-Letter Queue (DLQ) pattern.
//   1. A pre-flight lock is written to `card_provisioning_queue/{uuid}` with
//      status: "PENDING" before we hit the Bridgecard API.
//   2. On success, the queue item is marked "COMPLETED".
//   3. This sweeper runs every 15 minutes, queries for items stuck in PENDING
//      for > 5 minutes, then either auto-heals or auto-refunds.
//
// NOTE: The `card_provisioning_queue` document must be written at the START of
// `createBridgecard` (in bridgecardService.js) using the pattern documented at
// the bottom of this file.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { db } = require("../utils/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const axios = require("axios");
const { defineSecret } = require("firebase-functions/params");

const BRIDGECARD_ACCESS_TOKEN = defineSecret("BRIDGECARD_ACCESS_TOKEN");
const BASE_URL = process.env.BRIDGECARD_BASE_URL || "https://issuecards.api.bridgecard.co/v1/issuing";
const ISSUING_APP_ID = process.env.BRIDGECARD_ISSUING_APP_ID || "8ea9a4b4-26b1-4aa6-8e29-25648057ab7d";

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
  { schedule: "every 15 minutes", secrets: [BRIDGECARD_ACCESS_TOKEN] },
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
      const { uid, card_id, cardholder_id, fee_deducted_kobo, queue_id } = q;

      logger.warn(`[GhostCardSweeper] Processing stuck item: ${queueDoc.id} (card_id=${card_id}, uid=${uid})`);

      try {
        // ── Step 1: Check if Bridgecard actually created the card ──────────
        const client = axios.create({
          baseURL: BASE_URL,
          headers: {
            "accept": "application/json",
            "token": `Bearer ${BRIDGECARD_ACCESS_TOKEN.value().trim()}`,
            "issuing-app-id": ISSUING_APP_ID,
          },
          timeout: 30_000,
        });

        // Query Bridgecard for all cards belonging to this cardholder
        const bcRes = await client.get(`/cards/get_cardholder_cards?cardholder_id=${cardholder_id}`);
        const bcCards = bcRes.data?.data?.cards || [];

        // Match against our Firestore card doc metadata
        const cardSnap = await db.collection("cards").doc(card_id).get();
        const cardData = cardSnap.exists ? cardSnap.data() : null;

        // Find a card that was created within 10 minutes of our queue entry
        const tenMinsWindow = 10 * 60 * 1000;
        const orphanedCard = bcCards.find(bc => {
          const bcCreated = new Date(bc.date_created).getTime();
          return Math.abs(bcCreated - q.created_at) < tenMinsWindow;
        });

        if (orphanedCard) {
          // ── AUTO-HEAL: Card exists on Bridgecard, write it to Firestore ──
          logger.info(`[GhostCardSweeper] Found orphaned Bridgecard card ${orphanedCard.card_id} — auto-healing Firestore.`);

          await db.collection("cards").doc(card_id).set({
            bridgecard_card_id: orphanedCard.card_id,
            bridgecard_currency: orphanedCard.card_currency || "NGN",
            bridgecard_status: orphanedCard.is_active ? "active" : "frozen",
            local_status: "active",
            status: "active",
            last4: orphanedCard.last_four,
            masked_number: `**** **** **** ${orphanedCard.last_four}`,
          }, { merge: true });

          // Mark the queue item as auto-healed
          await queueDoc.ref.set({
            status: "AUTO_HEALED",
            healed_at: FieldValue.serverTimestamp(),
            bridgecard_card_id: orphanedCard.card_id,
          }, { merge: true });

          // Log to health_logs for audit visibility
          await db.collection("health_logs").add({
            timestamp: FieldValue.serverTimestamp(),
            level: "WARNING",
            source: "ghostCardSweeper",
            check: "ghost_card_auto_heal",
            message: `Auto-healed orphaned card ${orphanedCard.card_id} for UID ${uid}`,
            uid,
            card_id,
            bridgecard_card_id: orphanedCard.card_id,
          });

          // Notify the user
          await db.collection("users").doc(uid).collection("notifications").add({
            title: "Your card is ready!",
            body: "We detected and recovered your card from a provisioning hiccup. It is now active.",
            timestamp: new Date(),
            isRead: false,
            type: "card_healed",
          });

        } else {
          // ── AUTO-REFUND: Card doesn't exist on Bridgecard — refund fee ───
          logger.error(`[GhostCardSweeper] Card ${card_id} not found on Bridgecard — issuing automatic refund for UID ${uid}.`);

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
                  original_queue_id: queueDoc.id,
                },
                correlationId: `ghostCardSweeper:${queueDoc.id}`,
              });

              logger.info(`[GhostCardSweeper] Refunded ₦${refundAmountNgn} to UID ${uid}`);
            } catch (refundErr) {
              logger.error(`[GhostCardSweeper] CRITICAL: Refund failed for UID ${uid}:`, refundErr.message);
            }
          }

          // Delete or nullify the orphaned card doc to prevent UI confusion
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
          }, { merge: true });

          await db.collection("health_logs").add({
            timestamp: FieldValue.serverTimestamp(),
            level: "CRITICAL",
            source: "ghostCardSweeper",
            check: "ghost_card_auto_refund",
            message: `Auto-refunded ₦${fee_deducted_kobo / 100} for failed card provisioning for UID ${uid}`,
            uid,
            card_id,
            refund_amount_kobo: fee_deducted_kobo,
          });

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
 * ─── HOW TO INSTRUMENT createBridgecard (bridgecardService.js) ───────────────
 *
 * BEFORE hitting the Bridgecard API, write a pre-flight lock:
 *
 *   const queueId = `cpq_${card_id}_${Date.now()}`;
 *   await db.collection("card_provisioning_queue").doc(queueId).set({
 *     queue_id: queueId,
 *     uid,
 *     card_id,
 *     cardholder_id,
 *     fee_deducted_kobo: feeToDeductNGN * 100,
 *     status: "PENDING",
 *     created_at: Date.now(),
 *   });
 *
 * AFTER the Bridgecard API responds with a card_id, mark it COMPLETED:
 *
 *   await db.collection("card_provisioning_queue").doc(queueId)
 *     .set({ status: "COMPLETED", bridgecard_card_id }, { merge: true });
 */
