// Sign-in: Google and Apple ID tokens, email codes/links (free), and phone OTP
// (offered but not the default because SMS costs money per text).
import { createPublicKey, verify as cryptoVerify } from 'node:crypto';
import type { FastifyRequest } from 'fastify';
import { config } from '../config.ts';
import { one, q, pool } from '../db.ts';
import { HttpError, randomToken, randomDigits, sha256, safeEqual } from './util.ts';

const SESSION_DAYS = 90;
const CODE_MINUTES = 15;

export interface AuthUser { id: string; email: string | null; phone: string | null; name: string | null; locale: string; staff_role: string | null }

export async function createSession(userId: string): Promise<string> {
  const token = randomToken(32);
  await pool.query(`INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ($1, $2, now() + interval '${SESSION_DAYS} days')`, [sha256(token), userId]);
  return token;
}

export async function userFromRequest(req: FastifyRequest): Promise<AuthUser | null> {
  const h = req.headers.authorization;
  if (!h?.startsWith('Bearer ')) return null;
  const u = await one<AuthUser & { blocked_at: Date | null }>(
    `SELECT u.id, u.email, u.phone, u.name, u.locale, u.staff_role, u.blocked_at FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = $1 AND s.expires_at > now()`, [sha256(h.slice(7))]);
  if (!u || u.blocked_at) return null;
  const { blocked_at, ...user } = u;
  return user;
}

export async function requireUser(req: FastifyRequest): Promise<AuthUser> {
  const u = await userFromRequest(req);
  if (!u) throw new HttpError(401, 'unauthenticated');
  return u;
}

export const STAFF_MFA_HOURS = 12;

/** Staff two-factor state for this request's session. */
export async function staffMfa(req: FastifyRequest): Promise<{ required: boolean; enabled: boolean; verified: boolean }> {
  const r = await one(`SELECT u.totp_enabled_at IS NOT NULL AS enabled, coalesce(s.mfa_at > now() - interval '${STAFF_MFA_HOURS} hours', false) AS verified
    FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1`, [sha256(req.headers.authorization!.slice(7))]);
  return { required: config.staffMfa, enabled: !!r?.enabled, verified: !!r?.verified };
}

export async function requireStaff(req: FastifyRequest, roles: string[] = ['admin', 'support']): Promise<AuthUser> {
  const u = await requireUser(req);
  if (!u.staff_role || !roles.includes(u.staff_role)) throw new HttpError(403, 'staff_only');
  if (config.staffMfa) {
    const m = await staffMfa(req);
    if (!m.enabled) throw new HttpError(403, 'mfa_setup_required', 'Staff accounts need an authenticator app. Set it up to continue.');
    if (!m.verified) throw new HttpError(403, 'mfa_required', 'Enter the code from your authenticator app.');
  }
  return u;
}

/** Find or create a user by a verified identity. */
export async function upsertUser(by: { email?: string; phone?: string; google_sub?: string; apple_sub?: string; name?: string | null }): Promise<string> {
  const email = by.email?.toLowerCase();
  let u = by.google_sub ? await one('SELECT id FROM users WHERE google_sub=$1', [by.google_sub])
    : by.apple_sub ? await one('SELECT id FROM users WHERE apple_sub=$1', [by.apple_sub]) : undefined;
  if (!u && email) u = await one('SELECT id FROM users WHERE email=$1', [email]);
  if (!u && by.phone) u = await one('SELECT id FROM users WHERE phone=$1', [by.phone]);
  if (u) {
    await pool.query(
      `UPDATE users SET google_sub = coalesce(google_sub, $2), apple_sub = coalesce(apple_sub, $3),
         email = coalesce(email, $4), name = coalesce(name, $5) WHERE id=$1`,
      [u.id, by.google_sub ?? null, by.apple_sub ?? null, email ?? null, by.name ?? null]);
  } else {
    u = await one(
      `INSERT INTO users (email, phone, google_sub, apple_sub, name) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
      [email ?? null, by.phone ?? null, by.google_sub ?? null, by.apple_sub ?? null, by.name ?? null]);
  }
  if (email && config.adminEmails.includes(email)) {
    await pool.query(`UPDATE users SET staff_role='admin' WHERE id=$1 AND staff_role IS NULL`, [u!.id]);
  }
  return u!.id;
}

// ---- One-time codes (email and phone) ----

export async function startCode(channel: 'email' | 'phone', address: string): Promise<{ code: string; link: string }> {
  const recent = await one<{ n: number }>(
    `SELECT count(*)::int AS n FROM auth_codes WHERE channel=$1 AND address=$2 AND created_at > now() - interval '15 minutes'`, [channel, address]);
  if (recent!.n >= 5) throw new HttpError(429, 'too_many_codes', 'Please wait a few minutes before asking for another code.');
  const code = randomDigits(6);
  const link = randomToken(24);
  await pool.query(
    `INSERT INTO auth_codes (channel, address, code_hash, link_hash, expires_at) VALUES ($1,$2,$3,$4, now() + interval '${CODE_MINUTES} minutes')`,
    [channel, address, sha256(`${address}:${code}`), sha256(link)]);
  return { code, link };
}

export async function verifyCode(channel: 'email' | 'phone', address: string, code: string): Promise<boolean> {
  const row = await one(
    `SELECT id, code_hash, attempts FROM auth_codes WHERE channel=$1 AND address=$2 AND used_at IS NULL AND expires_at > now()
     ORDER BY created_at DESC LIMIT 1`, [channel, address]);
  if (!row) return false;
  if (row.attempts >= 5) return false;
  if (!safeEqual(row.code_hash, sha256(`${address}:${code}`))) {
    await pool.query('UPDATE auth_codes SET attempts = attempts + 1 WHERE id=$1', [row.id]);
    return false;
  }
  await pool.query('UPDATE auth_codes SET used_at = now() WHERE id=$1', [row.id]);
  return true;
}

export async function verifyLink(link: string): Promise<{ channel: string; address: string } | null> {
  const [row] = await q(
    `UPDATE auth_codes SET used_at = now() WHERE link_hash=$1 AND used_at IS NULL AND expires_at > now() RETURNING channel, address`, [sha256(link)]);
  return row ?? null;
}

// ---- Google / Apple ID tokens (RS256 JWT checked against the provider's public keys) ----

const jwksCache = new Map<string, { at: number; keys: any[] }>();
async function jwks(url: string): Promise<any[]> {
  const c = jwksCache.get(url);
  if (c && Date.now() - c.at < 6 * 3600_000) return c.keys;
  const r = await fetch(url);
  if (!r.ok) throw new HttpError(502, 'identity_provider_unreachable');
  const keys = (await r.json()).keys;
  jwksCache.set(url, { at: Date.now(), keys });
  return keys;
}

export async function verifyIdToken(idToken: string, provider: 'google' | 'apple'): Promise<Record<string, any>> {
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'invalid_token');
  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  if (header.alg !== 'RS256') throw new HttpError(401, 'invalid_token');
  const url = provider === 'google' ? 'https://www.googleapis.com/oauth2/v3/certs' : 'https://appleid.apple.com/auth/keys';
  const jwk = (await jwks(url)).find((k) => k.kid === header.kid);
  if (!jwk) throw new HttpError(401, 'invalid_token');
  const ok = cryptoVerify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(parts[2], 'base64url'));
  if (!ok) throw new HttpError(401, 'invalid_token');
  const issuers = provider === 'google' ? ['https://accounts.google.com', 'accounts.google.com'] : ['https://appleid.apple.com'];
  const audiences = provider === 'google' ? config.googleClientIds : config.appleClientIds;
  if (!issuers.includes(payload.iss)) throw new HttpError(401, 'invalid_token');
  if (!audiences.includes(payload.aud)) throw new HttpError(401, 'invalid_audience');
  if (payload.exp * 1000 < Date.now()) throw new HttpError(401, 'token_expired');
  return payload;
}
