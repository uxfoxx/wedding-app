# Build status: Phases 1, 2 and 3

Checked against the feature document. Phase 1 detail first, then Phases 2 and 3.
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

## Phase 2: planners and the guest experience

- ✅ Planner login and business profile; admin approval (one wedding allowed before approval)
- ✅ Dashboard of client weddings: date, days to go, RSVP progress, open/overdue tasks, team; archived weddings hidden
- ✅ Create a wedding for a client; invite the couple with chosen permissions; hand over ownership (planner keeps edit access)
- ✅ Who pays: planner pays at checkout, or shares the checkout with the couple
- ✅ Team: coordinators see only assigned weddings; team limits 1 / 3 / unlimited (free / paid / Studio)
- ✅ Tasks with due dates and owners, across all client weddings
- ✅ Reusable templates: save a checklist, run sheet or budget from one wedding, apply to another
- ✅ Client notes and contact (planner team only); branded printable reports (guest list, seating, run sheet, QR board)
- ✅ Studio plan: 10 or unlimited new weddings a month; covers weddings only while the subscription is paid (no resale); white-label logo on guest pages and reports
- ✅ Seating: round, long and head tables; suggested plan (families together, conflicts apart, elders and VIPs at the front, confirmed headcounts, capacity); tap-to-seat on phones, drag-and-drop in the web panel
- ✅ Find your seat on each guest's invitation, plus a seat-finder page and printable QR board for the entrance
- ✅ Live updates on every guest page, plus a WhatsApp send queue to confirmed guests
- ✅ Digital menu with allergens and diet labels
- ✅ Guest photo/video upload by QR (photos shrunk on the phone, direct to storage), couple approval before the wall, report button
- ✅ Live photo wall page for the reception screen; guestbook with voice notes; song requests for the DJ
- ✅ Keepsake page (album + guestbook) and thank-you message queue
- ✅ Budget (planned, agreed, paid, due; payment reminders), suggested checklist by months before (Buddhist, Hindu, Christian, Muslim, civil items), run sheet, readiness score with the next three steps
- ✅ RSVP message reading: paste a WhatsApp reply in English, Sinhala, Tamil or Singlish and the app suggests "2 coming, vegetarian"
- ✅ Admin: approve planners, Studio billing periods, reported photos and messages, storage per wedding
- 🟡 Push notifications for task reminders: tasks show overdue in the app; push needs Firebase/APNs keys
- 🟡 Phase 2 gate tracked in the admin stats (planners with 2+ weddings)

## Phase 3: vendor marketplace and growth

- ✅ Vendor login and business profile: category, district, service areas, languages, years, description
- ✅ Portfolio uploads (direct to storage), packages with starting prices and negotiable flag, availability calendar (booked dates hide the vendor)
- ✅ Enquiry inbox with wedding date, location, guest count, budget (only if the couple shared it); reply in the app or WhatsApp; quoted / booked / declined
- ✅ Stats: profile views, enquiries, reply time, bookings, shortlists; ask a couple for a review after the wedding
- ✅ Categories at launch: photographers, venues, decorators, caterers, makeup, bridal, DJs/bands, planners (more ready to switch on)
- ✅ Couples and planners: browse by category, district, price, language and date; "Suggested for your wedding" (district, free on date, near budget, rating, reply time)
- ✅ Shortlist, compare up to three, one enquiry to several vendors, track contacted → quoted → booked / rejected
- ✅ Booked vendors appear in the budget and run sheet automatically
- ✅ Planners keep preferred vendors
- ✅ Trust: team checks (phone, registration/NIC, original portfolio) before approval; verified reviews only from real weddings that contacted the vendor, after the date; public replies; complaints go to the team and three from real weddings hide the vendor pending review
- ✅ Featured, verified and checked are always labelled; featured slots per category
- ✅ Public vendor profile pages for social media
- ✅ Growth: "Create your own invitation" link with attribution, referrals (friend discount + credit), partner QR codes with discounts and co-branded templates, "Real weddings" showcase with permission and approval
- 🟡 WhatsApp Business automatic reminders: built and off by default (needs Meta approval, a template and a token)
- 🟡 Vendor money (featured, verified badge): set by admin after payment; self-serve checkout for vendors not built
- ⬜ Out of scope by design: booking payments, deposits, commission

## Verified (all phases)

- API: 14 test suites/cases against PostgreSQL, including end-to-end flows for each phase
- Flutter: analyzer clean, widget tests pass, web build succeeds
- Browser: couple flow (Phase 1), planner flow (dashboard → client wedding → Plan → Guest experience) and vendor flow (setup → inbox → profile) driven in Chromium against the real API
- Production mode checked: no dev codes, test checkout disabled, warning without object storage
- Not verified here: iOS/Android builds (no Xcode or Android SDK on this machine), Docker image build (no Docker daemon)

## Decisions needed from you
1. LKR payment gateway (for example PayHere) and bank account for transfers
2. Store prices and whether to offer the pass in-app (store rules require it to unlock in the apps)
3. Email and SMS providers; hosting and object storage (Cloudflare R2 or S3)
4. App name, bundle IDs, Apple/Google developer accounts, OAuth client IDs
5. Native-speaker review of all Sinhala and Tamil text
