-- Payment requests must be created through the authenticated server route,
-- which derives plan pricing from the canonical plan list.
DROP POLICY IF EXISTS "Users can insert own payment requests" ON payment_requests;
