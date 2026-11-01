import { createHmac } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { config } from '../config.ts';
import { one, q, pool, tx } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { requireUser } from '../lib/auth.ts';
import { assertCanAddEvent, paywall, planInfo } from '../lib/entitlements.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { loadRenderInput, openLink, publishWedding } from '../lib/publisher.ts';
import { renderGuestPage } from '../lib/renderer.ts';
import { HttpError, bad, int, notFound, oneOf, randomToken, safeEqual, sha256, str } from '../lib/util.ts';
import { fill } from '../lib/i18n.ts';

const KINDS = ['wedding', 'engagement', 'homecoming', 'other'] as const;
const TYPES = ['buddhist', 'hindu', 'muslim', 'christian', 'civil', 'mixed'] as const;
const EVENT_KINDS = ['poruwa', 'church', 'nikah', 'kovil', 'registration', 'reception', 'homecoming', 'engagement', 'other'] as const;
const LANGS = ['en', 'si', 'ta'] as const;

const DEFAULT_EVENT: Record<string, string> = { buddhist: 'poruwa', hindu: 'kovil', muslim: 'nikah', christian: 'church', civil: 'registration', mixed: 'reception' };

function parseDate(v: unknown, field: string): Date {
  const d = new Date(String(v ?? ''));
  if (Number.isNaN(d.getTime())) throw bad('invalid_input', `${field} must be a date and time`);
  return d;
}

function url(v: unknown, field: string): string | null {
  const s = str(v, field, { max: 1000, optional: true });
  if (s && !/^https:\/\//i.test(s)) throw bad('invalid_input', `${field} must start with https://`);
  return s;
}

// Invitation content the couple can edit. Anything else in the body is ignored.
function cleanInvitation(b: any) {
  const out: Record<string, unknown> = {};
  if (b.message !== undefined) out.message = str(b.message, 'message', { max: 2000, optional: true });
  if (b.parents !== undefined) out.parents = str(b.parents, 'parents', { max: 300, optional: true });
  if (b.cover_photo_url !== undefined) out.cover_photo_url = url(b.cover_photo_url, 'cover_photo_url');
  if (b.music_url !== undefined) out.music_url = url(b.music_url, 'music_url');
  if (b.photos !== undefined) {
    if (!Array.isArray(b.photos) || b.photos.length > 12) throw bad('invalid_input', 'photos must be a list of up to 12 links');
    out.photos = b.photos.map((p: unknown, i: number) => url(p, `photos[${i}]`)).filter(Boolean);
  }
  if (b.meal_options !== undefined) out.meal_options = !!b.meal_options;
  return out;
}

export async function weddingSummary(weddingId: string, role: string) {
  const w = await one(`SELECT id, kind, partner1, partner2, wedding_type, district, expected_guests, mode, language, plan, paid_at,
      template_id, invitation, slug, open_link_token, published_at, created_at, planner_id, showcase FROM weddings WHERE id=$1`, [weddingId]);
  const events = await q('SELECT * FROM events WHERE wedding_id=$1 ORDER BY starts_at, sort', [weddingId]);
  const c = await one(`SELECT count(*)::int AS guests, count(*) FILTER (WHERE sent_at IS NOT NULL)::int AS sent,
      count(*) FILTER (WHERE opened_at IS NOT NULL)::int AS opened,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM rsvps r WHERE r.guest_id=g.id))::int AS replied,
      coalesce(sum(seats),0)::int AS seats
      FROM guests g WHERE wedding_id=$1`, [weddingId]);
  const info = await planInfo(weddingId);
  const { open_link_token, ...rest } = w;
  return {
    wedding: { ...rest, open_link: open_link_token ? openLink(w.slug, open_link_token) : null, page_url: `${config.guestBaseUrl}/${w.slug}/` },
    role, events, counts: c, plan: info,
    nextStep: nextStep(w, events.length, c),
    suggestAdvanced: w.mode === 'easy' && (c.guests > 150 || events.length > 1),
  };
}

/** Easy Mode shows one clear next step. */
function nextStep(w: any, events: number, c: any): { key: string; label: string } {
  if (!events) return { key: 'add_event', label: 'Add the date and venue' };
  if (!w.template_id) return { key: 'choose_template', label: 'Choose an invitation design' };
  if (!w.published_at) return { key: 'publish', label: 'Preview and publish your invitation' };
  if (c.guests < 5) return { key: 'add_guests', label: 'Add at least five guests' };
  if (c.sent < c.guests) return { key: 'send', label: `Send invitations (${c.guests - c.sent} to go)` };
  if (c.replied < c.guests) return { key: 'follow_up', label: 'Remind guests who have not replied' };
  return { key: 'done', label: 'Everyone has replied. Well done!' };
}

export default async function weddingRoutes(app: FastifyInstance) {
  app.get('/weddings', async (req) => {
    const u = await requireUser(req);
    const rows = await q(`SELECT w.id, w.kind, w.partner1, w.partner2, w.plan, m.role,
        (SELECT min(starts_at) FROM events e WHERE e.wedding_id=w.id) AS first_event
      FROM wedding_members m JOIN weddings w ON w.id=m.wedding_id WHERE m.user_id=$1 ORDER BY w.created_at DESC`, [u.id]);
    return { weddings: rows };
  });

  // First-run: what are you planning, names, date, venue, mode.
  app.post('/weddings', async (req) => {
    const u = await requireUser(req);
    const b = req.body as any;
    const kind = oneOf(b.kind, 'kind', KINDS, 'wedding');
    const type = oneOf(b.wedding_type, 'wedding_type', TYPES, 'buddhist');
    const partner1 = str(b.partner1, 'partner1', { max: 60 })!;
    const partner2 = str(b.partner2, 'partner2', { max: 60 })!;
    const language = oneOf(b.language, 'language', LANGS, (u.locale as any) ?? 'en');
    const mode = oneOf(b.mode, 'mode', ['easy', 'advanced'] as const, 'easy');
    const id = await tx(async (c) => {
      const w = await one(`INSERT INTO weddings (owner_id, kind, partner1, partner2, wedding_type, district, expected_guests, mode, language, slug, template_id)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
        [u.id, kind, partner1, partner2, type, str(b.district, 'district', { max: 60, optional: true }),
          b.expected_guests ? int(b.expected_guests, 'expected_guests', 1, 5000) : null, mode, language, randomToken(9),
          b.template_id ? str(b.template_id, 'template_id', { max: 60 }) : null], c);
      await c.query(`INSERT INTO wedding_members (wedding_id, user_id, role) VALUES ($1,$2,'owner')`, [w.id, u.id]);
      // Growth: who brought this couple (a friend's code, a partner QR code, or a guest page).
      const code = typeof b.code === 'string' ? b.code.trim().toUpperCase() : '';
      if (code) {
        const partner = (await c.query('SELECT code FROM partner_codes WHERE code=$1 AND active', [code])).rows[0];
        const ref = partner ? null : (await c.query('SELECT code, user_id FROM referral_codes WHERE code=$1', [code])).rows[0];
        if (partner) { await c.query('UPDATE weddings SET partner_code=$2 WHERE id=$1', [w.id, code]); await c.query('UPDATE partner_codes SET uses=uses+1 WHERE code=$1', [code]); }
        else if (ref && ref.user_id !== u.id) await c.query('UPDATE weddings SET referral_code=$2 WHERE id=$1', [w.id, code]);
      }
      if (typeof b.from_slug === 'string' && /^[A-Za-z0-9_-]{6,20}$/.test(b.from_slug)) await c.query('UPDATE weddings SET source_slug=$2 WHERE id=$1', [w.id, b.from_slug]);
      if (b.event?.starts_at) {
        const ek = kind === 'wedding' ? DEFAULT_EVENT[type] : kind === 'other' ? 'other' : kind;
        await c.query(`INSERT INTO events (wedding_id, kind, starts_at, venue, address, maps_url) VALUES ($1,$2,$3,$4,$5,$6)`,
          [w.id, oneOf(b.event.kind, 'event.kind', EVENT_KINDS, ek as any), parseDate(b.event.starts_at, 'event.starts_at'),
            str(b.event.venue, 'event.venue', { max: 120, optional: true }), str(b.event.address, 'event.address', { max: 300, optional: true }),
            url(b.event.maps_url, 'event.maps_url')]);
      }
      return w.id as string;
    });
    return weddingSummary(id, 'owner');
  });

  app.get('/weddings/:weddingId', async (req) => {
    const a = await weddingAccess(req, 'view');
    return weddingSummary(a.weddingId, a.role);
  });

  app.patch('/weddings/:weddingId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const sets: string[] = [];
    const vals: unknown[] = [a.weddingId];
    const set = (col: string, v: unknown) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
    if (b.partner1 !== undefined) set('partner1', str(b.partner1, 'partner1', { max: 60 }));
    if (b.partner2 !== undefined) set('partner2', str(b.partner2, 'partner2', { max: 60 }));
    if (b.kind !== undefined) set('kind', oneOf(b.kind, 'kind', KINDS));
    if (b.wedding_type !== undefined) set('wedding_type', oneOf(b.wedding_type, 'wedding_type', TYPES));
    if (b.district !== undefined) set('district', str(b.district, 'district', { max: 60, optional: true }));
    if (b.expected_guests !== undefined) set('expected_guests', b.expected_guests === null ? null : int(b.expected_guests, 'expected_guests', 1, 5000));
    if (b.mode !== undefined) set('mode', oneOf(b.mode, 'mode', ['easy', 'advanced'] as const));
    if (b.language !== undefined) set('language', oneOf(b.language, 'language', LANGS));
    if (b.template_id !== undefined) {
      const t = await one(`SELECT t.id, t.premium FROM templates t, weddings w WHERE t.id=$1 AND t.published AND w.id=$2
        AND (t.partner_code IS NULL OR t.partner_code = w.partner_code)`, [b.template_id, a.weddingId]);
      if (!t) throw bad('invalid_template');
      // Premium designs can be previewed by anyone (preview?template=...) but only chosen with the pass.
      if (t.premium && !(await planInfo(a.weddingId)).limits.premiumTemplates) {
        throw paywall('premium_template', 'This design is part of the Wedding Pass. Choose a free design or upgrade.');
      }
      set('template_id', t.id);
    }
    if (b.invitation !== undefined) {
      vals.push(JSON.stringify(cleanInvitation(b.invitation ?? {})));
      sets.push(`invitation = invitation || $${vals.length}::jsonb`);
    }
    if (!sets.length) throw bad('nothing_to_update');
    await pool.query(`UPDATE weddings SET ${sets.join(', ')} WHERE id=$1`, vals);
    const w = await one('SELECT published_at FROM weddings WHERE id=$1', [a.weddingId]);
    if (w.published_at) await enqueuePublish(a.weddingId);
    return weddingSummary(a.weddingId, a.role);
  });

  app.delete('/weddings/:weddingId', async (req) => {
    const a = await weddingAccess(req, 'owner', { write: false });
    if ((req.body as any)?.confirm !== 'DELETE') throw bad('confirm_required');
    const paid = await one(`SELECT 1 FROM payments WHERE wedding_id=$1 LIMIT 1`, [a.weddingId]);
    if (paid) throw new HttpError(409, 'has_payments', 'Weddings with payments are archived by support rather than deleted.');
    const w = await one('SELECT slug FROM weddings WHERE id=$1', [a.weddingId]);
    await pool.query('DELETE FROM weddings WHERE id=$1', [a.weddingId]);
    const { storage } = await import('../lib/storage.ts');
    await storage.del(`site/${w.slug}`);
    return { deleted: true };
  });

  // ---- Events ----
  function eventValues(b: any, partial: boolean) {
    const v: Record<string, unknown> = {};
    if (!partial || b.kind !== undefined) v.kind = oneOf(b.kind, 'kind', EVENT_KINDS);
    if (b.title !== undefined) v.title = str(b.title, 'title', { max: 80, optional: true });
    if (!partial || b.starts_at !== undefined) v.starts_at = parseDate(b.starts_at, 'starts_at');
    if (b.ends_at !== undefined) v.ends_at = b.ends_at ? parseDate(b.ends_at, 'ends_at') : null;
    for (const [k, max] of [['nekath', 120], ['venue', 120], ['address', 300], ['dress_code', 120]] as const) {
      if (b[k] !== undefined) v[k] = str(b[k], k, { max, optional: true });
    }
    if (b.maps_url !== undefined) v.maps_url = url(b.maps_url, 'maps_url');
    if (b.programme !== undefined) {
      if (!Array.isArray(b.programme) || b.programme.length > 30) throw bad('invalid_input', 'programme must be a list');
      v.programme = JSON.stringify(b.programme.map((p: any) => ({ time: str(p.time, 'programme.time', { max: 20 }), item: str(p.item, 'programme.item', { max: 120 }) })));
    }
    return v;
  }

  app.post('/weddings/:weddingId/events', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertCanAddEvent(a.weddingId);
    const v = eventValues(req.body, false);
    const cols = Object.keys(v);
    const ev = await one(`INSERT INTO events (wedding_id, ${cols.join(',')}) VALUES ($1, ${cols.map((_, i) => `$${i + 2}`).join(',')}) RETURNING *`,
      [a.weddingId, ...Object.values(v)]);
    // New events are not added to existing guests automatically; the couple chooses (Advanced Mode),
    // except when the wedding has only one other event, where everyone is invited to both by default.
    if ((req.body as any)?.invite_all !== false) {
      await pool.query(`INSERT INTO guest_events (guest_id, event_id) SELECT id, $2 FROM guests WHERE wedding_id=$1 ON CONFLICT DO NOTHING`, [a.weddingId, ev.id]);
    }
    await enqueuePublish(a.weddingId);
    return { event: ev };
  });

  app.patch('/weddings/:weddingId/events/:eventId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const v = eventValues(req.body, true);
    const cols = Object.keys(v);
    if (!cols.length) throw bad('nothing_to_update');
    const ev = await one(`UPDATE events SET ${cols.map((c, i) => `${c}=$${i + 3}`).join(',')} WHERE id=$2 AND wedding_id=$1 RETURNING *`,
      [a.weddingId, (req.params as any).eventId, ...Object.values(v)]);
    if (!ev) throw notFound('event_not_found');
    await enqueuePublish(a.weddingId);
    return { event: ev };
  });

  app.delete('/weddings/:weddingId/events/:eventId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const n = await one('SELECT count(*)::int AS n FROM events WHERE wedding_id=$1', [a.weddingId]);
    if (n.n <= 1) throw bad('last_event', 'A wedding needs at least one event.');
    const r = await pool.query('DELETE FROM events WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).eventId]);
    if (!r.rowCount) throw notFound('event_not_found');
    await enqueuePublish(a.weddingId);
    return { deleted: true };
  });

  // ---- Co-owners ----
  app.get('/weddings/:weddingId/members', async (req) => {
    const a = await weddingAccess(req, 'view');
    const rows = await q(`SELECT u.id, u.name, u.email, u.phone, m.role FROM wedding_members m JOIN users u ON u.id=m.user_id WHERE m.wedding_id=$1 ORDER BY m.created_at`, [a.weddingId]);
    return { members: rows };
  });

  app.post('/weddings/:weddingId/members/invite', async (req) => {
    const a = await weddingAccess(req, 'owner');
    const role = oneOf((req.body as any)?.role, 'role', ['edit_all', 'edit_guests', 'view'] as const);
    const token = randomToken(18);
    await pool.query(`INSERT INTO member_invites (token_hash, wedding_id, role, created_by, expires_at) VALUES ($1,$2,$3,$4, now() + interval '14 days')`,
      [sha256(token), a.weddingId, role, a.user.id]);
    const w = await one('SELECT partner1, partner2 FROM weddings WHERE id=$1', [a.weddingId]);
    const link = `${config.webPanelUrl}/#join=${token}`;
    return { link, token, message: fill('{couple} invited you to help plan their wedding. Open this link to join: {link}', { couple: `${w.partner1} & ${w.partner2}`, link }) };
  });

  app.post('/invites/:token/accept', async (req) => {
    const u = await requireUser(req);
    const inv = await one(`UPDATE member_invites SET accepted_by=$2, accepted_at=now()
      WHERE token_hash=$1 AND accepted_by IS NULL AND expires_at > now() RETURNING wedding_id, role`, [sha256((req.params as any).token), u.id]);
    if (!inv) throw new HttpError(410, 'invite_expired', 'This invite link has expired or was already used.');
    await pool.query(`INSERT INTO wedding_members (wedding_id, user_id, role) VALUES ($1,$2,$3) ON CONFLICT (wedding_id, user_id) DO NOTHING`,
      [inv.wedding_id, u.id, inv.role]);
    return { weddingId: inv.wedding_id, role: inv.role };
  });

  app.patch('/weddings/:weddingId/members/:userId', async (req) => {
    const a = await weddingAccess(req, 'owner');
    const role = oneOf((req.body as any)?.role, 'role', ['edit_all', 'edit_guests', 'view'] as const);
    const r = await pool.query(`UPDATE wedding_members SET role=$3 WHERE wedding_id=$1 AND user_id=$2 AND role <> 'owner'`, [a.weddingId, (req.params as any).userId, role]);
    if (!r.rowCount) throw notFound('member_not_found');
    return { ok: true };
  });

  app.delete('/weddings/:weddingId/members/:userId', async (req) => {
    const a = await weddingAccess(req, 'view', { write: false });
    const target = (req.params as any).userId;
    if (target !== a.user.id && a.role !== 'owner') throw new HttpError(403, 'insufficient_role');
    const r = await pool.query(`DELETE FROM wedding_members WHERE wedding_id=$1 AND user_id=$2 AND role <> 'owner'`, [a.weddingId, target]);
    if (!r.rowCount) throw notFound('member_not_found');
    return { ok: true };
  });

  // ---- Templates, wording, preview, publish ----
  // Co-branded templates appear only for weddings that came through that partner's code.
  app.get('/templates', async (req) => {
    const wid = (req.query as any).wedding;
    const code = wid && /^[0-9a-f-]{36}$/i.test(wid) ? (await one('SELECT partner_code FROM weddings WHERE id=$1', [wid]))?.partner_code ?? null : null;
    return { templates: await q('SELECT id, name, category, premium, layout, partner_code FROM templates WHERE published AND (partner_code IS NULL OR partner_code=$1) ORDER BY (partner_code IS NULL), sort', [code]) };
  });

  app.get('/wordings', async (req) => {
    const { language, tone, event_kind } = req.query as any;
    const rows = await q(`SELECT id, language, tone, event_kind, body FROM wordings WHERE published
      AND ($1::text IS NULL OR language=$1) AND ($2::text IS NULL OR tone=$2) AND ($3::text IS NULL OR event_kind=$3) ORDER BY language, tone`,
      [language ?? null, tone ?? null, event_kind ?? null]);
    return { wordings: rows };
  });

  // Wording assistant: fills a template with this wedding's names, date and venue.
  app.post('/weddings/:weddingId/wording/:wordingId/fill', async (req) => {
    const a = await weddingAccess(req, 'view');
    const w = await one('SELECT partner1, partner2, invitation, language FROM weddings WHERE id=$1', [a.weddingId]);
    const wd = await one('SELECT body, language FROM wordings WHERE id=$1', [(req.params as any).wordingId]);
    if (!wd) throw notFound('wording_not_found');
    const ev = await one('SELECT starts_at, venue FROM events WHERE wedding_id=$1 ORDER BY starts_at LIMIT 1', [a.weddingId]);
    const loc = wd.language === 'si' ? 'si-LK' : wd.language === 'ta' ? 'ta-LK' : 'en-GB';
    const date = ev ? new Date(ev.starts_at).toLocaleDateString(loc, { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Colombo' }) : '…';
    const joiner = wd.language === 'si' ? ' සහ ' : wd.language === 'ta' ? ' மற்றும் ' : ' & ';
    return {
      text: fill(wd.body, { couple: `${w.partner1}${joiner}${w.partner2}`, date, venue: ev?.venue ?? '…', parents: w.invitation?.parents ?? (wd.language === 'en' ? 'Our families' : '…') }),
    };
  });

  // Preview: exactly the HTML guests get, with a sample guest embedded. The app asks for a
  // signed link valid for 30 minutes and opens it in an in-app browser (iOS, Android, web alike).
  app.post('/weddings/:weddingId/preview-link', async (req) => {
    const a = await weddingAccess(req, 'view');
    const exp = Date.now() + 30 * 60_000;
    const template = String((req.body as any)?.template ?? '');
    const sig = createHmac('sha256', config.previewSecret).update(`${a.weddingId}:${exp}:${template}`).digest('base64url');
    const qs = new URLSearchParams({ exp: String(exp), sig, ...(template ? { template } : {}) });
    return { url: `${config.publicApiUrl}/api/preview/${a.weddingId}?${qs}` };
  });

  app.get('/preview/:weddingId', async (req, reply) => {
    const { exp, sig, template = '' } = req.query as any;
    const weddingId = (req.params as any).weddingId;
    const want = createHmac('sha256', config.previewSecret).update(`${weddingId}:${exp}:${template}`).digest('base64url');
    if (!sig || !safeEqual(String(sig), want) || Number(exp) < Date.now()) throw new HttpError(403, 'preview_link_expired');
    return sendPreview(reply, weddingId, template, (req.query as any).name);
  });

  app.get('/weddings/:weddingId/preview', async (req, reply) => {
    const a = await weddingAccess(req, 'view');
    return sendPreview(reply, a.weddingId, (req.query as any).template, (req.query as any).name);
  });

  async function sendPreview(reply: any, weddingId: string, templateId?: string, name?: string) {
    const { input } = await loadRenderInput(weddingId);
    if (templateId) {
      const t = await one('SELECT id, layout FROM templates WHERE id=$1 AND published', [templateId]);
      if (t) input.template = t;
    }
    const html = renderGuestPage({
      ...input,
      preview: { guest: { name: name || 'Nimal & family', seats: 2, events: input.events.map((e) => e.id), rsvps: {} } },
    });
    return reply.type('text/html; charset=utf-8').header('cache-control', 'no-store').send(html);
  }

  app.post('/weddings/:weddingId/publish', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const w = await one('SELECT w.template_id, t.premium FROM weddings w LEFT JOIN templates t ON t.id=w.template_id WHERE w.id=$1', [a.weddingId]);
    const info = await planInfo(a.weddingId);
    if (!w.template_id) throw bad('choose_template_first', 'Choose a design before publishing.');
    if (w.premium && !info.limits.premiumTemplates) throw paywall('premium_template', 'This design is part of the Wedding Pass. Choose a free design or upgrade.');
    const ev = await one('SELECT 1 FROM events WHERE wedding_id=$1', [a.weddingId]);
    if (!ev) throw bad('add_event_first', 'Add the date and venue before publishing.');
    await pool.query('UPDATE weddings SET published_at = coalesce(published_at, now()) WHERE id=$1', [a.weddingId]);
    await publishWedding(a.weddingId);
    return weddingSummary(a.weddingId, a.role);
  });

  // Open group link for very large lists: guests type their name and are matched.
  app.post('/weddings/:weddingId/open-link', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const enable = (req.body as any)?.enabled !== false;
    await pool.query('UPDATE weddings SET open_link_token=$2 WHERE id=$1', [a.weddingId, enable ? randomToken(12) : null]);
    await enqueuePublish(a.weddingId);
    return weddingSummary(a.weddingId, a.role);
  });
}
