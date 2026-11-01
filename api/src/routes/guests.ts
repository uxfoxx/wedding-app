import type { FastifyInstance } from 'fastify';
import { one, q, pool, tx } from '../db.ts';
import { pricing } from '../config.ts';
import { weddingAccess } from '../lib/access.ts';
import { assertCanAddGuests, paywall, planInfo } from '../lib/entitlements.ts';
import { findDuplicates } from '../lib/duplicates.ts';
import { parseGuestCsv, parsePastedGuests } from '../lib/guestImport.ts';
import { eventNames, fill, inviteMessage, kindWords, reminderMessage, type Lang } from '../lib/i18n.ts';
import { normalizePhone, waDigits } from '../lib/phone.ts';
import { guestLink, publishGuest, unpublishGuestToken } from '../lib/publisher.ts';
import { bad, int, notFound, oneOf, randomToken, str } from '../lib/util.ts';

const SIDES = ['bride', 'groom', 'both'] as const;

interface GuestInput {
  name: string; title?: string | null; phone?: string | null; side?: string | null; group_name?: string | null;
  vip?: boolean; seats?: number; dietary?: string | null; notes?: string | null; tags?: string[]; event_ids?: string[];
}

function cleanGuest(b: any, partial = false): Partial<GuestInput> {
  const g: Partial<GuestInput> = {};
  if (!partial || b.name !== undefined) g.name = str(b.name, 'name', { max: 100 })!;
  if (b.title !== undefined) g.title = str(b.title, 'title', { max: 30, optional: true });
  if (b.phone !== undefined) {
    const raw = str(b.phone, 'phone', { max: 30, optional: true });
    g.phone = raw ? normalizePhone(raw) : null;
    if (raw && !g.phone) throw bad('invalid_phone', 'That phone number could not be read. Use 07X XXX XXXX, or +country code for numbers abroad.');
  }
  if (b.side !== undefined) g.side = b.side ? oneOf(b.side, 'side', SIDES) : null;
  if (b.group_name !== undefined) g.group_name = str(b.group_name, 'group_name', { max: 40, optional: true });
  if (b.vip !== undefined) g.vip = !!b.vip;
  if (b.seats !== undefined) g.seats = int(b.seats, 'seats', 1, 30);
  if (b.dietary !== undefined) g.dietary = str(b.dietary, 'dietary', { max: 100, optional: true });
  if (b.notes !== undefined) g.notes = str(b.notes, 'notes', { max: 500, optional: true });
  if (b.tags !== undefined) {
    if (!Array.isArray(b.tags) || b.tags.length > 10) throw bad('invalid_input', 'tags must be a list');
    g.tags = b.tags.map((t: unknown) => str(t, 'tag', { max: 30 })!);
  }
  if (b.event_ids !== undefined) {
    if (!Array.isArray(b.event_ids)) throw bad('invalid_input', 'event_ids must be a list');
    g.event_ids = b.event_ids.map(String);
  }
  return g;
}

async function insertGuests(weddingId: string, guests: Partial<GuestInput>[], source: string) {
  return tx(async (c) => {
    await c.query('SELECT 1 FROM weddings WHERE id=$1 FOR UPDATE', [weddingId]); // serialise the free-plan count check
    await assertCanAddGuests(weddingId, guests.length, c);
    const allEvents = (await c.query('SELECT id FROM events WHERE wedding_id=$1', [weddingId])).rows.map((r) => r.id);
    const ids: string[] = [];
    for (const g of guests) {
      const r = await c.query(
        `INSERT INTO guests (wedding_id, name, title, phone, side, group_name, vip, seats, dietary, notes, tags, token, source)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
        [weddingId, g.name, g.title ?? null, g.phone ?? null, g.side ?? null, g.group_name ?? null, g.vip ?? false, g.seats ?? 1,
          g.dietary ?? null, g.notes ?? null, g.tags ?? [], randomToken(16), source]);
      const id = r.rows[0].id;
      const evs = (g.event_ids ?? allEvents).filter((e) => allEvents.includes(e));
      for (const e of evs) await c.query('INSERT INTO guest_events VALUES ($1,$2) ON CONFLICT DO NOTHING', [id, e]);
      ids.push(id);
    }
    return ids;
  });
}

async function listGuests(weddingId: string) {
  return q(`SELECT g.id, g.name, g.title, g.phone, g.side, g.group_name, g.vip, g.seats, g.dietary, g.notes, g.tags, g.source,
      g.sent_at, g.opened_at, g.created_at,
      coalesce((SELECT array_agg(event_id) FROM guest_events ge WHERE ge.guest_id=g.id), '{}') AS event_ids,
      coalesce((SELECT json_agg(json_build_object('event_id', r.event_id, 'status', r.status, 'headcount', r.headcount, 'meal', r.meal, 'dietary', r.dietary, 'message', r.message, 'updated_at', r.updated_at))
        FROM rsvps r WHERE r.guest_id=g.id), '[]') AS rsvps
    FROM guests g WHERE g.wedding_id=$1 ORDER BY g.vip DESC, g.created_at`, [weddingId]);
}

function message(kind: 'invite' | 'reminder', w: any, guest: { name: string; title: string | null; token: string }) {
  const lang = w.language as Lang;
  const tpl = kind === 'invite' ? inviteMessage[lang] : reminderMessage[lang];
  const joiner = lang === 'si' ? ' සහ ' : lang === 'ta' ? ' மற்றும் ' : ' & ';
  return fill(tpl, {
    name: guest.title ? `${guest.title} ${guest.name}` : guest.name,
    couple: `${w.partner1}${joiner}${w.partner2}`,
    kind: kindWords[lang][w.kind] ?? kindWords[lang].wedding,
    link: guestLink(w.slug, guest.token),
  });
}

function waUrl(phone: string | null, text: string) {
  // Without a number WhatsApp opens the contact picker with the message ready.
  return phone ? `https://wa.me/${waDigits(phone)}?text=${encodeURIComponent(text)}` : `https://wa.me/?text=${encodeURIComponent(text)}`;
}

function csvCell(v: unknown) {
  const s = v == null ? '' : String(v);
  // Neutralise spreadsheet formulas (CSV injection) and quote.
  const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s;
  return `"${safe.replace(/"/g, '""')}"`;
}

export default async function guestRoutes(app: FastifyInstance) {
  app.get('/weddings/:weddingId/guests', async (req) => {
    const a = await weddingAccess(req, 'view');
    const guests = await listGuests(a.weddingId);
    const w = await one('SELECT slug, published_at FROM weddings WHERE id=$1', [a.weddingId]);
    // Links are only useful (and only shown) to people who can send them.
    if (a.role !== 'view' && w.published_at) {
      const toks = await q('SELECT id, token FROM guests WHERE wedding_id=$1', [a.weddingId]);
      const m = new Map(toks.map((t) => [t.id, t.token]));
      for (const g of guests) g.link = guestLink(w.slug, m.get(g.id));
    }
    return { guests };
  });

  app.post('/weddings/:weddingId/guests', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const g = cleanGuest(req.body);
    const [id] = await insertGuests(a.weddingId, [g], 'manual');
    await publishGuest(id);
    const dup = await one('SELECT id, name FROM guests WHERE wedding_id=$1 AND id<>$2 AND phone IS NOT NULL AND phone=$3 LIMIT 1', [a.weddingId, id, g.phone ?? null]);
    return { id, possibleDuplicateOf: dup ?? null };
  });

  // Step 1 of an import: parse and show the rows, with flags, without saving anything.
  app.post('/weddings/:weddingId/guests/import/preview', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const b = req.body as any;
    const format = oneOf(b.format, 'format', ['paste', 'csv', 'contacts'] as const);
    const text = format === 'contacts' ? '' : str(b.text, 'text', { max: 500_000 })!;
    let rows: any[];
    if (format === 'contacts') {
      if (!Array.isArray(b.contacts) || b.contacts.length > 3000) throw bad('invalid_input', 'contacts must be a list');
      rows = b.contacts.map((c: any) => {
        const phone = normalizePhone(c.phone);
        return { name: String(c.name ?? '').trim().slice(0, 100), title: null, phone, seats: 1, dietary: null, flags: c.phone && !phone ? ['phone_unreadable'] : [], raw: '' };
      }).filter((r: any) => r.name);
    } else rows = format === 'csv' ? parseGuestCsv(text) : parsePastedGuests(text);
    // Flag rows that match guests already on the list.
    const existing = await q<{ id: string; name: string; phone: string | null }>('SELECT id, name, phone FROM guests WHERE wedding_id=$1', [a.weddingId]);
    const tmp = rows.map((r, i) => ({ id: `new:${i}`, name: r.name, phone: r.phone }));
    // Flag the later row of each pair: an existing guest always counts as earlier than a new row.
    const order = (id: string) => (id.startsWith('new:') ? existing.length + Number(id.slice(4)) : -1);
    for (const d of findDuplicates([...existing, ...tmp])) {
      const [first, later] = order(d.a) < order(d.b) ? [d.a, d.b] : [d.b, d.a];
      if (!later.startsWith('new:')) continue;
      const r = rows[Number(later.slice(4))];
      if (!r.flags.includes('possible_duplicate')) r.flags.push('possible_duplicate');
      r.duplicateOf ??= first.startsWith('new:') ? rows[Number(first.slice(4))].name : existing.find((e) => e.id === first)?.name;
    }
    const info = await planInfo(a.weddingId);
    return {
      rows,
      limit: info.limits.guests,
      current: existing.length,
      overLimit: info.limits.guests !== null && existing.length + rows.length > info.limits.guests,
    };
  });

  // Step 2: save the rows the couple confirmed.
  app.post('/weddings/:weddingId/guests/import', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const b = req.body as any;
    if (!Array.isArray(b.rows) || !b.rows.length || b.rows.length > 3000) throw bad('invalid_input', 'rows must be a list');
    const source = oneOf(b.source, 'source', ['paste', 'csv', 'contacts'] as const, 'paste');
    const clean = b.rows.map((r: any) => cleanGuest(r));
    const ids = await insertGuests(a.weddingId, clean, source);
    const w = await one('SELECT published_at FROM weddings WHERE id=$1', [a.weddingId]);
    if (w.published_at) for (const id of ids) await publishGuest(id);
    return { added: ids.length };
  });

  app.get('/weddings/:weddingId/guests/duplicates', async (req) => {
    const a = await weddingAccess(req, 'view');
    const guests = await q<{ id: string; name: string; phone: string | null }>('SELECT id, name, phone FROM guests WHERE wedding_id=$1', [a.weddingId]);
    const byId = new Map(guests.map((g) => [g.id, g]));
    return { pairs: findDuplicates(guests).map((p) => ({ ...p, a: byId.get(p.a), b: byId.get(p.b) })) };
  });

  // Merge b into a: keeps a, combines events and RSVPs, deletes b.
  app.post('/weddings/:weddingId/guests/:guestId/merge', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const keep = (req.params as any).guestId;
    const drop = str((req.body as any)?.other_id, 'other_id')!;
    if (keep === drop) throw bad('same_guest');
    const both = await q('SELECT id, token FROM guests WHERE wedding_id=$1 AND id = ANY($2)', [a.weddingId, [keep, drop]]);
    if (both.length !== 2) throw notFound('guest_not_found');
    const slug = (await one('SELECT slug FROM weddings WHERE id=$1', [a.weddingId])).slug;
    await tx(async (c) => {
      await c.query('INSERT INTO guest_events SELECT $1, event_id FROM guest_events WHERE guest_id=$2 ON CONFLICT DO NOTHING', [keep, drop]);
      await c.query(`INSERT INTO rsvps (guest_id, event_id, status, headcount, meal, dietary, message, updated_at)
        SELECT $1, event_id, status, headcount, meal, dietary, message, updated_at FROM rsvps WHERE guest_id=$2 ON CONFLICT DO NOTHING`, [keep, drop]);
      await c.query(`UPDATE guests k SET phone = coalesce(k.phone, d.phone), seats = greatest(k.seats, d.seats),
          sent_at = coalesce(k.sent_at, d.sent_at), opened_at = coalesce(k.opened_at, d.opened_at)
        FROM guests d WHERE k.id=$1 AND d.id=$2`, [keep, drop]);
      await c.query('DELETE FROM guests WHERE id=$1', [drop]);
    });
    await unpublishGuestToken(slug, both.find((g) => g.id === drop).token);
    await publishGuest(keep);
    return { merged: true };
  });

  app.patch('/weddings/:weddingId/guests/:guestId', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const g = cleanGuest(req.body, true);
    const { event_ids, ...cols } = g;
    const id = (req.params as any).guestId;
    await tx(async (c) => {
      const exists = await c.query('SELECT 1 FROM guests WHERE id=$1 AND wedding_id=$2', [id, a.weddingId]);
      if (!exists.rowCount) throw notFound('guest_not_found');
      const keys = Object.keys(cols);
      if (keys.length) {
        await c.query(`UPDATE guests SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(',')} WHERE id=$1`, [id, ...Object.values(cols)]);
      }
      if (event_ids) {
        await c.query('DELETE FROM guest_events WHERE guest_id=$1', [id]);
        await c.query(`INSERT INTO guest_events SELECT $1, e.id FROM events e WHERE e.wedding_id=$2 AND e.id::text = ANY($3)`, [id, a.weddingId, event_ids]);
      }
    });
    await publishGuest(id);
    return { ok: true };
  });

  app.delete('/weddings/:weddingId/guests/:guestId', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const g = await one('DELETE FROM guests g USING weddings w WHERE g.id=$1 AND g.wedding_id=$2 AND w.id=g.wedding_id RETURNING g.token, w.slug', [(req.params as any).guestId, a.weddingId]);
    if (!g) throw notFound('guest_not_found');
    await unpublishGuestToken(g.slug, g.token);
    return { deleted: true };
  });

  // Revoke a guest's link (e.g. it was forwarded) and issue a new one.
  app.post('/weddings/:weddingId/guests/:guestId/new-link', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const old = await one('SELECT g.token, w.slug FROM guests g JOIN weddings w ON w.id=g.wedding_id WHERE g.id=$1 AND g.wedding_id=$2', [(req.params as any).guestId, a.weddingId]);
    if (!old) throw notFound('guest_not_found');
    const token = randomToken(16);
    await pool.query('UPDATE guests SET token=$2, sent_at=NULL, opened_at=NULL WHERE id=$1', [(req.params as any).guestId, token]);
    await unpublishGuestToken(old.slug, old.token);
    await publishGuest((req.params as any).guestId);
    return { link: guestLink(old.slug, token) };
  });

  // ---- Sending ----

  // The WhatsApp send queue: one tap opens WhatsApp with the message ready.
  app.get('/weddings/:weddingId/send-queue', async (req) => {
    const a = await weddingAccess(req, 'edit_guests', { write: false });
    const kind = oneOf((req.query as any).kind, 'kind', ['invite', 'reminder'] as const, 'invite');
    const w = await one('SELECT kind, partner1, partner2, slug, language, published_at FROM weddings WHERE id=$1', [a.weddingId]);
    if (!w.published_at) throw bad('publish_first', 'Publish your invitation before sending it.');
    const rows = kind === 'invite'
      ? await q(`SELECT id, name, title, phone, token, vip FROM guests WHERE wedding_id=$1 AND sent_at IS NULL ORDER BY vip DESC, created_at`, [a.weddingId])
      : await followUpRows(a.weddingId);
    return {
      kind,
      guests: rows.map((g) => {
        const text = message(kind, w, g);
        return { id: g.id, name: g.name, phone: g.phone, vip: g.vip, text, whatsapp: waUrl(g.phone, text), sms: g.phone ? `sms:${g.phone}?&body=${encodeURIComponent(text)}` : null, link: guestLink(w.slug, g.token) };
      }),
    };
  });

  // Marks guests as handed to WhatsApp. The app can't see whether Send was pressed;
  // opens (from the guest page) are the real signal.
  app.post('/weddings/:weddingId/guests/mark-sent', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const ids = (req.body as any)?.guest_ids;
    if (!Array.isArray(ids) || ids.length > 3000) throw bad('invalid_input', 'guest_ids must be a list');
    const r = await pool.query('UPDATE guests SET sent_at = coalesce(sent_at, now()) WHERE wedding_id=$1 AND id::text = ANY($2)', [a.weddingId, ids.map(String)]);
    return { updated: r.rowCount };
  });

  async function followUpRows(weddingId: string) {
    // No reply after 7 days; VIPs first (for a personal call).
    return q(`SELECT g.id, g.name, g.title, g.phone, g.token, g.vip, g.sent_at, g.opened_at FROM guests g
      WHERE g.wedding_id=$1 AND g.sent_at IS NOT NULL AND g.sent_at < now() - make_interval(days => $2)
        AND NOT EXISTS (SELECT 1 FROM rsvps r WHERE r.guest_id=g.id)
      ORDER BY g.vip DESC, g.sent_at`, [weddingId, pricing.followUpAfterDays]);
  }

  app.get('/weddings/:weddingId/follow-ups', async (req) => {
    const a = await weddingAccess(req, 'view');
    const rows = await followUpRows(a.weddingId);
    return { guests: rows.map(({ token, ...g }) => ({ ...g, callFirst: g.vip })) };
  });

  // ---- RSVP dashboard ----
  app.get('/weddings/:weddingId/dashboard', async (req) => {
    const a = await weddingAccess(req, 'view');
    const w = await one('SELECT language FROM weddings WHERE id=$1', [a.weddingId]);
    const totals = await one(`SELECT count(*)::int AS invited, count(*) FILTER (WHERE sent_at IS NOT NULL)::int AS sent,
        count(*) FILTER (WHERE opened_at IS NOT NULL)::int AS opened FROM guests WHERE wedding_id=$1`, [a.weddingId]);
    const events = await q(`SELECT e.id, e.kind, e.title, e.starts_at,
        count(ge.guest_id)::int AS invited,
        coalesce(sum(g.seats),0)::int AS seats_invited,
        count(r.*) FILTER (WHERE r.status='coming')::int AS coming,
        count(r.*) FILTER (WHERE r.status='not_coming')::int AS declined,
        count(r.*) FILTER (WHERE r.status='maybe')::int AS maybe,
        (count(ge.guest_id) - count(r.*))::int AS pending,
        coalesce(sum(r.headcount) FILTER (WHERE r.status='coming'),0)::int AS headcount,
        coalesce(sum(r.headcount) FILTER (WHERE r.status='maybe'),0)::int AS maybe_headcount,
        coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='vegetarian'),0)::int AS meals_vegetarian,
        coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='vegan'),0)::int AS meals_vegan,
        coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='halal'),0)::int AS meals_halal
      FROM events e
      LEFT JOIN guest_events ge ON ge.event_id=e.id
      LEFT JOIN guests g ON g.id=ge.guest_id
      LEFT JOIN rsvps r ON r.guest_id=ge.guest_id AND r.event_id=e.id
      WHERE e.wedding_id=$1 GROUP BY e.id ORDER BY e.starts_at`, [a.weddingId]);
    const lang = w.language as Lang;
    const messages = await q(`SELECT g.name, r.message, r.updated_at FROM rsvps r JOIN guests g ON g.id=r.guest_id
      WHERE g.wedding_id=$1 AND r.message IS NOT NULL ORDER BY r.updated_at DESC LIMIT 20`, [a.weddingId]);
    return {
      totals,
      events: events.map((e) => ({ ...e, name: e.title ?? eventNames[lang][e.kind] })),
      recentMessages: messages.filter((m, i, arr) => arr.findIndex((x) => x.name === m.name && x.message === m.message) === i),
    };
  });

  // ---- Export for the venue and caterer (Wedding Pass) ----
  // CSV opens in Excel. PDF is produced on the device (print view), which renders
  // Sinhala and Tamil correctly and keeps heavy PDF work off the 1 GB server.
  app.get('/weddings/:weddingId/export.csv', async (req, reply) => {
    const a = await weddingAccess(req, 'view');
    const info = await planInfo(a.weddingId);
    if (!info.limits.export) throw paywall('export', 'Exporting the guest list is part of the Wedding Pass.');
    const w = await one('SELECT language FROM weddings WHERE id=$1', [a.weddingId]);
    const events = await q('SELECT id, kind, title FROM events WHERE wedding_id=$1 ORDER BY starts_at', [a.weddingId]);
    const guests = await listGuests(a.weddingId);
    const head = ['Name', 'Title', 'Phone', 'Side', 'Group', 'VIP', 'Seats', 'Dietary', 'Notes',
      ...events.flatMap((e) => { const n = e.title ?? eventNames[w.language as Lang][e.kind]; return [`${n}: invited`, `${n}: reply`, `${n}: people`, `${n}: meal`]; })];
    const lines = [head.map(csvCell).join(',')];
    for (const g of guests) {
      const cells: unknown[] = [g.name, g.title, g.phone, g.side, g.group_name, g.vip ? 'yes' : '', g.seats, g.dietary, g.notes];
      for (const e of events) {
        const r = g.rsvps.find((x: any) => x.event_id === e.id);
        cells.push(g.event_ids.includes(e.id) ? 'yes' : 'no', r?.status ?? '', r?.headcount ?? '', r?.meal ?? '');
      }
      lines.push(cells.map(csvCell).join(','));
    }
    return reply.type('text/csv; charset=utf-8').header('content-disposition', 'attachment; filename="guest-list.csv"').send('﻿' + lines.join('\r\n'));
  });
}
