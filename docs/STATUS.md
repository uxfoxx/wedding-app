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
- ✅ 17 templates as data (5 free, 12 premium with envelope/curtain/scroll openings), covering traditional, church, Nikah, Kovil, modern, minimal and homecoming; staff add more in the admin console without an app update
- ✅ Names, parents, message, dress code, venue, maps, add-to-calendar, countdown, programme, music, gallery links
- ✅ Wording library in three languages (26 launch wordings), filled with names, date and venue. Each wording has a tone and a faith: a wedding is only offered wording for its own faith (civil gets none of the religious ones, mixed gets all), plus homecoming or engagement wording when it has that event
- ✅ Preview as a guest, using the same renderer as the published page
- ✅ Cover photo (Easy and Advanced), gallery of up to 12 photos and background music (Advanced) uploaded straight to storage, with phones shrinking photos first; replaced or removed files are deleted

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
- ✅ Export CSV and a printable guest list and headcount (saved as PDF from the browser) for the venue/caterer, both Wedding Pass

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
- ✅ Templates and wording edited in the admin console (colours, fonts, ornament, opening, faith, tone, publish/hide)

## Platform
- ✅ Every request checks the person's role on the wedding; strangers get 404
- ✅ Database job queue (debounced republish), PDPA purge of guest phone numbers 12 months after the wedding, account deletion
- ✅ Rate limits on sign-in and guest endpoints, CSV-injection protection, escaped user content on guest pages
- ✅ Production storage: S3/R2 client with presigned uploads (`S3_*` settings). 🟡 CDN purge for changed guest pages depends on the CDN chosen
- ⬜ Email/SMS providers (interface in `api/src/lib/notify.ts`)
- ⬜ Nightly backups, error tracking, uptime checks (architecture decision 8)
- ✅ Offline copy: the open wedding and its guest list are kept on the phone and shown, read-only with a banner, when there is no connection; removed on sign-out
- ✅ Staff two-factor sign-in with an authenticator app (TOTP, secret encrypted, codes single-use, re-asked every 12 hours and on each new device; admins can reset a lost phone). Required by default in production
- 🟡 Accessibility: section titles are now marked as headings for screen readers; a pass with VoiceOver/TalkBack on real phones is still owed

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
- ✅ Vendor money: vendors buy featured placement (by the month, within the category's slots) or the 12-month verified badge in the web panel, by card or bank transfer; refunds take back exactly what was bought. Off until `VENDOR_PROMOTIONS=on`, and never offered in the phone apps (store rules)
- ⬜ Out of scope by design: booking payments, deposits, commission

## Verified (all phases)

- API: 17 test suites/cases against PostgreSQL, including end-to-end flows for each phase, wording by faith, invitation uploads, staff two-factor and vendor payments
- Flutter: analyzer clean, widget tests pass, web build succeeds
- Browser: couple flow (Phase 1), planner flow (dashboard → client wedding → Plan → Guest experience) and vendor flow (setup → inbox → profile) driven in Chromium against the real API
- Production mode checked: no dev codes, test checkout disabled, warning without object storage
- iOS: built and run on the iPhone 17 Pro simulator. Not verified here: Android build (no Android SDK), Docker image build (no Docker daemon)

## Decisions needed from you
1. LKR payment gateway (for example PayHere) and bank account for transfers
2. Store prices and whether to offer the pass in-app (store rules require it to unlock in the apps)
3. Email and SMS providers; hosting and object storage (Cloudflare R2 or S3)
4. App name, bundle IDs, Apple/Google developer accounts, OAuth client IDs
5. Native-speaker review of all Sinhala and Tamil text
