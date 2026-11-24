-- Bank transfer is gone: the website sells by card through Paddle, and the
-- Android app through Google Play. The queue and the function that approved it
-- have no caller left, so leaving them would keep stale customer references and
-- a review path that nothing enforces.

drop function if exists public.review_bank_payment_request(text, text, uuid);
drop table if exists public.payment_requests;
