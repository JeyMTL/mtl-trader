-- Give trial users unlimited access for 30 days, then require a paid plan.
UPDATE users
SET max_trades = -1,
    trades_remaining = -1,
  trial_ends_at = NOW() + INTERVAL '30 days'
WHERE subscription_tier = 'free'
  AND subscription_status = 'trial';

ALTER TABLE users ALTER COLUMN max_trades SET DEFAULT -1;
ALTER TABLE users ALTER COLUMN trades_remaining SET DEFAULT -1;

CREATE OR REPLACE FUNCTION enforce_trade_quota()
RETURNS TRIGGER AS $$
DECLARE
  m_max INTEGER;
  m_count BIGINT;
  m_ts TIMESTAMP WITH TIME ZONE;
BEGIN
  IF EXISTS (
    SELECT 1 FROM users
    WHERE id = NEW.user_id
      AND subscription_status = 'trial'
      AND trial_ends_at IS NOT NULL
      AND trial_ends_at <= now()
  ) THEN
    RAISE EXCEPTION 'Free trial ended. Choose a paid plan to add trades.';
  END IF;

  SELECT COALESCE(max_trades, -1) INTO m_max
  FROM users
  WHERE id = NEW.user_id;

  IF m_max IS NULL OR m_max = -1 THEN
    RETURN NEW;
  END IF;

  m_ts := COALESCE(NEW.close_time, NEW.open_time, NEW.created_at, now());

  IF date_trunc('month', m_ts) <> date_trunc('month', now()) THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO m_count
  FROM trades
  WHERE user_id = NEW.user_id
    AND date_trunc('month', COALESCE(close_time, open_time, created_at)) = date_trunc('month', now());

  IF m_count >= m_max THEN
    RAISE EXCEPTION 'Monthly trade limit reached (% trades). Upgrade your plan for more.', m_max;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_trade_quota ON trades;
CREATE TRIGGER trg_enforce_trade_quota
  BEFORE INSERT ON trades
  FOR EACH ROW EXECUTE FUNCTION enforce_trade_quota();
