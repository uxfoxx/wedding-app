// Phase 3 end to end: vendor onboarding and review, directory search, suggestions, shortlist,
// multi-vendor enquiry, vendor inbox, booking → budget + run sheet, verified reviews, complaints,
// featured/verified labels, referrals with credits, partner codes with co-branded templates, showcase.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pool } from '../src/db.ts';
import { config } from '../src/config.ts';
import { migrate } from '../src/migrate.ts';
import { seed } from '../src/seed.ts';
import { buildApp } from '../src/app.ts';
import { runDueJobs } from '../src/lib/jobs.ts';
import { signWebhook } from '../src/routes/payments.ts';
import type { FastifyInstance } from 'fastify';

let app: FastifyInstance;
async function call(method: string, url: string, token?: string, body?: unknown) {
  const r = await app.inject({ method: method as any, url: '/api' + url, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) }, payload: body !== undefined ? JSON.stringify(body) : undefined });
  return { status: r.statusCode, body: (r.headers['content-type']?.includes('json') ? r.json() : r.body) as any };
}
async function signIn(email: string) {
  const s = await call('POST', '/auth/email/start', undefined, { email });
  return (await call('POST', '/auth/email/verify', undefined, { email, code: s.body.devCode })).body.token as string;
}
const png = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000', 'hex');

async function makeVendor(email: string, name: string, category: string, district: string, price: number) {
  const t = await signIn(email);
  const v = await call('POST', '/vendors', t, { business_name: name, category, district, service_areas: [district, 'Gampaha'], languages: ['si', 'en'], phone: '0771234567', years_active: 6 });
  assert.equal(v.status, 200, JSON.stringify(v.body));
  assert.equal((await call('POST', '/vendor/submit', t)).body.error, 'portfolio_too_small');
  for (let i = 0; i < 3; i++) {
    const m = await call('POST', '/vendor/media', t, { content_type: 'image/png', size: png.length, caption: `Wedding ${i}` });
    const put = await app.inject({ method: 'PUT', url: new URL(m.body.upload_url).pathname, headers: { 'content-type': 'image/png' }, payload: png });
    assert.equal(put.statusCode, 200);
    assert.equal((await call('POST', `/vendor/media/${m.body.id}/complete`, t)).status, 200);
  }
  await call('POST', '/vendor/packages', t, { name: 'Full day', includes: '2 photographers, album', starting_lkr: price });
  assert.equal((await call('POST', '/vendor/submit', t)).body.status, 'pending');
  return { token: t, id: v.body.vendor.id as string, slug: v.body.vendor.slug as string };
}

before(async () => {
  assert.match(config.databaseUrl, /wedding_test/);
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  await seed();
  app = await buildApp();
  config.adminEmails.push('admin3@example.com');
});
after(async () => { await app.close(); await pool.end(); });

test('Phase 3: marketplace and growth', async () => {
  const admin = await signIn('admin3@example.com');
  const lens = await makeVendor('lens@example.com', 'Lens & Light', 'photographers', 'Colombo', 150000);
  const pricey = await makeVendor('pricey@example.com', 'Grand Studio', 'photographers', 'Colombo', 450000);
  const kandy = await makeVendor('kandy@example.com', 'Hill Photos', 'photographers', 'Kandy', 120000);

  // Not visible until the team checks and approves.
  assert.equal((await call('GET', '/vendors?category=photographers')).body.vendors.length, 0);
  assert.equal((await call('POST', `/admin/vendors/${lens.id}/status`, admin, { status: 'approved', reason: 'ok' })).body.error, 'checks_missing');
  for (const v of [lens, pricey, kandy]) {
    await call('POST', `/admin/vendors/${v.id}/checks`, admin, { phone_verified: true, portfolio_checked: true, registration_checked: true });
    assert.equal((await call('POST', `/admin/vendors/${v.id}/status`, admin, { status: 'approved', reason: 'checked' })).status, 200);
  }
  await pool.query('UPDATE jobs SET run_at=now() WHERE done_at IS NULL');
  await runDueJobs();
  const page = await readFile(join(config.storageDir, 'site', 'vendors', `${lens.slug}.html`), 'utf8');
  assert.match(page, /Lens &amp; Light/);

  // Couple: referred by a friend.
  const friend = await signIn('friend@example.com');
  const ref = (await call('GET', '/me/referral', friend)).body;
  assert.equal(ref.code.length, 6);
  const couple = await signIn('couple3@example.com');
  const w = (await call('POST', '/weddings', couple, { partner1: 'Saman', partner2: 'Ishara', district: 'Colombo', code: ref.code, event: { starts_at: '2027-08-15T04:30:00Z', venue: 'Taj Samudra' } })).body;
  const W = w.wedding.id;

  // Directory filters.
  const all = (await call('GET', '/vendors?category=photographers&district=Colombo')).body.vendors;
  assert.deepEqual(all.map((v: any) => v.business_name).sort(), ['Grand Studio', 'Lens & Light']);
  assert.equal((await call('GET', '/vendors?category=photographers&max_price=200000')).body.vendors.length, 2);
  await call('PUT', '/vendor/availability', lens.token, { days: ['2027-08-15'] });
  assert.ok(!(await call('GET', '/vendors?category=photographers&date=2027-08-15')).body.vendors.some((v: any) => v.business_name === 'Lens & Light'), 'booked dates hide the vendor');
  await call('PUT', '/vendor/availability', lens.token, { days: ['2027-08-15'], blocked: false });

  // Suggestions: district + date + budget.
  await call('POST', `/admin/weddings/${W}/grant-pass`, admin, { reason: 'test' });
  await call('POST', `/weddings/${W}/budget`, couple, { category: 'Photography', name: 'Photographer', estimated_lkr: 180000 });
  const sug = (await call('GET', `/weddings/${W}/vendor-suggestions?category=photographers`, couple)).body;
  assert.equal(sug.vendors[0].business_name, 'Lens & Light', 'fits the budget first');
  assert.equal(sug.vendors.find((v: any) => v.business_name === 'Grand Studio').fits_budget, false);
  assert.ok(!sug.vendors.some((v: any) => v.business_name === 'Hill Photos'), 'does not serve Colombo');

  // Profile view counts, shortlist, one enquiry to two vendors.
  const prof = (await call('GET', `/vendors/${lens.slug}`)).body;
  assert.equal(prof.packages[0].starting_lkr, '150000');
  await call('PUT', `/weddings/${W}/shortlist/${pricey.id}`, couple);
  const enq = await call('POST', `/weddings/${W}/enquiries`, couple, { vendor_ids: [lens.id, pricey.id], message: 'Are you free on our date?', share_budget: false });
  assert.equal(enq.body.sent, 2);
  assert.equal((await call('GET', `/weddings/${W}/shortlist`, couple)).body.vendors.length, 2);

  // Vendor inbox: wedding details arrive with the enquiry; budget only if shared.
  const inbox = (await call('GET', '/vendor/enquiries', lens.token)).body.enquiries;
  assert.equal(inbox.length, 1);
  assert.match(inbox[0].location, /Taj Samudra/);
  assert.equal(inbox[0].budget_lkr, null);
  const det = (await call('GET', `/vendor/enquiries/${inbox[0].id}`, lens.token)).body;
  assert.equal(det.messages[0].body, 'Are you free on our date?');
  await call('POST', `/vendor/enquiries/${inbox[0].id}/reply`, lens.token, { body: 'Yes! Our full-day package is LKR 150,000.' });
  await call('PATCH', `/vendor/enquiries/${inbox[0].id}`, lens.token, { status: 'quoted' });
  const st = (await call('GET', '/vendor/stats', lens.token)).body;
  assert.equal(st.views_30d, 1);
  assert.ok(st.reply_hours !== null);
  assert.equal((await call('POST', `/vendor/enquiries/${inbox[0].id}/request-review`, lens.token)).body.error, 'too_early');

  // Couple books → vendor appears in the budget and run sheet.
  const mine = (await call('GET', `/weddings/${W}/enquiries`, couple)).body.enquiries;
  const lensEnq = mine.find((e: any) => e.business_name === 'Lens & Light');
  assert.equal(lensEnq.messages.length, 2);
  await call('PATCH', `/weddings/${W}/enquiries/${lensEnq.id}`, couple, { status: 'booked', price_lkr: 150000 });
  assert.ok((await call('GET', `/weddings/${W}/budget`, couple)).body.items.some((i: any) => i.vendor === 'Lens & Light' && Number(i.total_lkr) === 150000));
  assert.ok((await call('GET', `/weddings/${W}/run-sheet`, couple)).body.items.some((i: any) => i.owner === 'Lens & Light'));

  // Reviews: only after the wedding, only from weddings that contacted the vendor.
  assert.equal((await call('POST', `/weddings/${W}/reviews`, couple, { vendor_id: lens.id, rating: 5, body: 'Wonderful' })).body.error, 'too_early');
  assert.equal((await call('POST', `/weddings/${W}/reviews`, couple, { vendor_id: kandy.id, rating: 1 })).body.error, 'not_contacted');
  await pool.query(`UPDATE events SET starts_at = now() - interval '3 days' WHERE wedding_id=$1`, [W]);
  assert.equal((await call('POST', `/weddings/${W}/reviews`, couple, { vendor_id: lens.id, rating: 5, body: 'Wonderful photos!' })).status, 200);
  await call('POST', `/vendor/reviews/${(await call('GET', '/vendor/reviews', lens.token)).body.reviews[0].id}/reply`, lens.token, { reply: 'Thank you!' });
  const card = (await call('GET', '/vendors?category=photographers')).body.vendors.find((v: any) => v.business_name === 'Lens & Light');
  assert.deepEqual([card.rating, card.reviews], [5, 1]);
  // A free wedding that never sent invitations can't review (fake-wedding protection).
  const fake = await signIn('fake@example.com');
  const fw = (await call('POST', '/weddings', fake, { partner1: 'F', partner2: 'K', event: { starts_at: '2026-01-01T04:00:00Z' } })).body;
  await call('POST', `/weddings/${fw.wedding.id}/enquiries`, fake, { vendor_ids: [pricey.id], message: 'hi' });
  assert.equal((await call('POST', `/weddings/${fw.wedding.id}/reviews`, fake, { vendor_id: pricey.id, rating: 1 })).body.error, 'not_verified');

  // Featured and verified are labelled; featured comes first.
  await call('POST', `/admin/vendors/${pricey.id}/promotion`, admin, { kind: 'featured', months: 1 });
  await call('POST', `/admin/vendors/${pricey.id}/promotion`, admin, { kind: 'verified', months: 12 });
  const list = (await call('GET', '/vendors?category=photographers')).body.vendors;
  assert.equal(list[0].business_name, 'Grand Studio');
  assert.equal(list[0].featured, true);
  assert.equal(list[0].verified_badge, true);

  // Complaints: three from real weddings hide the vendor pending review; one doesn't.
  for (let i = 0; i < 3; i++) {
    const t = await signIn(`c${i}@example.com`);
    const ww = (await call('POST', '/weddings', t, { partner1: `A${i}`, partner2: 'B', event: { starts_at: '2027-01-01T04:00:00Z' } })).body.wedding.id;
    await call('POST', `/admin/weddings/${ww}/grant-pass`, admin, { reason: 'test' });
    await call('POST', `/weddings/${ww}/enquiries`, t, { vendor_ids: [kandy.id], message: 'hello' });
    await call('POST', `/weddings/${ww}/complaints`, t, { vendor_id: kandy.id, body: 'Never showed up' });
    const status = (await pool.query('SELECT status FROM vendors WHERE id=$1', [kandy.id])).rows[0].status;
    assert.equal(status, i < 2 ? 'approved' : 'under_review');
  }
  const comps = (await call('GET', '/admin/vendor-complaints', admin)).body.complaints;
  for (const c of comps) await call('POST', `/admin/vendor-complaints/${c.id}`, admin, { status: 'dismissed' });
  assert.equal((await pool.query('SELECT status FROM vendors WHERE id=$1', [kandy.id])).rows[0].status, 'approved');

  // Referral: friend's code gives LKR 1,000 off; the friend earns a credit when it's paid.
  const couple2 = await signIn('couple4@example.com');
  const w2 = (await call('POST', '/weddings', couple2, { partner1: 'Ruwan', partner2: 'Malsha', code: ref.code, event: { starts_at: '2027-10-01T04:00:00Z' } })).body.wedding.id;
  const quote = (await call('GET', `/weddings/${w2}/quote`, couple2)).body;
  assert.deepEqual([quote.list, quote.discount, quote.total], [7900, 1000, 6900]);
  const co = (await call('POST', `/weddings/${w2}/checkout`, couple2, { product: 'wedding_pass' })).body;
  assert.equal(co.amount_lkr, 6900);
  const hook = JSON.stringify({ reference: co.reference, amount_lkr: 6900, status: 'paid' });
  await app.inject({ method: 'POST', url: '/api/payments/webhook', headers: { 'content-type': 'application/json', 'x-signature': signWebhook(hook) }, payload: hook });
  assert.equal((await call('GET', '/me/referral', friend)).body.credits_lkr, 1000);
  // The friend uses the credit on their own wedding.
  const fw2 = (await call('POST', '/weddings', friend, { partner1: 'Friend', partner2: 'Partner', event: { starts_at: '2027-12-01T04:00:00Z' } })).body.wedding.id;
  const q2 = (await call('GET', `/weddings/${fw2}/quote`, friend)).body;
  assert.deepEqual([q2.credits, q2.total], [1000, 6900]);
  const co2 = (await call('POST', `/weddings/${fw2}/checkout`, friend, { product: 'wedding_pass' })).body;
  const hook2 = JSON.stringify({ reference: co2.reference, amount_lkr: 6900, status: 'paid' });
  await app.inject({ method: 'POST', url: '/api/payments/webhook', headers: { 'content-type': 'application/json', 'x-signature': signWebhook(hook2) }, payload: hook2 });
  assert.equal((await call('GET', '/me/referral', friend)).body.credits_lkr, 0, 'credit spent');

  // Partner code: discount and a co-branded template only its couples can pick.
  await call('PUT', '/admin/templates/taj-partner', admin, { name: 'Taj Samudra Classic', category: 'traditional', premium: true, layout: { palette: { bg: '#ffffff', surface: '#ffffff', ink: '#111111', accent: '#8a6d3b', muted: '#666666' }, headingFont: 'serif', ornament: 'arch', animation: 'curtain', hero: 'photo' } });
  const pc = await call('PUT', '/admin/partner-codes/TAJ2027', admin, { partner_name: 'Taj Samudra', discount_lkr: 1500, template_id: 'taj-partner' });
  assert.match(pc.body.qr_link, /#code=TAJ2027/);
  assert.equal((await call('GET', '/public/partner/taj2027')).body.partner.discount_lkr, 1500);
  const pcCouple = await signIn('tajcouple@example.com');
  const w3 = (await call('POST', '/weddings', pcCouple, { partner1: 'Nuwan', partner2: 'Sachini', code: 'TAJ2027', event: { starts_at: '2027-11-01T04:00:00Z' } })).body.wedding.id;
  assert.ok((await call('GET', `/templates?wedding=${w3}`)).body.templates.some((t: any) => t.id === 'taj-partner'));
  assert.ok(!(await call('GET', '/templates')).body.templates.some((t: any) => t.id === 'taj-partner'), 'hidden from everyone else');
  assert.equal((await call('PATCH', `/weddings/${W}`, couple, { template_id: 'taj-partner' })).status, 400);
  assert.equal((await call('GET', `/weddings/${w3}/quote`, pcCouple)).body.discount, 1500);

  // Viral attribution from a guest page, and the showcase (permission + approval).
  const viral = await signIn('viral@example.com');
  await call('POST', '/weddings', viral, { partner1: 'V', partner2: 'W', from_slug: w.wedding.slug, event: { starts_at: '2027-12-12T04:00:00Z' } });
  await call('PATCH', `/weddings/${W}`, couple, { template_id: 'kandyan-gold' });
  await call('POST', `/weddings/${W}/publish`, couple);
  await call('POST', `/weddings/${W}/showcase`, couple, { share: true });
  assert.equal((await call('GET', '/public/showcase')).body.weddings.length, 0);
  await call('POST', `/admin/showcase/${W}`, admin, { approve: true });
  const sc = (await call('GET', '/public/showcase')).body.weddings;
  assert.equal(sc.length, 1);
  assert.equal(sc[0].vendors[0].name, 'Lens & Light');
  const ms = (await call('GET', '/admin/marketplace-stats', admin)).body;
  assert.equal(ms.viral_signups, 1);
  assert.ok(ms.paid_weddings_contacting >= 1);
});
