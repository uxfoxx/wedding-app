import type { FastifyInstance } from 'fastify';
import { config } from '../config.ts';
import { one, pool } from '../db.ts';
import { createSession, requireUser, startCode, upsertUser, verifyCode, verifyIdToken, verifyLink } from '../lib/auth.ts';
import { outbox } from '../lib/notify.ts';
import { normalizePhone } from '../lib/phone.ts';
import { HttpError, bad, oneOf, sha256, str } from '../lib/util.ts';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export default async function authRoutes(app: FastifyInstance) {
  app.post('/auth/email/start', { config: { rateLimit: 10 } }, async (req) => {
    const email = str((req.body as any)?.email, 'email', { max: 200 })!.toLowerCase();
    if (!EMAIL_RE.test(email)) throw bad('invalid_email');
    const { code, link } = await startCode('email', email);
    const url = `${config.publicApiUrl}/api/auth/link/${link}`;
    await outbox.email(email, 'Your sign-in code', `Your code is ${code}. Or tap to sign in: ${url}\nThe code expires in 15 minutes.`);
    return { sent: true, ...(config.exposeDevCodes ? { devCode: code, devLink: url } : {}) };
  });

  app.post('/auth/email/verify', { config: { rateLimit: 20 } }, async (req) => {
    const b = req.body as any;
    const email = str(b?.email, 'email', { max: 200 })!.toLowerCase();
    const code = str(b?.code, 'code', { max: 10 })!;
    if (!(await verifyCode('email', email, code))) throw new HttpError(401, 'invalid_code', 'That code is wrong or has expired.');
    const userId = await upsertUser({ email });
    return { token: await createSession(userId) };
  });

  // Magic link: signs in and hands the session to the web panel.
  app.get('/auth/link/:token', async (req, reply) => {
    const row = await verifyLink((req.params as any).token);
    if (!row) return reply.code(410).type('text/html').send('<p>This sign-in link has expired. Please ask for a new one.</p>');
    const userId = await upsertUser(row.channel === 'email' ? { email: row.address } : { phone: row.address });
    const token = await createSession(userId);
    return reply.redirect(`${config.webPanelUrl}/#session=${token}`);
  });

  app.post('/auth/phone/start', { config: { rateLimit: 5 } }, async (req) => {
    const phone = normalizePhone(str((req.body as any)?.phone, 'phone', { max: 30 }));
    if (!phone) throw bad('invalid_phone');
    const { code } = await startCode('phone', phone);
    await outbox.sms(phone, `Your wedding app code is ${code}`);
    return { sent: true, phone, ...(config.exposeDevCodes ? { devCode: code } : {}) };
  });

  app.post('/auth/phone/verify', { config: { rateLimit: 20 } }, async (req) => {
    const b = req.body as any;
    const phone = normalizePhone(str(b?.phone, 'phone', { max: 30 }));
    if (!phone) throw bad('invalid_phone');
    if (!(await verifyCode('phone', phone, str(b?.code, 'code', { max: 10 })!))) throw new HttpError(401, 'invalid_code');
    return { token: await createSession(await upsertUser({ phone })) };
  });

  app.post('/auth/:provider', async (req) => {
    const provider = oneOf((req.params as any).provider, 'provider', ['google', 'apple'] as const);
    const p = await verifyIdToken(str((req.body as any)?.idToken, 'idToken', { max: 5000 })!, provider);
    const userId = await upsertUser({
      [provider === 'google' ? 'google_sub' : 'apple_sub']: p.sub,
      email: p.email_verified === true || p.email_verified === 'true' ? p.email : undefined,
      name: (req.body as any)?.name ?? p.name ?? null,
    });
    return { token: await createSession(userId) };
  });

  app.post('/auth/logout', async (req) => {
    const h = req.headers.authorization;
    if (h?.startsWith('Bearer ')) await pool.query('DELETE FROM sessions WHERE token_hash=$1', [sha256(h.slice(7))]);
    return { ok: true };
  });

  app.get('/me', async (req) => {
    const u = await requireUser(req);
    return { user: u };
  });

  app.patch('/me', async (req) => {
    const u = await requireUser(req);
    const b = req.body as any;
    const name = b.name !== undefined ? str(b.name, 'name', { max: 100, optional: true }) : undefined;
    const locale = b.locale !== undefined ? oneOf(b.locale, 'locale', ['en', 'si', 'ta'] as const) : undefined;
    const row = await one(
      `UPDATE users SET name = coalesce($2, name), locale = coalesce($3, locale) WHERE id=$1 RETURNING id, email, phone, name, locale, staff_role`,
      [u.id, name ?? null, locale ?? null]);
    return { user: row };
  });

  // Account deletion on request (PDPA). Weddings the user owns are deleted with their guests.
  app.delete('/me', async (req) => {
    const u = await requireUser(req);
    if ((req.body as any)?.confirm !== 'DELETE') throw bad('confirm_required', 'Send {"confirm":"DELETE"}.');
    const paid = await one(`SELECT 1 FROM payments WHERE user_id=$1 LIMIT 1`, [u.id]);
    await pool.query('DELETE FROM weddings w WHERE owner_id=$1 AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.wedding_id=w.id)', [u.id]);
    // Payment records must be kept for accounting; anonymise the user instead of deleting.
    if (paid) {
      await pool.query(`UPDATE users SET email=NULL, phone=NULL, name='Deleted user', google_sub=NULL, apple_sub=NULL, blocked_at=now() WHERE id=$1`, [u.id]);
      await pool.query(`UPDATE guests SET phone=NULL, notes=NULL WHERE wedding_id IN (SELECT id FROM weddings WHERE owner_id=$1)`, [u.id]);
    } else {
      await pool.query('DELETE FROM wedding_members WHERE user_id=$1', [u.id]);
      await pool.query('DELETE FROM users WHERE id=$1', [u.id]);
    }
    return { deleted: true };
  });
}
