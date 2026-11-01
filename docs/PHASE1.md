# Phase 1 status

Checked against "Phase 1 — Launch: the couple app" in the feature document.
✅ built and tested · 🟡 built, needs a provider account or more work · ⬜ not started

## Accounts and wedding setup
- ✅ Email sign-in (6-digit code or link); phone OTP (SMS provider stubbed: logs in development)
- 🟡 Google and Apple sign-in: server verification built (`POST /api/auth/google|apple`); app buttons need OAuth client IDs and the `google_sign_in` / `sign_in_with_apple` packages
- ✅ Wedding profile, wedding type, district, multiple events (Poruwa, church, Nikah, Kovil, registration, reception, homecoming, engagement), nekath time, programme
- ✅ Co-owners with view / edit guests / edit everything, by invite link
- ✅ Easy and Advanced Mode (4 fixed tabs; Plan added in Advanced; suggestion at 150+ guests or 2+ events)
- ✅ App language: English, Sinhala, Tamil (🟡 Sinhala/Tamil text needs native review; some app screens fall back to English)

## Invitation builder
- 🟡 12 templates as data (5 free, 7 premium with envelope/curtain/scroll openings). The document asks for 15–20; more can be added in the admin API without an app update
- ✅ Names, parents, message, dress code, venue, maps, add-to-calendar, countdown, programme, music, gallery links
- ✅ Wording library in three languages, filled with names, date and venue
- ✅ Preview as a guest, using the same renderer as the published page
- 🟡 Photos and music are links for now. Next: signed direct uploads to object storage (architecture decision 4), with phones shrinking images first

## Guests
- ✅ Add by hand; paste a WhatsApp list (smart import, including Singlish words like "denek", "elawalu"); Excel/CSV; phone contacts (couple ticks who to import)
- ✅ Sides, groups, VIP, seats, dietary needs, notes, per-event invitations (Advanced)
- ✅ Duplicate detection (same phone / near-identical name) and merge
- ✅ Revoke a guest's link and issue a new one

## Sending and RSVPs
- ✅ Personal link per guest (random token in the URL fragment, no names or numbers in the URL)
- ✅ WhatsApp send queue (one tap per guest, from the couple's own WhatsApp), SMS, copy link
- ✅ Open group link: guests type their name; matched or added for review
- ✅ RSVP per event: coming / not coming / maybe, headcount within seats, meal, dietary needs, message
- ✅ Opened tracking from the page's script only (WhatsApp's link-preview crawler doesn't count)
- ✅ RSVP dashboard per event, meal counts, follow-up list (7 days, VIPs first for a call), reminders
- ✅ Export CSV for the venue/caterer (Wedding Pass). 🟡 PDF export: planned as print-to-PDF on the device

## Guest page
- ✅ Static HTML on the CDN, ~24 KB before fonts and photos; per-guest JSON beside it
- ✅ Three languages with a switcher, large text and tap targets, works without login
- 🟡 Date text appeared in English in a headless browser even with Sinhala chosen; check on real phones

## Payments
- ✅ Free plan limits enforced on the server (50 guests, 1 event, free designs, branding, no export)
- ✅ Web checkout through a gateway (signed webhook unlocks the wedding) and bank transfer (admin confirms)
- 🟡 Gateway is a test stand-in. Next: pick the LKR gateway and plug in its hosted checkout and webhook format
- 🟡 In-app purchase in the iOS/Android apps is wired with `in_app_purchase` (product id `wedding_pass`); server receipt verification returns 501 until App Store / Play credentials exist
- ✅ Receipts by email (provider stubbed). ✅ Refund rule (7 days, nothing sent) enforced, with audited override

## Admin console
- ✅ Daily stats and Phase 1 gate progress, look up users/weddings/payments, confirm transfers, refund, free upgrade, block users, take down pages, design-job queue, audit log, failed jobs
- ✅ Templates and wording managed through the admin API. 🟡 No admin screens for editing them yet

## Platform
- ✅ Every request checks the person's role on the wedding; strangers get 404
- ✅ Database job queue (debounced republish), PDPA purge of guest phone numbers 12 months after the wedding, account deletion
- ✅ Rate limits on sign-in and guest endpoints, CSV-injection protection, escaped user content on guest pages
- ⬜ Production storage: S3/R2 client + CDN purge (interface in `api/src/lib/storage.ts`)
- ⬜ Email/SMS providers (interface in `api/src/lib/notify.ts`)
- ⬜ Nightly backups, error tracking, uptime checks (architecture decision 8)
- ⬜ Offline copy of the guest list on the phone
- ⬜ Staff two-factor sign-in
- 🟡 Accessibility: Flutter merges some screen text into nearby fields' labels. Add explicit `Semantics` headers

## Verified
- API: 8 tests (smart import, phones, duplicates, full couple flow from sign-up to payment and admin, privacy purge)
- Flutter: analyzer clean; widget test of sign-in → first run → Easy Mode home
- Browser: web panel driven through sign-in, wedding setup, design, wording, publish, paste import, send queue; guest page opened, RSVP sent in Sinhala, dashboard updated
- Not verified here: iOS and Android builds (this machine has no Android SDK or Xcode)

## Decisions needed from you
1. LKR payment gateway (for example PayHere) and bank account for transfers
2. Store prices and whether to offer the pass in-app (store rules require it to unlock in the apps)
3. Email and SMS providers; hosting and object storage (Cloudflare R2 or S3)
4. App name, bundle IDs, Apple/Google developer accounts, OAuth client IDs
5. Native-speaker review of all Sinhala and Tamil text
