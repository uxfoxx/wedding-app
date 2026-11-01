// Entitlements live on the server (architecture decision 6). The apps only read them.
import { pricing } from '../config.ts';
import { HttpError, addMonths } from './util.ts';
import { one, type Queryable, pool } from '../db.ts';

export interface WeddingPlanInfo {
  plan: 'free' | 'pass';
  coveredBy: 'pass' | 'studio' | null;
  whiteLabel: boolean;
  lastEventAt: Date | null;
  readOnly: boolean;           // pass access ended → keepsake, read-only
  limits: { guests: number | null; events: number | null; premiumTemplates: boolean; export: boolean; branding: boolean; uploads: boolean; seating: boolean; planning: boolean };
}

export async function planInfo(weddingId: string, db: Queryable = pool): Promise<WeddingPlanInfo> {
  const w = await one<{ plan: 'free' | 'pass'; last: Date | null; studio: boolean; white_label: boolean }>(
    `SELECT w.plan, (SELECT max(coalesce(ends_at, starts_at)) FROM events e WHERE e.wedding_id = w.id) AS last,
       (w.covered_by_studio AND p.studio_until > now()) AS studio,
       (p.plan <> 'free' AND p.studio_until > now()) AS white_label
     FROM weddings w LEFT JOIN planners p ON p.id = w.planner_id WHERE w.id = $1`, [weddingId], db);
  if (!w) throw new HttpError(404, 'wedding_not_found');
  // A Studio wedding is covered only while the planner's subscription is paid, so a one-month
  // Studio can't be used to resell cheap passes.
  const pass = w.plan === 'pass' || !!w.studio;
  const readOnly = pass && !!w.last && addMonths(w.last, pricing.passAccessMonthsAfterLastEvent) < new Date();
  return {
    plan: pass ? 'pass' : 'free',
    coveredBy: w.plan === 'pass' ? 'pass' : w.studio ? 'studio' : null,
    whiteLabel: !!w.white_label,
    lastEventAt: w.last,
    readOnly,
    limits: {
      guests: pass ? null : pricing.freeGuestLimit,
      events: pass ? null : pricing.freeEventLimit,
      premiumTemplates: pass,
      export: pass,
      branding: !pass,
      uploads: pass,
      seating: pass,
      planning: pass,
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

/** Seating, guestbook, album, budget, checklist and run sheet are Wedding Pass features. */
export async function assertFeature(weddingId: string, feature: 'uploads' | 'seating' | 'planning', db: Queryable = pool) {
  const info = await planInfo(weddingId, db);
  if (!info.limits[feature]) {
    const names = { uploads: 'Guest photos, the photo wall and the guestbook', seating: 'Seating', planning: 'Budget, checklist and run sheet' };
    throw paywall(feature, `${names[feature]} are part of the Wedding Pass.`);
  }
}
