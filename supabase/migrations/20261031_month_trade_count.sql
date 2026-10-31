-- One definition of "trades used this month".
--
-- The UI used to count rows by `created_at` while `enforce_trade_quota` counts by
-- `COALESCE(close_time, open_time, created_at)`. A trade closed this month but
-- created last month was therefore invisible to the meter and rejected by the
-- trigger. Both sides now call this function.

CREATE OR REPLACE FUNCTION month_trade_count()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COUNT(*)::int
  FROM trades
  WHERE user_id = auth.uid()
    AND date_trunc('month', COALESCE(close_time, open_time, created_at))
        = date_trunc('month', now());
$$;

COMMENT ON FUNCTION month_trade_count() IS
  'Trades counted against the monthly quota for the signed-in user, using the same window as enforce_trade_quota().';

REVOKE ALL ON FUNCTION month_trade_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION month_trade_count() TO authenticated;
