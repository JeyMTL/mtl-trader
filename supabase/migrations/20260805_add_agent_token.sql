-- Add agent_token column to users table for MT5 sync authentication
ALTER TABLE users ADD COLUMN IF NOT EXISTS agent_token TEXT;

-- Add ticket column to trades table for MT5 deal tickets
ALTER TABLE trades ADD COLUMN IF NOT EXISTS ticket BIGINT;

-- Create unique index on ticket per user to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_trades_user_ticket ON trades (user_id, ticket) WHERE ticket IS NOT NULL;
