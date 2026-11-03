// Vendors pay for featured placement and the verified badge themselves (VENDOR_PROMOTIONS=on).
process.env.VENDOR_PROMOTIONS = 'on';
process.env.ADMIN_EMAILS = 'admin@example.test';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { FastifyInstance } from 'fastify';

const { pool } = await import('../src/db.ts');
const { config } = await import('../src/config.ts');
const { migrate } = await import('../src/migrate.ts');
const { seed } = await import('../src/seed.ts');
const { buildApp } = await import('../src/app.ts');
const { signWebhook } = await import('../src/routes/payments.ts');

let app: FastifyInstance;
async function call(method: string, url: string, token?: string, body?: unknown) {
  const r = await app.inject({ method: method as any, url: '/api' + url, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) }, payload: body !== undefined ? JSON.stringify(body) : undefined });
  return { status: r.statusCode, body: r.json() as any };
}
async function signIn(email: string) {
  const s = await call('POST', '/auth/email/start', undefined, { email });
  return (await call('POST', '/auth/email/verify', undefined, { email, code: s.body.devCode })).body.token as string;
}
async function gatewayPays(reference: string, amount: number) {
  const body = JSON.stringify({ reference, amount_lkr: amount, status: 'paid', transaction_id: 't-' + reference });
  const r = await app.inject({ method: 'POST', url: '/api/payments/webhook', headers: { 'content-type': 'application/json', 'x-signature': signWebhook(body) }, payload: body });
  assert.equal(r.statusCode, 200);
}
const monthsFromNow = (d: string) => Math.round((new Date(d).getTime() - Date.now()) / (30.44 * 86400000));

before(async () => {
  assert.match(config.databaseUrl, /wedding_test/, 'tests must use the test database');
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  await seed();
  app = await buildApp();
});
after(async () => { await app.close(); await pool.end(); });

test('a vendor buys featured placement and the verified badge; slots and refunds are respected', async () => {
  const t = await signIn('studio@example.test');
  const v = await call('POST', '/vendors', t, { business_name: 'Lens Studio', category: 'photographers', district: 'Colombo', service_areas: ['Colombo'], languages: ['en'], phone: '0771234567', years_active: 4 });
  assert.equal(v.status, 200, JSON.stringify(v.body));
  const vendorId = (await pool.query(`SELECT id FROM vendors WHERE business_name='Lens Studio'`)).rows[0].id;

  // Not before approval.
  assert.equal((await call('GET', '/vendor/promotions', t)).body.open, false);
  assert.equal((await call('POST', '/vendor/checkout', t, { product: 'vendor_featured', months: 2 })).status, 400);
  await pool.query(`UPDATE vendors SET status='approved' WHERE id=$1`, [vendorId]);

  const promo = await call('GET', '/vendor/promotions', t);
  assert.equal(promo.body.open, true);
  assert.ok(promo.body.featured_slots_left >= 1);

  // Featured, by card: 2 months at the monthly price.
  const f = await call('POST', '/vendor/checkout', t, { product: 'vendor_featured', months: 2 });
  assert.equal(f.status, 200, JSON.stringify(f.body));
  assert.equal(f.body.amount_lkr, 2 * 3000);
  await gatewayPays(f.body.reference, f.body.amount_lkr);
  const after1 = await call('GET', '/vendor/promotions', t);
  assert.equal(monthsFromNow(after1.body.featured_until), 2);

  // Verified badge by bank transfer: confirmed by an admin from the usual list.
  const vb = await call('POST', '/vendor/checkout', t, { product: 'vendor_verified', method: 'bank_transfer' });
  assert.equal(vb.body.status, 'pending');
  const admin = await signIn('admin@example.test');
  const pending = (await call('GET', '/admin/payments?status=pending', admin)).body.payments;
  const row = pending.find((p: any) => p.reference === vb.body.reference);
  assert.equal(row.business_name, 'Lens Studio');
  assert.equal((await call('POST', `/admin/payments/${row.id}/approve`, admin)).status, 200);
  assert.equal(monthsFromNow((await call('GET', '/vendor/promotions', t)).body.verified_until), 12);

  // Refunding the featured payment takes back exactly those two months.
  const paid = (await pool.query(`SELECT id FROM payments WHERE reference=$1`, [f.body.reference])).rows[0];
  assert.equal((await call('POST', `/admin/payments/${paid.id}/refund`, admin, { reason: 'changed mind' })).status, 200);
  assert.equal((await call('GET', '/vendor/promotions', t)).body.featured_until, null);

  // When every featured place in the category is taken, a new vendor can't buy one.
  await pool.query(`UPDATE vendor_categories SET featured_slots=1 WHERE id='photographers'`);
  await pool.query(`UPDATE vendors SET featured_until = now() + interval '1 month' WHERE id=$1`, [vendorId]);
  const t2 = await signIn('second@example.test');
  await call('POST', '/vendors', t2, { business_name: 'Second Lens', category: 'photographers', district: 'Kandy', service_areas: ['Kandy'], languages: ['si'], phone: '0771234568', years_active: 2 });
  await pool.query(`UPDATE vendors SET status='approved' WHERE business_name='Second Lens'`);
  assert.equal((await call('POST', '/vendor/checkout', t2, { product: 'vendor_featured', months: 1 })).status, 409);
  // …but the one holding the slot can extend.
  assert.equal((await call('POST', '/vendor/checkout', t, { product: 'vendor_featured', months: 1 })).status, 200);
});
