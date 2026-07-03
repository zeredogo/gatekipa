-- Database Schema Initialization for Gatekipa Relational Ledgers

-- 1. Transactions Table
CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'wallet_funding', 'card_funding', 'card_charge', 'withdrawal_hold'
    amount_kobo BIGINT NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at);

-- 2. Wallet Ledger Table
CREATE TABLE IF NOT EXISTS wallet_ledger (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'credit', 'debit'
    amount_kobo BIGINT NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    reference VARCHAR(255) NOT NULL, -- Points to transactions(id) or withdrawal request
    balance_after_kobo BIGINT NOT NULL,
    balance_after NUMERIC(15, 2) NOT NULL,
    source VARCHAR(255) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user_id ON wallet_ledger(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_reference ON wallet_ledger(reference);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_created_at ON wallet_ledger(created_at);

-- 3. Card Ledger Table
CREATE TABLE IF NOT EXISTS card_ledger (
    id SERIAL PRIMARY KEY,
    card_id VARCHAR(255) NOT NULL,
    account_id VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'charge', 'funding', 'refund'
    amount_kobo BIGINT NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    merchant_name VARCHAR(255) NOT NULL,
    reference VARCHAR(255) NOT NULL, -- Points to transactions(id) or external provider ID
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_card_ledger_card_id ON card_ledger(card_id);
CREATE INDEX IF NOT EXISTS idx_card_ledger_reference ON card_ledger(reference);
CREATE INDEX IF NOT EXISTS idx_card_ledger_created_at ON card_ledger(created_at);
