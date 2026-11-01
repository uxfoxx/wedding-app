-- Phase 1 schema. Every wedding-scoped record carries wedding_id (architecture decision 5).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text UNIQUE,
  phone         text UNIQUE,              -- E.164
  name          text,
  google_sub    text UNIQUE,
  apple_sub     text UNIQUE,
  locale        text NOT NULL DEFAULT 'en' CHECK (locale IN ('en','si','ta')),
  staff_role    text CHECK (staff_role IN ('admin','support','designer')),
  blocked_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- One-time sign-in codes (email link / phone OTP). Only hashes are stored.
CREATE TABLE auth_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel     text NOT NULL CHECK (channel IN ('email','phone')),
  address     text NOT NULL,
  code_hash   text NOT NULL,
  link_hash   text,
  attempts    int  NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON auth_codes (channel, address, created_at DESC);

CREATE TABLE sessions (
  token_hash  text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);

CREATE TABLE templates (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  category    text NOT NULL,             -- traditional, church, nikah, kovil, modern, minimal, homecoming
  premium     boolean NOT NULL DEFAULT false,
  layout      jsonb NOT NULL,            -- colours, fonts, ornament, animation (templates are data)
  published   boolean NOT NULL DEFAULT true,
  sort        int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wordings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  language    text NOT NULL CHECK (language IN ('en','si','ta')),
  tone        text NOT NULL CHECK (tone IN ('formal','modern','religious','casual')),
  event_kind  text NOT NULL DEFAULT 'wedding',
  body        text NOT NULL,             -- with {couple}, {date}, {venue}, {parents} fields
  published   boolean NOT NULL DEFAULT true
);

CREATE TABLE weddings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL REFERENCES users(id),
  kind            text NOT NULL DEFAULT 'wedding' CHECK (kind IN ('wedding','engagement','homecoming','other')),
  partner1        text NOT NULL,
  partner2        text NOT NULL,
  wedding_type    text NOT NULL DEFAULT 'buddhist' CHECK (wedding_type IN ('buddhist','hindu','muslim','christian','civil','mixed')),
  district        text,
  expected_guests int,
  mode            text NOT NULL DEFAULT 'easy' CHECK (mode IN ('easy','advanced')),
  language        text NOT NULL DEFAULT 'en' CHECK (language IN ('en','si','ta')),
  plan            text NOT NULL DEFAULT 'free' CHECK (plan IN ('free','pass')),
  paid_at         timestamptz,
  template_id     text REFERENCES templates(id),
  invitation      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- editable content: message, parents, dress code, photos, music...
  slug            text NOT NULL UNIQUE,                 -- random, no names (decision 5)
  open_link_token text UNIQUE,                          -- optional group link
  published_at    timestamptz,
  contacts_purged_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE wedding_members (
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('owner','edit_all','edit_guests','view')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (wedding_id, user_id)
);

CREATE TABLE member_invites (
  token_hash  text PRIMARY KEY,
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('edit_all','edit_guests','view')),
  created_by  uuid NOT NULL REFERENCES users(id),
  expires_at  timestamptz NOT NULL,
  accepted_by uuid REFERENCES users(id),
  accepted_at timestamptz
);

CREATE TABLE events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('poruwa','church','nikah','kovil','registration','reception','homecoming','engagement','other')),
  title       text,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz,
  nekath      text,                      -- auspicious time note, e.g. "Poruwa at 10:24 am"
  venue       text,
  address     text,
  maps_url    text,
  dress_code  text,
  programme   jsonb NOT NULL DEFAULT '[]'::jsonb,
  sort        int NOT NULL DEFAULT 0
);
CREATE INDEX ON events (wedding_id);

CREATE TABLE guests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  name        text NOT NULL,
  title       text,
  phone       text,                      -- E.164, purged 12 months after the wedding (PDPA)
  side        text CHECK (side IN ('bride','groom','both')),
  group_name  text,                      -- family, friends, colleagues...
  vip         boolean NOT NULL DEFAULT false,
  seats       int NOT NULL DEFAULT 1 CHECK (seats BETWEEN 1 AND 30),
  dietary     text,
  notes       text,
  tags        text[] NOT NULL DEFAULT '{}',
  token       text NOT NULL UNIQUE,      -- long random, revocable
  source      text NOT NULL DEFAULT 'manual',
  sent_at     timestamptz,               -- handed to WhatsApp/SMS (not proof of delivery)
  opened_at   timestamptz,               -- from JS beacon only, so link-preview crawlers don't count
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()  -- keeps import order within one transaction
);
CREATE INDEX ON guests (wedding_id);
CREATE INDEX ON guests (wedding_id, phone);

CREATE TABLE guest_events (
  guest_id  uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  event_id  uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  PRIMARY KEY (guest_id, event_id)
);

CREATE TABLE rsvps (
  guest_id    uuid NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  event_id    uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  status      text NOT NULL CHECK (status IN ('coming','not_coming','maybe')),
  headcount   int NOT NULL DEFAULT 0 CHECK (headcount BETWEEN 0 AND 30),
  meal        text,
  dietary     text,
  message     text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (guest_id, event_id)
);

CREATE TABLE payments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id   uuid NOT NULL REFERENCES weddings(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  product      text NOT NULL CHECK (product IN ('wedding_pass','design_for_me')),
  method       text NOT NULL CHECK (method IN ('gateway','bank_transfer','app_store','play_store','admin_grant')),
  amount_lkr   int NOT NULL,
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','refunded')),
  reference    text NOT NULL UNIQUE,     -- shown to the user for bank transfers
  external_id  text,
  approved_by  uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  paid_at      timestamptz,
  refunded_at  timestamptz
);
CREATE INDEX ON payments (wedding_id);

CREATE TABLE design_jobs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  brief       jsonb NOT NULL,
  status      text NOT NULL DEFAULT 'awaiting_payment' CHECK (status IN ('awaiting_payment','queued','in_progress','review','approved','cancelled')),
  designer_id uuid REFERENCES users(id),
  messages    jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Database-backed job queue (no Redis on a 1 GB server).
CREATE TABLE jobs (
  id          bigserial PRIMARY KEY,
  type        text NOT NULL,
  key         text,                      -- de-duplicates pending jobs, e.g. publish:<wedding>
  payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
  run_at      timestamptz NOT NULL DEFAULT now(),
  attempts    int NOT NULL DEFAULT 0,
  locked_at   timestamptz,
  done_at     timestamptz,
  error       text
);
CREATE UNIQUE INDEX jobs_pending_key ON jobs (key) WHERE done_at IS NULL;
CREATE INDEX ON jobs (run_at) WHERE done_at IS NULL;

CREATE TABLE audit_log (
  id          bigserial PRIMARY KEY,
  actor_id    uuid REFERENCES users(id),
  action      text NOT NULL,
  target      text,
  details     jsonb NOT NULL DEFAULT '{}'::jsonb,
  at          timestamptz NOT NULL DEFAULT now()
);
