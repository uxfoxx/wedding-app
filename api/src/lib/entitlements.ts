// Entitlements live on the server (architecture decision 6). The apps only read them.
import { pricing } from '../config.ts';
import { HttpError, addMonths } from './util.ts';
import { one, type Queryable, pool } from '../db.ts';

export interface WeddingPlanInfo {
  plan: 'free' | 'pass';
  lastEventAt: Date | null;
  readOnly: boolean;           // pass access ended → keepsake, read-only
  limits: { guests: number | null; events: number | null; premiumTemplates: boolean; export: boolean; branding: boolean };
}

export async function planInfo(weddingId: string, db: Queryable = pool): Promise<WeddingPlanInfo> {
  const w = await one<{ plan: 'free' | 'pass'; last: Date | null }>(
    `SELECT w.plan, (SELECT max(coalesce(ends_at, starts_at)) FROM events e WHERE e.wedding_id = w.id) AS last
     FROM weddings w WHERE w.id = $1`, [weddingId], db);
  if (!w) throw new HttpError(404, 'wedding_not_found');
  const pass = w.plan === 'pass';
  const readOnly = pass && !!w.last && addMonths(w.last, pricing.passAccessMonthsAfterLastEvent) < new Date();
  return {
    plan: w.plan,
    lastEventAt: w.last,
    readOnly,
    limits: {
      guests: pass ? null : pricing.freeGuestLimit,
      events: pass ? null : pricing.freeEventLimit,
      premiumTemplates: pass,
      export: pass,
      branding: !pass,
    },
  };
}

export function paywall(feature: string, message: string): HttpError {
  return new HttpError(402, 'upgrade_required', message, { feature });
}

export async function assertCanAddGuests(weddingId: string, adding: number, db: Queryable = pool) {
  const info = await planInfo(weddingId, db);
  if (info.limits.guests === null) return;
  const r = await one<{ n: number }>('SELECT count(*)::int AS n FROM guests WHERE wedding_id=$1', [weddingId], db);
  if (r!.n + adding > info.limits.guests) {
    throw paywall('guests', `The free plan includes up to ${info.limits.guests} guests. The Wedding Pass removes the limit.`);
  }
}

export async function assertCanAddEvent(weddingId: string, db: Queryable = pool) {
  const info = await planInfo(weddingId, db);
  if (info.limits.events === null) return;
  const r = await one<{ n: number }>('SELECT count(*)::int AS n FROM events WHERE wedding_id=$1', [weddingId], db);
  if (r!.n >= info.limits.events) throw paywall('events', 'The free plan includes one event. The Wedding Pass adds the Poruwa, reception, homecoming and more.');
}
