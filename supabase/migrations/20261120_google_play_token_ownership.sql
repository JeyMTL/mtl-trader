-- ============================================================
-- Google Play purchase-token ownership
--
-- A purchase token identifies one Google subscription. The table was keyed by
-- `user_id` only, so two accounts could each store the same token. The server
-- checks ownership before granting, but an application-level check cannot stop
-- two concurrent verifications from both passing it. This index makes the
-- database the final authority: a token can belong to at most one account.
--
-- The verify route also compares the stored owner and refuses a token linked to
-- another account, so this index is a backstop rather than the only check.
--
-- If this migration fails, the table already contains the same token on more
-- than one account. Find them before deleting anything:
--
--   SELECT purchase_token, array_agg(user_id) AS accounts, count(*)
--   FROM public.google_play_subscriptions
--   GROUP BY purchase_token
--   HAVING count(*) > 1;
--
-- Keep the row whose account actually bought the subscription (the Play console
-- shows the obfuscated account id), remove the others, then re-run.
--
-- Idempotent: CREATE UNIQUE INDEX IF NOT EXISTS.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_google_play_subscriptions_token
  ON public.google_play_subscriptions (purchase_token);
