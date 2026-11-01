-- Phase 2: planners, seating, guest experience on the day, planning tools.

-- ---------- Planners ----------
CREATE TABLE planners (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL REFERENCES users(id),
  business_name   text NOT NULL,
  phone           text,
  district        text,
  logo_url        text,
  plan            text NOT NULL DEFAULT 'free' CHECK (plan IN ('free','studio10','studio_unlimited')),
  studio_until    timestamptz,            -- Studio covers weddings only while it is paid
  approved_at     timestamptz,            -- admin approves planner accounts
  approved_by     uuid REFERENCES users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ON planners (owner_id);

CREATE TABLE planner_members (
  planner_id  uuid NOT NULL REFERENCES planners(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('owner','coordinator')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (planner_id, user_id)
);

CREATE TABLE planner_invites (
  token_hash  text PRIMARY KEY,
  planner_id  uuid NOT NULL REFERENCES planners(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  accepted_by uuid REFERENCES users(id)
);

ALTER TABLE weddings
  ADD COLUMN planner_id uuid REFERENCES planners(id),
  ADD COLUMN covered_by_studio boolean NOT NULL DEFAULT false,
  ADD COLUMN planner_notes text,
  ADD COLUMN client_name text,
  ADD COLUMN client_phone text,
  ADD COLUMN settings jsonb NOT NULL DEFAULT '{}'::jsonb;   -- wall approval, uploads on/off, etc.

-- Marks who came in through the planner (team assignment), so removing a coordinator is clean.
ALTER TABLE wedding_members ADD COLUMN via_planner boolean NOT NULL DEFAULT false;

-- Reusable checklists / run sheets a planner copies into each wedding.
CREATE TABLE planner_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  planner_id  uuid NOT NULL REFERENCES planners(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('checklist','run_sheet','budget')),
  name        text NOT NULL,
  items       jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Tasks (planner and couple) ----------
CREATE TABLE tasks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id   uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  title        text NOT NULL,
  due_date     date,
  assignee_id  uuid REFERENCES users(id) ON DELETE SET NULL,
  done_at      timestamptz,
  kind         text NOT NULL DEFAULT 'task' CHECK (kind IN ('task','checklist')),
  months_before int,                     -- checklist suggestion bucket
  sort         int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ON tasks (wedding_id);
CREATE INDEX ON tasks (assignee_id) WHERE done_at IS NULL;

-- ---------- Seating ----------
CREATE TABLE seating_tables (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  event_id    uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  name        text NOT NULL,
  shape       text NOT NULL DEFAULT 'round' CHECK (shape IN ('round','long','head')),
  seats       int NOT NULL CHECK (seats BETWEEN 1 AND 60),
  sort        int NOT NULL DEFAULT 0
);
CREATE INDEX ON seating_tables (event_id);

CREATE TABLE seat_assignments (
  guest_id   uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  event_id   uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  table_id   uuid NOT NULL REFERENCES seating_tables(id) ON DELETE CASCADE,
  PRIMARY KEY (guest_id, event_id)
);
CREATE INDEX ON seat_assignments (table_id);

-- Guests who should not sit together (known conflicts).
CREATE TABLE guest_conflicts (
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  a           uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  b           uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  PRIMARY KEY (a, b),
  CHECK (a < b)
);

-- ---------- Guest experience ----------
CREATE TABLE wedding_updates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  body        text NOT NULL,
  kind        text NOT NULL DEFAULT 'info' CHECK (kind IN ('info','time','venue','dress_code','parking')),
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Photos, videos and voice notes from guests (bytes live in object storage, never on the server).
CREATE TABLE uploads (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id   uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('photo','video','voice')),
  path         text NOT NULL UNIQUE,
  content_type text NOT NULL,
  size_bytes   int,
  uploader     text,                     -- the name the guest typed
  guest_id     uuid REFERENCES guests(id) ON DELETE SET NULL,
  upload_token text NOT NULL UNIQUE,     -- one-time token for the direct upload
  status       text NOT NULL DEFAULT 'uploading' CHECK (status IN ('uploading','pending','approved','hidden')),
  reported_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON uploads (wedding_id, status);

CREATE TABLE guestbook_entries (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  name        text NOT NULL,
  message     text,
  upload_id   uuid REFERENCES uploads(id) ON DELETE SET NULL,   -- voice note
  status      text NOT NULL DEFAULT 'visible' CHECK (status IN ('visible','hidden')),
  reported_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON guestbook_entries (wedding_id);

CREATE TABLE song_requests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  name        text,
  song        text NOT NULL,
  played_at   timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Planning tools ----------
CREATE TABLE budget_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  category    text NOT NULL,
  name        text NOT NULL,
  estimated_lkr bigint NOT NULL DEFAULT 0 CHECK (estimated_lkr >= 0),
  paid_lkr    bigint NOT NULL DEFAULT 0 CHECK (paid_lkr >= 0),
  total_lkr   bigint CHECK (total_lkr >= 0),   -- agreed price, once known
  due_date    date,
  vendor      text,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ON budget_items (wedding_id);

CREATE TABLE run_sheet_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  event_id    uuid REFERENCES events(id) ON DELETE CASCADE,
  time        text NOT NULL,             -- "10:24" (nekath times are exact, kept as typed)
  item        text NOT NULL,
  owner       text,                      -- who is responsible (name or role)
  notes       text,
  sort        int NOT NULL DEFAULT 0
);
CREATE INDEX ON run_sheet_items (wedding_id);
