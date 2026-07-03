const logger = require('firebase-functions/logger');
const { query } = require('../utils/db');

/**
 * Inserts a record into the PostgreSQL transactions table.
 * Supports passing a client for transactions.
 */
async function pgInsertTransaction(txn, client = null) {
  const q = client ? client.query.bind(client) : query;
  
  const text = `
    INSERT INTO transactions (id, user_id, type, amount_kobo, amount, status, metadata, created_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
      status = EXCLUDED.status,
      metadata = transactions.metadata || EXCLUDED.metadata,
      updated_at = NOW();
  `;
  
  const amount = Number((txn.amount_kobo / 100).toFixed(2));
  const params = [
    txn.id,
    txn.user_id,
    txn.type,
    txn.amount_kobo,
    amount,
    txn.status,
    JSON.stringify(txn.metadata || {})
  ];
  
  await q(text, params);
  logger.info(`[Postgres Ledger] Inserted/updated transaction ${txn.id} (Status: ${txn.status})`);
}

/**
 * Updates a transaction status in PostgreSQL.
 */
async function pgUpdateTransactionStatus(id, status, client = null) {
  const q = client ? client.query.bind(client) : query;
  
  const text = `
    UPDATE transactions
    SET status = $1, updated_at = NOW()
    WHERE id = $2;
  `;
  
  await q(text, [status, id]);
  logger.info(`[Postgres Ledger] Updated transaction ${id} status to ${status}`);
}

/**
 * Inserts an entry into the PostgreSQL wallet_ledger table.
 */
async function pgInsertWalletLedger(ledger, client = null) {
  const q = client ? client.query.bind(client) : query;
  
  const text = `
    INSERT INTO wallet_ledger (user_id, type, amount_kobo, amount, reference, balance_after_kobo, balance_after, source, metadata, created_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW());
  `;
  
  const amount = Number((ledger.amount_kobo / 100).toFixed(2));
  const balanceAfter = Number((ledger.balance_after_kobo / 100).toFixed(2));
  const params = [
    ledger.user_id,
    ledger.type,
    ledger.amount_kobo,
    amount,
    ledger.reference,
    ledger.balance_after_kobo,
    balanceAfter,
    ledger.source,
    JSON.stringify(ledger.metadata || {})
  ];
  
  await q(text, params);
  logger.info(`[Postgres Ledger] Wallet ledger entry saved for user ${ledger.user_id} (${ledger.type})`);
}

/**
 * Inserts an entry into the PostgreSQL card_ledger table.
 */
async function pgInsertCardLedger(ledger, client = null) {
  const q = client ? client.query.bind(client) : query;
  
  const text = `
    INSERT INTO card_ledger (card_id, account_id, type, amount_kobo, amount, merchant_name, reference, created_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, NOW());
  `;
  
  const amount = Number((ledger.amount_kobo / 100).toFixed(2));
  const params = [
    ledger.card_id,
    ledger.account_id || '',
    ledger.type,
    ledger.amount_kobo,
    amount,
    ledger.merchant_name || 'Unknown',
    ledger.reference
  ];
  
  await q(text, params);
  logger.info(`[Postgres Ledger] Card ledger entry saved for card ${ledger.card_id} (${ledger.type})`);
}

module.exports = {
  pgInsertTransaction,
  pgUpdateTransactionStatus,
  pgInsertWalletLedger,
  pgInsertCardLedger
};
