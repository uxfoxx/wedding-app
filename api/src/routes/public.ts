// The only API calls guest pages make: send an RSVP, record an open, claim an open link.
import type { FastifyInstance } from 'fastify';
import { one, q, tx } from '../db.ts';
import { matchGuestName } from '../lib/duplicates.ts';
import { assertCanAddGuests } from '../lib/entitlements.ts';
import { guestJson, publishGuest } from '../lib/publisher.ts';
import { HttpError, bad, int, oneOf, randomToken, str } from '../lib/util.ts';

const TOKEN_RE = /^[A-Za-z0-9_-]{16,64}$/;

async function guestByToken(token: unknown) {
  if (typeof token !== 'string' || !TOKEN_RE.test(token)) throw new HttpError(404, 'invalid_link');
  const g = await one(`SELECT g.id, g.seats, g.wedding_id, w.contacts_purged_at FROM guests g JOIN weddings w ON w.id=g.wedding_id WHERE g.token=$1`, [token]);
  if (!g) throw new HttpError(404, 'invalid_link');
  return g;
}

export default async function publicRoutes(app: FastifyInstance) {
  app.post('/public/rsvp', { config: { rateLimit: 30 } }, async (req) => {
    const b = req.body as any;
    const g = await guestByToken(b?.token);
    if (!Array.isArray(b.responses) || !b.responses.length || b.responses.length > 10) throw bad('invalid_input');
    const invited = new Set((await q('SELECT event_id FROM guest_events WHERE guest_id=$1', [g.id])).map((r) => r.event_id));
    const dietary = str(b.dietary, 'dietary', { max: 200, optional: true });
    const msg = str(b.message, 'message', { max: 1000, optional: true });
    await tx(async (c) => {
      for (const r of b.responses) {
        if (!invited.has(r.event_id)) throw bad('not_invited_to_event');
        const status = oneOf(r.status, 'status', ['coming', 'not_coming', 'maybe'] as const);
        const headcount = status === 'not_coming' ? 0 : int(r.headcount, 'headcount', 1, g.seats, g.seats);
        const meal = r.meal ? oneOf(r.meal, 'meal', ['vegetarian', 'vegan', 'halal'] as const) : null;
        await c.query(`INSERT INTO rsvps (guest_id, event_id, status, headcount, meal, dietary, message) VALUES ($1,$2,$3,$4,$5,$6,$7)
          ON CONFLICT (guest_id, event_id) DO UPDATE SET status=EXCLUDED.status, headcount=EXCLUDED.headcount, meal=EXCLUDED.meal,
            dietary=EXCLUDED.dietary, message=EXCLUDED.message, updated_at=now()`,
          [g.id, r.event_id, status, headcount, meal, dietary, msg]);
      }
      await c.query('UPDATE guests SET opened_at = coalesce(opened_at, now()) WHERE id=$1', [g.id]);
    });
    await publishGuest(g.id);
    return { ok: true, guest: (await guestJson(g.id))!.json };
  });

  // Sent by the page's script only, so WhatsApp's link-preview crawler never counts as an open.
  app.post('/public/open', { config: { rateLimit: 60 } }, async (req) => {
    const token = (req.body as any)?.token;
    if (typeof token === 'string' && TOKEN_RE.test(token)) {
      await q('UPDATE guests SET opened_at = now() WHERE token=$1 AND opened_at IS NULL', [token]);
    }
    return { ok: true };
  });

  // Open group link: the guest types their name. A confident match returns that guest's link;
  // otherwise a new guest is added (marked "open_link" for the couple to review), within the plan limit.
  app.post('/public/claim', { config: { rateLimit: 10 } }, async (req) => {
    const b = req.body as any;
    const name = str(b?.name, 'name', { max: 80 })!;
    if (name.length < 3) throw bad('name_too_short');
    const w = await one('SELECT id, open_link_token FROM weddings WHERE slug=$1', [String(b?.slug ?? '')]);
    if (!w?.open_link_token || w.open_link_token !== b?.open) throw new HttpError(404, 'invalid_link');
    const guests = await q<{ id: string; name: string; token: string }>(`SELECT id, name, token FROM guests WHERE wedding_id=$1`, [w.id]);
    const match = matchGuestName(name, guests);
    if (match) return { token: match.token, matched: true };
    try {
      const token = await tx(async (c) => {
        await c.query('SELECT 1 FROM weddings WHERE id=$1 FOR UPDATE', [w.id]);
        await assertCanAddGuests(w.id, 1, c);
        const t = randomToken(16);
        const r = await c.query(`INSERT INTO guests (wedding_id, name, seats, token, source, opened_at, tags) VALUES ($1,$2,1,$3,'open_link', now(), '{needs_review}') RETURNING id`, [w.id, name, t]);
        await c.query('INSERT INTO guest_events SELECT $1, id FROM events WHERE wedding_id=$2', [r.rows[0].id, w.id]);
        return { t, id: r.rows[0].id };
      });
      await publishGuest(token.id);
      return { token: token.t, matched: false };
    } catch (e: any) {
      if (e?.code === 'upgrade_required') throw new HttpError(404, 'not_found');
      throw e;
    }
  });
}
