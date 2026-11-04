// Authenticator-app codes (TOTP, RFC 6238: SHA-1, 6 digits, 30 seconds) for staff sign-in.
// The shared secret is stored encrypted, and each code works once.
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'node:crypto';
import { config } from '../config.ts';

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32(buf: Buffer): string {
  let bits = 0, value = 0, out = '';
  for (const b of buf) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function unbase32(s: string): Buffer {
  let bits = 0, value = 0;
  const out: number[] = [];
  for (const c of s.replace(/=+$/, '').toUpperCase()) {
    const i = B32.indexOf(c);
    if (i < 0) throw new Error('bad base32');
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(out);
}

export function newSecret(): string { return base32(randomBytes(20)); }

/** The code for a 30-second time step. */
export function codeAt(secret: string, step: number): string {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(step));
  const h = createHmac('sha1', unbase32(secret)).update(msg).digest();
  const o = h[h.length - 1] & 15;
  const n = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(n % 1_000_000).padStart(6, '0');
}

export const stepNow = (ms = Date.now()) => Math.floor(ms / 30_000);

/**
 * The matching time step (one step either side allows for clock drift), or null. Steps at or
 * before lastStep are refused, so an overheard code can't be used again.
 */
export function matchStep(secret: string, code: string, lastStep: number | null, ms = Date.now()): number | null {
  if (!/^\d{6}$/.test(code)) return null;
  const now = stepNow(ms);
  for (const s of [now - 1, now, now + 1]) {
    if (lastStep !== null && s <= lastStep) continue;
    if (codeAt(secret, s) === code) return s;
  }
  return null;
}

export function otpauthUrl(secret: string, account: string): string {
  return `otpauth://totp/${encodeURIComponent(`Wedding admin:${account}`)}?secret=${secret}&issuer=${encodeURIComponent('Wedding admin')}&algorithm=SHA1&digits=6&period=30`;
}

const key = () => createHash('sha256').update(config.totpKey || `totp:${config.previewSecret}`).digest();

export function sealSecret(secret: string): string {
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key(), iv);
  const body = Buffer.concat([c.update(secret, 'utf8'), c.final()]);
  return [iv, c.getAuthTag(), body].map((b) => b.toString('base64url')).join('.');
}

export function openSecret(sealed: string): string {
  const [iv, tag, body] = sealed.split('.').map((p) => Buffer.from(p, 'base64url'));
  const d = createDecipheriv('aes-256-gcm', key(), iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(body), d.final()]).toString('utf8');
}
