-- Persisted AI reviews. Enables (a) caching so an unchanged journal does not
-- re-bill the model, (b) review history in the UI, and (c) outcome tracking,
-- since created_at is the moment the advice was produced.
CREATE TABLE IF NOT EXISTS ai_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  summary_hash TEXT NOT NULL,
  provider TEXT,
  model TEXT,
  review JSONB NOT NULL,
  stats JSONB,
  similar JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_reviews_user_created ON ai_reviews (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_reviews_user_hash ON ai_reviews (user_id, summary_hash);

ALTER TABLE ai_reviews ENABLE ROW LEVEL SECURITY;

-- Users can read and manage only their own reviews. Server routes use the
-- service role and bypass RLS, matching the rest of the app.
DROP POLICY IF EXISTS "Users can view own AI reviews" ON ai_reviews;
CREATE POLICY "Users can view own AI reviews" ON ai_reviews
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own AI reviews" ON ai_reviews;
CREATE POLICY "Users can insert own AI reviews" ON ai_reviews
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own AI reviews" ON ai_reviews;
CREATE POLICY "Users can delete own AI reviews" ON ai_reviews
  FOR DELETE USING (auth.uid() = user_id);
