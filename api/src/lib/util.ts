import { randomBytes, createHash, timingSafeEqual } from 'node:crypto';

export class HttpError extends Error {
  status: number;
  code: string;
  extra?: Record<string, unknown>;
  constructor(status: number, code: string, message?: string, extra?: Record<string, unknown>) {
    super(message ?? code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

export const bad = (code: string, msg?: string) => new HttpError(400, code, msg);
export const notFound = (what = 'not_found') => new HttpError(404, what);
export const forbidden = (code = 'forbidden') => new HttpError(403, code);

/** URL-safe random token. 24 bytes ≈ 192 bits. */
export function randomToken(bytes = 24): string {
  return randomBytes(bytes).toString('base64url');
}

export function randomDigits(n: number): string {
  const b = randomBytes(n);
  return Array.from(b, (x) => String(x % 10)).join('');
}

export function sha256(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}

export function safeEqual(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

// Small input helpers so routes validate without a schema library.
export function str(v: unknown, field: string, opts: { max?: number; optional?: boolean } = {}): string | null {
  if (v === undefined || v === null || v === '') {
    if (opts.optional) return null;
    throw bad('invalid_input', `${field} is required`);
  }
  if (typeof v !== 'string') throw bad('invalid_input', `${field} must be text`);
  const s = v.trim();
  if (s.length > (opts.max ?? 500)) throw bad('invalid_input', `${field} is too long`);
  if (!s && !opts.optional) throw bad('invalid_input', `${field} is required`);
  return s || null;
}

export function int(v: unknown, field: string, min: number, max: number, def?: number): number {
  if ((v === undefined || v === null || v === '') && def !== undefined) return def;
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isInteger(n) || n < min || n > max) throw bad('invalid_input', `${field} must be ${min}–${max}`);
  return n;
}

export function oneOf<T extends string>(v: unknown, field: string, allowed: readonly T[], def?: T): T {
  if ((v === undefined || v === null || v === '') && def !== undefined) return def;
  if (!allowed.includes(v as T)) throw bad('invalid_input', `${field} must be one of ${allowed.join(', ')}`);
  return v as T;
}

export function escapeHtml(s: unknown): string {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

export function addMonths(d: Date, months: number): Date {
  const x = new Date(d);
  x.setMonth(x.getMonth() + months);
  return x;
}
