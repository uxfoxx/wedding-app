# Wedding App

Couples, wedding planners and vendors in one app (Phases 1–3 of the feature document).
One Flutter codebase for the **iOS app, Android app and web panel**, a small **Node.js + PostgreSQL API**
built for a 1 GB server, and **static guest pages** (plain HTML, served from a CDN) that guests open from WhatsApp.

```
app/        Flutter app: iOS, Android, and the web panel (Flutter web)
api/        Node.js 22 + PostgreSQL API, job queue, guest-page publisher
  migrations/   database schema
  src/lib/      renderer (guest pages), smart import, duplicates, publisher, jobs, auth
  src/routes/   auth, weddings, guests, public (guest pages), payments, admin
  test/         unit tests + end-to-end API test against PostgreSQL
docs/STATUS.md  what is built in each phase, what is left, decisions needed
docs/DEPLOY.md  Netlify (web panel), Render (API + database), Cloudflare R2 (guest pages, photos)
```

## Run it locally

Needs Node.js 22.18+ (runs TypeScript directly), PostgreSQL 14+, and Flutter 3.x.

```bash
createuser -s wed && createdb -O wed wedding && createdb -O wed wedding_test   # password: wed
```

```bash
cd api && npm install && npm start
```

The API listens on http://localhost:8080. It creates the schema, seeds templates and wording,
serves published guest pages at `/site/…` and, once built, the web panel at `/panel/`.
In development, sign-in codes are shown on screen instead of being emailed.

```bash
cd app && flutter pub get && flutter build web --base-href /panel/
```

Then open http://localhost:8080/panel/. For the phone apps:

```bash
cd app && flutter run --dart-define=API_URL=http://<your-computer-ip>:8080
```

To make yourself an admin, start the API with `ADMIN_EMAILS=you@example.com` and sign in with that email.

## Tests

```bash
cd api && npm test
```

```bash
cd app && flutter analyze && flutter test
```

## Production settings (API)

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection |
| `PUBLIC_API_URL` | Public URL of the API (used in links) |
| `GUEST_BASE_URL` | CDN URL where guest pages are served |
| `WEB_PANEL_URL` | Web panel URL (sign-in links, "Create your own invitation") |
| `STORAGE_DIR` | Local storage folder (replace with S3/R2 client, see docs) |
| `GATEWAY_SECRET` | Payment gateway webhook signing secret (required) |
| `PREVIEW_SECRET` | Signs preview links (required) |
| `GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS` | OAuth client IDs for Google / Apple sign-in |
| `ADMIN_EMAILS` | Emails that get the admin role |
| `PASS_WEB_LKR`, `PASS_APP_LKR`, `FREE_GUEST_LIMIT` | Prices and free-plan limit |
| `EXPOSE_DEV_CODES` | Must be `false` in production (default when `NODE_ENV=production`) |
