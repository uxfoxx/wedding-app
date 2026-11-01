# Deploying

Three pieces, each on the host that suits it:

| Piece | What | Where (suggested) |
| --- | --- | --- |
| Web panel | Flutter web build of the app | **Netlify** (`netlify.toml`) |
| API + database | Node.js 22 + PostgreSQL 16 | **Render** (`render.yaml`), or any 1 GB VPS with Docker (`api/Dockerfile`) |
| Guest pages + photos | Static files and uploads | **Cloudflare R2** (S3-compatible) with a public domain |

The iOS and Android apps are built from the same `app/` folder and point at the API with `--dart-define=API_URL=…`.

## 1. Object storage (Cloudflare R2)

1. Create a bucket, e.g. `wedding-media`, and connect a public custom domain, e.g. `https://media.example.lk`.
2. Create an API token with read/write access to the bucket.
3. Add a CORS rule so browsers can upload directly:

```json
[{ "AllowedOrigins": ["*"], "AllowedMethods": ["PUT", "GET", "HEAD"], "AllowedHeaders": ["content-type"], "MaxAgeSeconds": 3600 }]
```

## 2. API and database (Render)

1. Render → **New → Blueprint** → choose this repository. It creates `wedding-api` and `wedding-db`.
2. Fill the environment variables marked `sync: false`:

| Variable | Example |
| --- | --- |
| `PUBLIC_API_URL` | `https://wedding-api.onrender.com` |
| `WEB_PANEL_URL` | `https://your-site.netlify.app` |
| `GUEST_BASE_URL` | `https://media.example.lk/site` |
| `MEDIA_BASE_URL` | `https://media.example.lk/media` |
| `S3_BUCKET`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | from step 1 (`S3_ENDPOINT` = `https://<account-id>.r2.cloudflarestorage.com`) |
| `ADMIN_EMAILS` | your email, to get the admin console |

3. The API runs migrations and seeds templates on start. Check `https://…/api/health`.

**Sign-in emails:** until an email provider is connected (`api/src/lib/notify.ts`), codes are only logged.
For a private demo you can set `EXPOSE_DEV_CODES=true` so the code shows on screen. Never leave that on for real users.

## 3. Web panel (Netlify)

1. Netlify → **Add new site → Import an existing project** → GitHub → this repository.
   Netlify reads `netlify.toml` (base `app`, publish `build/web`).
2. Site configuration → Environment variables → add `API_URL` = your API URL from step 2.
3. Deploy. The first build downloads Flutter (a few minutes); later builds are cached.

## 4. Phone apps

```bash
cd app && flutter build appbundle --dart-define=API_URL=https://wedding-api.onrender.com
```

```bash
cd app && flutter build ipa --dart-define=API_URL=https://wedding-api.onrender.com
```

Before store submission: set the bundle IDs, app name and icons; create the in-app product `wedding_pass` in App Store Connect and Google Play;
then add receipt verification to `POST /weddings/:id/iap` (it returns 501 until store credentials exist).

## Still to connect for a real launch

- LKR payment gateway (hosted checkout + webhook in `api/src/routes/payments.ts`; the test checkout is disabled in production)
- Email (sign-in codes, receipts) and SMS (phone OTP) providers in `api/src/lib/notify.ts`
- Google / Apple sign-in client IDs (`GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS`) and the app buttons
- WhatsApp Business Platform (optional): `WHATSAPP_BUSINESS_ENABLED`, `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, an approved template
- Nightly database backups and uptime/error monitoring
