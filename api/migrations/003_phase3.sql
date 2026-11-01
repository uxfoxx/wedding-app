-- Phase 3: vendor marketplace and growth.

CREATE TABLE vendor_categories (
  id            text PRIMARY KEY,
  name          text NOT NULL,
  active        boolean NOT NULL DEFAULT true,
  featured_slots int NOT NULL DEFAULT 3,
  sort          int NOT NULL DEFAULT 0
);

CREATE TABLE vendors (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL REFERENCES users(id),
  slug            text NOT NULL UNIQUE,
  business_name   text NOT NULL,
  category        text NOT NULL REFERENCES vendor_categories(id),
  district        text NOT NULL,
  service_areas   text[] NOT NULL DEFAULT '{}',   -- districts served
  languages       text[] NOT NULL DEFAULT '{}',   -- en / si / ta
  years_active    int,
  phone           text,
  whatsapp        text,
  description     text,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending','approved','under_review','suspended')),
  -- Checks done by the team before approval.
  phone_verified        boolean NOT NULL DEFAULT false,
  registration_checked  boolean NOT NULL DEFAULT false,
  portfolio_checked     boolean NOT NULL DEFAULT false,
  verified_until  timestamptz,      -- paid annual "verified" badge
  featured_until  timestamptz,      -- paid featured placement
  approved_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ON vendors (owner_id);
CREATE INDEX ON vendors (category, status);

CREATE TABLE vendor_media (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id     uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('photo','video')),
  path          text NOT NULL UNIQUE,
  content_type  text NOT NULL,
  size_bytes    int,
  caption       text,
  upload_token  text NOT NULL UNIQUE,
  ready         boolean NOT NULL DEFAULT false,
  sort          int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE vendor_packages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id     uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  name          text NOT NULL,
  includes      text,
  addons        text,
  starting_lkr  bigint NOT NULL CHECK (starting_lkr >= 0),
  negotiable    boolean NOT NULL DEFAULT true,
  sort          int NOT NULL DEFAULT 0
);

CREATE TABLE vendor_blocked_dates (
  vendor_id  uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  day        date NOT NULL,
  PRIMARY KEY (vendor_id, day)
);

CREATE TABLE vendor_views (
  vendor_id  uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  day        date NOT NULL DEFAULT current_date,
  views      int NOT NULL DEFAULT 0,
  PRIMARY KEY (vendor_id, day)
);

-- One enquiry per (wedding, vendor). It carries the wedding's details so nobody explains twice.
CREATE TABLE enquiries (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id      uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  wedding_id     uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  sender_id      uuid NOT NULL REFERENCES users(id),
  wedding_date   timestamptz,
  location       text,
  guest_count    int,
  budget_lkr     bigint,              -- only if the couple chose to share it
  vendor_status  text NOT NULL DEFAULT 'new' CHECK (vendor_status IN ('new','quoted','booked','declined')),
  couple_status  text NOT NULL DEFAULT 'contacted' CHECK (couple_status IN ('contacted','quoted','booked','rejected')),
  first_reply_at timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (vendor_id, wedding_id)
);
CREATE INDEX ON enquiries (wedding_id);

CREATE TABLE enquiry_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enquiry_id  uuid NOT NULL REFERENCES enquiries(id) ON DELETE CASCADE,
  from_side   text NOT NULL CHECK (from_side IN ('couple','vendor')),
  author_id   uuid REFERENCES users(id),
  body        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ON enquiry_messages (enquiry_id);

CREATE TABLE shortlists (
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  vendor_id   uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  note        text,
  added_by    uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (wedding_id, vendor_id)
);

CREATE TABLE planner_preferred_vendors (
  planner_id  uuid NOT NULL REFERENCES planners(id) ON DELETE CASCADE,
  vendor_id   uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  PRIMARY KEY (planner_id, vendor_id)
);

-- Verified reviews only: from a real wedding that contacted the vendor, after the wedding date.
CREATE TABLE reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id   uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES users(id),
  rating      int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body        text,
  reply       text,
  replied_at  timestamptz,
  status      text NOT NULL DEFAULT 'visible' CHECK (status IN ('visible','hidden')),
  reported_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (vendor_id, wedding_id)
);

CREATE TABLE vendor_complaints (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id   uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  wedding_id  uuid NOT NULL REFERENCES weddings(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL REFERENCES users(id),
  body        text NOT NULL,
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','upheld','dismissed')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (vendor_id, wedding_id)
);

-- ---------- Growth ----------
-- Referrals: a couple's code gives a friend a discount and the referrer a credit.
CREATE TABLE referral_codes (
  code      text PRIMARY KEY,
  user_id   uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE
);
CREATE TABLE credits (
  id          bigserial PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_lkr  int NOT NULL,              -- positive = earned, negative = spent
  reason      text NOT NULL,
  payment_id  uuid REFERENCES payments(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON credits (user_id);

-- Partner codes: venues, photographers and salons hand out QR codes with a discount,
-- optionally unlocking a co-branded template.
CREATE TABLE partner_codes (
  code          text PRIMARY KEY,
  partner_name  text NOT NULL,
  vendor_id     uuid REFERENCES vendors(id) ON DELETE SET NULL,
  discount_lkr  int NOT NULL DEFAULT 0 CHECK (discount_lkr >= 0),
  template_id   text REFERENCES templates(id),
  active        boolean NOT NULL DEFAULT true,
  uses          int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE templates ADD COLUMN partner_code text REFERENCES partner_codes(code);

ALTER TABLE weddings
  ADD COLUMN referral_code text REFERENCES referral_codes(code),
  ADD COLUMN partner_code text REFERENCES partner_codes(code),
  ADD COLUMN source_slug text,                      -- signed up from another wedding's guest page
  ADD COLUMN showcase text NOT NULL DEFAULT 'off' CHECK (showcase IN ('off','requested','approved'));

ALTER TABLE payments
  ADD COLUMN list_price_lkr int,
  ADD COLUMN discount_lkr int NOT NULL DEFAULT 0,
  ADD COLUMN credits_lkr int NOT NULL DEFAULT 0,
  ADD COLUMN discount_reason text;

ALTER TABLE payments DROP CONSTRAINT payments_product_check;
ALTER TABLE payments ADD CONSTRAINT payments_product_check CHECK (product IN ('wedding_pass','design_for_me','vendor_featured','vendor_verified'));
ALTER TABLE payments ALTER COLUMN wedding_id DROP NOT NULL;
ALTER TABLE payments ADD COLUMN vendor_id uuid REFERENCES vendors(id);
