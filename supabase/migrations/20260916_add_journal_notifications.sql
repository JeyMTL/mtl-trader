-- Add preferences for in-app journal reminders and monthly overviews.
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_journal_reminders BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notifications_monthly_overview BOOLEAN DEFAULT true;
