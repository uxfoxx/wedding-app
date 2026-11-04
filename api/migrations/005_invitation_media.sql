-- The couple's own invitation photos and music, uploaded straight to storage (no pasted links).
-- A file stays while the invitation uses it; replaced or removed ones are deleted.
CREATE TABLE invitation_media (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id    uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('cover','photo','music')),
  path          text NOT NULL UNIQUE,
  content_type  text NOT NULL,
  size_bytes    bigint NOT NULL,
  upload_token  text UNIQUE,
  ready         boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX invitation_media_wedding ON invitation_media (wedding_id);
