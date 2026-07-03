const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const logger = require('firebase-functions/logger');

let pool;

function getDbPool() {
  if (pool) return pool;

  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    logger.warn('[Postgres DB] DATABASE_URL is not configured. Relational database operations will fail.');
    return null;
  }

  pool = new Pool({
    connectionString,
    max: 10,                 // Low maximum connection pool size appropriate for Cloud Functions scale
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    ssl: {
      rejectUnauthorized: false // Required for many serverless PG hosts (e.g. Neon, Supabase, Vercel)
    }
  });

  pool.on('error', (err) => {
    logger.error('[Postgres DB] Unexpected pool error:', err);
  });

  return pool;
}

/**
 * Helper to execute raw queries on the database.
 */
async function query(text, params) {
  const dbPool = getDbPool();
  if (!dbPool) {
    throw new Error('Database is not configured. Set DATABASE_URL.');
  }
  return await dbPool.query(text, params);
}

/**
 * Execute a function within a database transaction block.
 */
async function runTransaction(callback) {
  const dbPool = getDbPool();
  if (!dbPool) {
    throw new Error('Database is not configured. Set DATABASE_URL.');
  }
  
  const client = await dbPool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

/**
 * Runs migrations/schema setup on startup.
 */
async function initializeSchema() {
  try {
    const schemaPath = path.join(__dirname, '../db/init_schema.sql');
    const schemaSql = fs.readFileSync(schemaPath, 'utf8');
    
    logger.info('[Postgres DB] Initializing relational database schema...');
    await query(schemaSql);
    logger.info('[Postgres DB] Schema initialized successfully.');
    return true;
  } catch (error) {
    logger.error('[Postgres DB] Schema initialization failed:', error);
    return false;
  }
}

module.exports = {
  getDbPool,
  query,
  runTransaction,
  initializeSchema
};
