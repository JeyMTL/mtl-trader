-- ------------------------------------------------------------
-- Public profile pictures.
--
-- Avatars are the one media type that has to render in a plain <img> without a
-- signed URL, so reads are public while writes stay owner-only. Every object
-- path starts with the owner's id (`<user_id>/<uuid>.<ext>`), which is exactly
-- what the write policies compare against auth.uid().
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  2097152, -- 2 MB: a 512px portrait is well under this
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- A profile picture is referenced by a public URL, so anyone may load one.
DROP POLICY IF EXISTS "Avatars are readable" ON storage.objects;
CREATE POLICY "Avatars are readable" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Avatars are owner writable" ON storage.objects;
CREATE POLICY "Avatars are owner writable" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Avatars are owner updatable" ON storage.objects;
CREATE POLICY "Avatars are owner updatable" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "Avatars are owner deletable" ON storage.objects;
CREATE POLICY "Avatars are owner deletable" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
