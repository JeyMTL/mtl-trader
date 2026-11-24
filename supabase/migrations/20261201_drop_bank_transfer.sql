-- Bank transfer is gone: the website sells by card through Paddle, and the
-- Android app through Google Play. The queue and the function that approved it
-- have no caller left, so leaving them would keep stale customer references and
-- a review path that nothing enforces.
--
-- The signature has to be spelled exactly as Postgres stored it, or `if exists`
-- matches nothing and reports success while the function stays: p_action is
-- text and both ids are uuid. The text/text/uuid line covers a deployment that
-- created it with ids as text; it is a no-op where that signature never existed.

drop function if exists public.review_bank_payment_request(text, uuid, uuid);
drop function if exists public.review_bank_payment_request(text, text, uuid);
drop table if exists public.payment_requests;
