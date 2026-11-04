// Staff two-factor sign-in, with STAFF_MFA=required as in production.
process.env.STAFF_MFA = 'required';
process.env.ADMIN_EMAILS = 'boss@example.test';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { FastifyInstance } from 'fastify';

const { pool } = await import('../src/db.ts');
const { config } = await import('../src/config.ts');
const { migrate } = await import('../src/migrate.ts');
const { seed } = await import('../src/seed.ts');
const { buildApp } = await import('../src/app.ts');
const { codeAt, stepNow, matchStep, base32 } = await import('../src/lib/totp.ts');

let app: FastifyInstance;
async function call(method: string, url: string, token?: string, body?: unknown) {
  const r = await app.inject({ method: method as any, url: '/api' + url, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) }, payload: body !== undefined ? JSON.stringify(body) : undefined });
  return { status: r.statusCode, body: r.json() as any };
}
async function signIn(email: string) {
  const s = await call('POST', '/auth/email/start', undefined, { email });
  return (await call('POST', '/auth/email/verify', undefined, { email, code: s.body.devCode })).body.token as string;
}

before(async () => {
  assert.match(config.databaseUrl, /wedding_test/, 'tests must use the test database');
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  await seed();
  app = await buildApp();
});
after(async () => { await app.close(); await pool.end(); });

test('TOTP matches RFC 6238 and refuses reused codes', () => {
  const secret = base32(Buffer.from('12345678901234567890'));
  assert.equal(codeAt(secret, stepNow(59_000)), '287082');
  assert.equal(codeAt(secret, stepNow(1111111109_000)), '081804');
  const step = matchStep(secret, '287082', null, 59_000);
  assert.equal(step, 1);
  assert.equal(matchStep(secret, '287082', step, 59_000), null, 'the same code twice');
  assert.equal(matchStep(secret, '000000', null, 59_000), null);
});

test('staff must set up and verify an authenticator app before admin work', async () => {
  assert.equal(config.staffMfa, true);
  const boss = await signIn('boss@example.test');
  assert.equal((await call('GET', '/admin/stats', boss)).body.error, 'mfa_setup_required');
  assert.deepEqual((await call('GET', '/me', boss)).body.staff_mfa, { required: true, enabled: false, verified: false });

  const setup = await call('POST', '/auth/totp/setup', boss);
  assert.equal(setup.status, 200);
  assert.match(setup.body.otpauth_url, /^otpauth:\/\/totp\//);
  const stored = (await pool.query(`SELECT totp_secret FROM users WHERE email='boss@example.test'`)).rows[0].totp_secret;
  assert.ok(!stored.includes(setup.body.secret), 'the secret is stored encrypted');

  assert.equal((await call('POST', '/auth/totp/verify', boss, { code: '000000' })).status, 401);
  const code = codeAt(setup.body.secret, stepNow());
  assert.equal((await call('POST', '/auth/totp/verify', boss, { code })).status, 200);
  assert.equal((await call('GET', '/admin/stats', boss)).status, 200);
  assert.equal((await call('POST', '/auth/totp/setup', boss)).status, 409, 'cannot be replaced without an admin reset');

  // A new session (another device) needs a fresh code, and the code just used doesn't work again.
  const boss2 = await signIn('boss@example.test');
  assert.equal((await call('GET', '/admin/stats', boss2)).body.error, 'mfa_required');
  assert.equal((await call('POST', '/auth/totp/verify', boss2, { code })).status, 401);
  assert.equal((await call('POST', '/auth/totp/verify', boss2, { code: codeAt(setup.body.secret, stepNow() + 1) })).status, 200);
  assert.equal((await call('GET', '/admin/stats', boss2)).status, 200);

  // Couples never see any of this.
  const couple = await signIn('couple@example.test');
  assert.equal((await call('POST', '/auth/totp/setup', couple)).status, 403);
  assert.equal((await call('GET', '/me', couple)).body.staff_mfa, undefined);
});
