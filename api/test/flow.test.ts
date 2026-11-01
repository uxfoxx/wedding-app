// End-to-end Phase 1 flow against a real PostgreSQL test database:
// sign up → create wedding → design → guests → publish → send → guest opens and RSVPs →
// dashboard → free limits → pay → export → admin.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, rm, access } from 'node:fs/promises';
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
  const json = r.headers['content-type']?.includes('json') ? r.json() : r.body;
  return { status: r.statusCode, body: json as any };
}

async function signIn(email: string) {
  const s = await call('POST', '/auth/email/start', undefined, { email });
  assert.equal(s.status, 200);
  const v = await call('POST', '/auth/email/verify', undefined, { email, code: s.body.devCode });
  assert.equal(v.status, 200);
  return v.body.token as string;
}

before(async () => {
  assert.match(config.databaseUrl, /wedding_test/, 'tests must use the test database');
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await rm(config.storageDir, { recursive: true, force: true });
  await migrate();
  await seed();
  app = await buildApp();
});

after(async () => { await app.close(); await pool.end(); });

test('Phase 1 couple flow, end to end', async () => {
  const couple = await signIn('nimal@example.com');
  assert.equal((await call('POST', '/auth/email/verify', undefined, { email: 'nimal@example.com', code: '000000' })).status, 401);

  // First run: create the wedding with its first event.
  const created = await call('POST', '/weddings', couple, {
    kind: 'wedding', wedding_type: 'buddhist', partner1: 'Nimal', partner2: 'Kumari', language: 'en', mode: 'easy',
    event: { starts_at: '2027-05-20T04:30:00Z', venue: 'Cinnamon Grand', address: 'Colombo 03' },
  });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const W = created.body.wedding.id;
  assert.equal(created.body.events[0].kind, 'poruwa');
  assert.equal(created.body.nextStep.key, 'choose_template');

  // Free plan: one event only.
  const ev2 = await call('POST', `/weddings/${W}/events`, couple, { kind: 'homecoming', starts_at: '2027-05-25T10:00:00Z' });
  assert.equal(ev2.status, 402);
  assert.equal(ev2.body.feature, 'events');

  // Premium template is blocked on the free plan; a free one works.
  assert.equal((await call('PATCH', `/weddings/${W}`, couple, { template_id: 'poruwa-royal' })).status, 402);
  const tpl = await call('PATCH', `/weddings/${W}`, couple, { template_id: 'kandyan-gold', invitation: { message: 'Join us <script>alert(1)</script>', parents: 'Mr & Mrs Perera' } });
  assert.equal(tpl.status, 200);

  // Wording assistant.
  const wordings = await call('GET', '/wordings?language=en&tone=formal&event_kind=wedding', couple);
  const filled = await call('POST', `/weddings/${W}/wording/${wordings.body.wordings[0].id}/fill`, couple);
  assert.match(filled.body.text, /Nimal & Kumari/);
  assert.match(filled.body.text, /Cinnamon Grand/);

  // Preview is the same renderer guests get; user text is escaped.
  const prev = await app.inject({ method: 'GET', url: `/api/weddings/${W}/preview`, headers: { authorization: `Bearer ${couple}` } });
  assert.equal(prev.statusCode, 200);
  assert.match(prev.body, /Nimal/);
  assert.ok(!prev.body.includes('<script>alert(1)'), 'user content must be escaped');
  const pl = await call('POST', `/weddings/${W}/preview-link`, couple, { template: 'poruwa-royal' });
  const plUrl = new URL(pl.body.url);
  const signed = await app.inject({ method: 'GET', url: plUrl.pathname + plUrl.search });
  assert.equal(signed.statusCode, 200);
  assert.match(signed.body, /class="envelope"/, 'premium designs can be previewed on the free plan');
  assert.equal((await app.inject({ method: 'GET', url: plUrl.pathname + plUrl.search.replace('sig=', 'sig=x') })).statusCode, 403);

  // Guests: paste import preview → confirm.
  const pv = await call('POST', `/weddings/${W}/guests/import/preview`, couple, { format: 'paste', text: 'Uncle Sam – 2 people, veg / Nimal Silva & wife 0771234567 / Dr. Perera 0771234567' });
  assert.equal(pv.body.rows.length, 3);
  assert.ok(pv.body.rows[2].flags.includes('possible_duplicate'));
  const imp = await call('POST', `/weddings/${W}/guests/import`, couple, { source: 'paste', rows: pv.body.rows.slice(0, 2) });
  assert.equal(imp.body.added, 2);
  for (const n of ['Amara', 'Bandula', 'Chathura']) assert.equal((await call('POST', `/weddings/${W}/guests`, couple, { name: n, phone: '+61 412 000 00' + n.length, vip: n === 'Amara' })).status, 200);

  // Can't send before publishing.
  assert.equal((await call('GET', `/weddings/${W}/send-queue`, couple)).status, 400);

  const pub = await call('POST', `/weddings/${W}/publish`, couple);
  assert.equal(pub.status, 200, JSON.stringify(pub.body));
  const slug = pub.body.wedding.slug;
  const html = await readFile(join(config.storageDir, 'site', slug, 'index.html'), 'utf8');
  assert.match(html, /<footer>/, 'free plan shows branding');
  assert.match(html, /og:title/);

  // Send queue: personal WhatsApp links, VIP first.
  const queue = await call('GET', `/weddings/${W}/send-queue`, couple);
  assert.equal(queue.body.guests.length, 5);
  assert.equal(queue.body.guests[0].name, 'Amara');
  const sam = queue.body.guests.find((g: any) => g.name === 'Sam');
  assert.match(queue.body.guests[0].whatsapp, /^https:\/\/wa\.me\/614120000/);
  assert.match(sam.text, /Dear Uncle Sam/);
  const token = new URL(sam.link.replace('#t=', '?t=')).searchParams.get('t')!;
  assert.ok(token.length >= 20);
  assert.ok(!sam.link.includes('Sam'), 'no names in URLs');
  await call('POST', `/weddings/${W}/guests/mark-sent`, couple, { guest_ids: queue.body.guests.map((g: any) => g.id) });

  // Guest side: static JSON on the "CDN", then open beacon and RSVP.
  const gj = JSON.parse(await readFile(join(config.storageDir, 'site', slug, 'g', `${token}.json`), 'utf8'));
  assert.equal(gj.name, 'Uncle Sam');
  assert.equal(gj.seats, 2);
  assert.ok(!JSON.stringify(gj).includes('+94'), 'no phone numbers on the CDN');
  await call('POST', '/public/open', undefined, { token });
  const evId = created.body.events[0].id;
  assert.equal((await call('POST', '/public/rsvp', undefined, { token, responses: [{ event_id: evId, status: 'coming', headcount: 3 }] })).status, 400, 'headcount above seats rejected');
  const rs = await call('POST', '/public/rsvp', undefined, { token, responses: [{ event_id: evId, status: 'coming', headcount: 2, meal: 'vegetarian' }], message: 'So happy for you!' });
  assert.equal(rs.status, 200);
  assert.equal(rs.body.guest.rsvps[evId].status, 'coming');
  assert.equal((await call('POST', '/public/rsvp', undefined, { token: 'x'.repeat(22), responses: [{ event_id: evId, status: 'coming' }] })).status, 404);

  const dash = await call('GET', `/weddings/${W}/dashboard`, couple);
  assert.deepEqual([dash.body.totals.invited, dash.body.totals.sent, dash.body.totals.opened], [5, 5, 1]);
  assert.deepEqual([dash.body.events[0].coming, dash.body.events[0].pending, dash.body.events[0].headcount, dash.body.events[0].meals_vegetarian], [1, 4, 2, 2]);
  assert.equal(dash.body.recentMessages[0].message, 'So happy for you!');

  // Follow-ups: nobody yet (sent < 7 days ago); backdate and check VIP comes first.
  assert.equal((await call('GET', `/weddings/${W}/follow-ups`, couple)).body.guests.length, 0);
  await pool.query(`UPDATE guests SET sent_at = now() - interval '8 days' WHERE wedding_id=$1`, [W]);
  const fu = await call('GET', `/weddings/${W}/follow-ups`, couple);
  assert.equal(fu.body.guests.length, 4);
  assert.equal(fu.body.guests[0].name, 'Amara');
  assert.equal(fu.body.guests[0].callFirst, true);

  // Revoking a link removes the old file.
  const nl = await call('POST', `/weddings/${W}/guests/${sam.id}/new-link`, couple);
  assert.equal(nl.status, 200);
  await assert.rejects(access(join(config.storageDir, 'site', slug, 'g', `${token}.json`)));

  // Co-owner with edit-guests permission.
  const inv = await call('POST', `/weddings/${W}/members/invite`, couple, { role: 'edit_guests' });
  const mum = await signIn('amma@example.com');
  assert.equal((await call('POST', `/invites/${inv.body.token}/accept`, mum)).status, 200);
  assert.equal((await call('POST', `/weddings/${W}/guests`, mum, { name: 'Mum friend' })).status, 200);
  assert.equal((await call('PATCH', `/weddings/${W}`, mum, { partner1: 'X' })).status, 403);
  const stranger = await signIn('stranger@example.com');
  assert.equal((await call('GET', `/weddings/${W}`, stranger)).status, 404);

  // Free limit: 50 guests.
  const many = Array.from({ length: 44 }, (_, i) => ({ name: `Guest ${i}` }));
  assert.equal((await call('POST', `/weddings/${W}/guests/import`, couple, { rows: many })).status, 200);
  const over = await call('POST', `/weddings/${W}/guests`, couple, { name: 'One too many' });
  assert.equal(over.status, 402);
  assert.equal((await call('GET', `/weddings/${W}/export.csv`, couple)).status, 402);

  // Pay on the web: gateway checkout → signed webhook unlocks the wedding.
  const co = await call('POST', `/weddings/${W}/checkout`, couple, { product: 'wedding_pass' });
  assert.equal(co.body.amount_lkr, 7900);
  const bad = JSON.stringify({ reference: co.body.reference, amount_lkr: 7900, status: 'paid' });
  assert.equal((await app.inject({ method: 'POST', url: '/api/payments/webhook', headers: { 'content-type': 'application/json', 'x-signature': 'nope' }, payload: bad })).statusCode, 401);
  const wr = await app.inject({ method: 'POST', url: '/api/payments/webhook', headers: { 'content-type': 'application/json', 'x-signature': signWebhook(bad) }, payload: bad });
  assert.equal(wr.statusCode, 200);
  const after = await call('GET', `/weddings/${W}`, couple);
  assert.equal(after.body.plan.plan, 'pass');
  assert.equal(after.body.plan.limits.guests, null);
  assert.equal((await call('POST', `/weddings/${W}/guests`, couple, { name: 'Now allowed' })).status, 200);
  assert.equal((await call('POST', `/weddings/${W}/events`, couple, { kind: 'homecoming', starts_at: '2027-05-25T10:00:00Z' })).status, 200);
  assert.equal((await call('PATCH', `/weddings/${W}`, couple, { template_id: 'poruwa-royal' })).status, 200);

  // Republish job removes the footer.
  await pool.query("UPDATE jobs SET run_at = now() WHERE done_at IS NULL");
  await runDueJobs();
  const html2 = await readFile(join(config.storageDir, 'site', slug, 'index.html'), 'utf8');
  assert.ok(!html2.includes('<footer>'));
  assert.match(html2, /id="cover" class="envelope"/);

  const csv = await app.inject({ method: 'GET', url: `/api/weddings/${W}/export.csv`, headers: { authorization: `Bearer ${couple}` } });
  assert.equal(csv.statusCode, 200);
  assert.match(csv.body, /Uncle/);
  assert.match(csv.body, /Poruwa Ceremony: reply/);

  // Open group link: matched name → existing guest; unknown name → new guest for review.
  const ol = await call('POST', `/weddings/${W}/open-link`, couple, { enabled: true });
  const open = new URLSearchParams(ol.body.wedding.open_link.split('#')[1]).get('o');
  const m1 = await call('POST', '/public/claim', undefined, { slug, open, name: 'chathura' });
  assert.equal(m1.body.matched, true);
  const m2 = await call('POST', '/public/claim', undefined, { slug, open, name: 'Someone New' });
  assert.equal(m2.body.matched, false);
  assert.equal((await call('POST', '/public/claim', undefined, { slug, open: 'wrong', name: 'Someone' })).status, 404);

  // Admin: stats, refund policy, audit.
  config.adminEmails.push('staff@example.com');
  const staff = await signIn('staff@example.com');
  assert.equal((await call('GET', '/admin/stats', couple)).status, 403);
  const stats = await call('GET', '/admin/stats', staff);
  assert.equal(stats.body.totals.paid_weddings, 1);
  const pay = (await call('GET', '/admin/payments?status=paid', staff)).body.payments[0];
  const ref = await call('POST', `/admin/payments/${pay.id}/refund`, staff, { reason: 'changed mind' });
  assert.equal(ref.status, 409, 'invitations were already sent, so outside policy');
  const audit = await call('GET', '/admin/audit', staff);
  assert.equal(audit.status, 200);

  // Bank transfer → admin approval.
  const w2 = await call('POST', '/weddings', stranger, { partner1: 'A', partner2: 'B', event: { starts_at: '2027-08-01T05:00:00Z' } });
  const bt = await call('POST', `/weddings/${w2.body.wedding.id}/checkout`, stranger, { method: 'bank_transfer' });
  assert.match(bt.body.reference, /^WP-/);
  assert.equal((await call('POST', `/admin/payments/${bt.body.paymentId}/approve`, staff)).status, 200);
  assert.equal((await call('GET', `/weddings/${w2.body.wedding.id}`, stranger)).body.plan.plan, 'pass');
  assert.ok((await call('GET', '/admin/audit', staff)).body.entries.some((e: any) => e.action === 'payment.approve'));
});

test('privacy purge removes guest phone numbers 12 months after the wedding', async () => {
  const { purgeExpiredContacts } = await import('../src/lib/privacy.ts');
  const u = await pool.query(`INSERT INTO users (email) VALUES ('old@example.com') RETURNING id`);
  const w = await pool.query(`INSERT INTO weddings (owner_id, partner1, partner2, slug) VALUES ($1,'O','P','oldslug') RETURNING id`, [u.rows[0].id]);
  await pool.query(`INSERT INTO events (wedding_id, kind, starts_at) VALUES ($1,'poruwa', now() - interval '13 months')`, [w.rows[0].id]);
  await pool.query(`INSERT INTO guests (wedding_id, name, phone, token) VALUES ($1,'G','+94770000000','tok_old_guest_123456')`, [w.rows[0].id]);
  assert.ok((await purgeExpiredContacts()) >= 1);
  const g = await pool.query('SELECT name, phone FROM guests WHERE wedding_id=$1', [w.rows[0].id]);
  assert.deepEqual(g.rows[0], { name: 'G', phone: null });
});
