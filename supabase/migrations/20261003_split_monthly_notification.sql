-- Split the monthly notification setting into two independent preferences:
--   notifications_monthly_overview — show the overview card on the dashboard
--   notifications_monthly_email    — send the monthly summary email
-- Previously the single notifications_monthly_overview column controlled both,
-- so toggling the dashboard card silently enabled/disabled the monthly email.
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_monthly_email BOOLEAN DEFAULT true;

-- Existing users opted into the monthly overview should keep receiving the email.
UPDATE users SET notifications_monthly_email = notifications_monthly_overview
WHERE notifications_monthly_email IS DISTINCT FROM notifications_monthly_overview;
