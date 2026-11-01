// Publishes a wedding's guest page as static files (architecture decision 1):
//   site/<slug>/index.html         shared shell (cached by the CDN)
//   site/<slug>/g/<token>.json     one small file per guest (no phone numbers)
// Guest traffic only reaches the API to send an RSVP or record an open.
import { q, one, pool, type Queryable } from '../db.ts';
import { config } from '../config.ts';
import { storage } from './storage.ts';
import { renderGuestPage, type GuestJson, type RenderEvent } from './renderer.ts';
import { planInfo } from './entitlements.ts';

export function guestLink(slug: string, token: string) {
  return `${config.guestBaseUrl}/${slug}/#t=${token}`;
}
export function openLink(slug: string, openToken: string) {
  return `${config.guestBaseUrl}/${slug}/#o=${openToken}`;
}

export async function loadRenderInput(weddingId: string, db: Queryable = pool) {
  const w = await one(`SELECT w.*, t.layout, t.premium FROM weddings w LEFT JOIN templates t ON t.id = w.template_id WHERE w.id=$1`, [weddingId], db);
  if (!w) throw new Error('wedding not found');
  const events = await q<RenderEvent>(
    `SELECT id, kind, title, starts_at, ends_at, nekath, venue, address, maps_url, dress_code, programme
     FROM events WHERE wedding_id=$1 ORDER BY starts_at, sort`, [weddingId], db);
  const info = await planInfo(weddingId, db);
  const fallback = await one('SELECT id, layout FROM templates ORDER BY sort LIMIT 1', [], db);
  return {
    w,
    input: {
      wedding: {
        slug: w.slug, kind: w.kind, partner1: w.partner1, partner2: w.partner2, language: w.language,
        invitation: w.invitation, hasOpenLink: !!w.open_link_token,
      },
      template: w.layout ? { id: w.template_id, layout: w.layout } : { id: fallback.id, layout: fallback.layout },
      events: events.map((e) => ({ ...e, starts_at: new Date(e.starts_at).toISOString(), ends_at: e.ends_at ? new Date(e.ends_at).toISOString() : null })),
      showBranding: info.limits.branding,
      apiUrl: `${config.publicApiUrl}/api`,
      siteUrl: `${config.guestBaseUrl}/${w.slug}/`,
      signupUrl: config.webPanelUrl,
    },
  };
}

export async function guestJson(guestId: string, db: Queryable = pool): Promise<{ slug: string; token: string; json: GuestJson } | null> {
  const g = await one(
    `SELECT g.id, g.name, g.title, g.seats, g.token, w.slug FROM guests g JOIN weddings w ON w.id=g.wedding_id WHERE g.id=$1`, [guestId], db);
  if (!g) return null;
  const evs = await q<{ event_id: string }>('SELECT event_id FROM guest_events WHERE guest_id=$1', [guestId], db);
  const rs = await q('SELECT event_id, status, headcount, meal, dietary, message FROM rsvps WHERE guest_id=$1', [guestId], db);
  return {
    slug: g.slug,
    token: g.token,
    json: {
      name: g.title ? `${g.title} ${g.name}` : g.name,
      seats: g.seats,
      events: evs.map((e) => e.event_id),
      rsvps: Object.fromEntries(rs.map((r) => [r.event_id, { status: r.status, headcount: r.headcount, meal: r.meal, dietary: r.dietary, message: r.message }])),
    },
  };
}

/** Rewrites one guest's JSON if the wedding is published. Cheap; called after edits and RSVPs. */
export async function publishGuest(guestId: string, db: Queryable = pool) {
  const pub = await one('SELECT w.published_at FROM guests g JOIN weddings w ON w.id=g.wedding_id WHERE g.id=$1', [guestId], db);
  if (!pub?.published_at) return;
  const gj = await guestJson(guestId, db);
  if (gj) await storage.put(`site/${gj.slug}/g/${gj.token}.json`, JSON.stringify(gj.json), 'application/json', 'no-cache');
}

export async function unpublishGuestToken(slug: string, token: string) {
  await storage.del(`site/${slug}/g/${token}.json`);
}

/** Full publish: shell + every guest file; removes files for revoked or deleted guests. */
export async function publishWedding(weddingId: string) {
  const { w, input } = await loadRenderInput(weddingId);
  const html = renderGuestPage(input);
  await storage.put(`site/${w.slug}/index.html`, html, 'text/html; charset=utf-8', 'public, max-age=60');
  const guests = await q<{ id: string; token: string }>('SELECT id, token FROM guests WHERE wedding_id=$1', [weddingId]);
  const keep = new Set<string>();
  for (const g of guests) {
    const gj = await guestJson(g.id);
    if (!gj) continue;
    keep.add(`${g.token}.json`);
    await storage.put(`site/${w.slug}/g/${g.token}.json`, JSON.stringify(gj.json), 'application/json', 'no-cache');
  }
  for (const f of await storage.list(`site/${w.slug}/g`)) {
    const name = f.split('/').pop()!;
    if (!keep.has(name)) await storage.del(f);
  }
  return { html, guests: guests.length };
}
