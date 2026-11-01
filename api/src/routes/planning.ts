// Seating, tasks/checklist, budget, run sheet, readiness, couple-entered RSVPs, printable reports.
import { createHmac } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { config } from '../config.ts';
import { one, q, pool, tx } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { assertFeature } from '../lib/entitlements.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { publishGuest } from '../lib/publisher.ts';
import { readReply } from '../lib/rsvpReader.ts';
import { looksElder, suggestSeating } from '../lib/seating.ts';
import { readiness, suggestedChecklist } from '../lib/planning.ts';
import { eventNames, type Lang } from '../lib/i18n.ts';
import { HttpError, bad, escapeHtml, int, notFound, oneOf, safeEqual, str } from '../lib/util.ts';

function dateOrNull(v: unknown, field: string): string | null {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad('invalid_input', `${field} must be YYYY-MM-DD`);
  return v;
}
const money = (v: unknown, f: string) => (v === undefined || v === null || v === '' ? 0 : int(Math.round(Number(v)), f, 0, 1_000_000_000));

export async function eventOf(weddingId: string, eventId: string) {
  const e = await one('SELECT * FROM events WHERE id=$1 AND wedding_id=$2', [eventId, weddingId]);
  if (!e) throw notFound('event_not_found');
  return e;
}

export default async function planningRoutes(app: FastifyInstance) {
  // =============== Seating ===============
  app.get('/weddings/:weddingId/events/:eventId/seating', async (req) => {
    const a = await weddingAccess(req, 'view');
    const ev = await eventOf(a.weddingId, (req.params as any).eventId);
    const tables = await q('SELECT * FROM seating_tables WHERE event_id=$1 ORDER BY sort, name', [ev.id]);
    // Parties invited to this event, with confirmed size (RSVP headcount) when known.
    const guests = await q(`SELECT g.id, g.name, g.title, g.side, g.group_name, g.vip, g.tags, g.seats,
        r.status, r.headcount, sa.table_id
      FROM guest_events ge JOIN guests g ON g.id=ge.guest_id
      LEFT JOIN rsvps r ON r.guest_id=g.id AND r.event_id=ge.event_id
      LEFT JOIN seat_assignments sa ON sa.guest_id=g.id AND sa.event_id=ge.event_id
      WHERE ge.event_id=$1 AND coalesce(r.status,'') <> 'not_coming'
      ORDER BY g.vip DESC, g.group_name NULLS LAST, g.name`, [ev.id]);
    const conflicts = await q('SELECT a, b FROM guest_conflicts WHERE wedding_id=$1', [a.weddingId]);
    const w = await one('SELECT settings FROM weddings WHERE id=$1', [a.weddingId]);
    return {
      event: ev, tables, conflicts,
      guests: guests.map((g) => ({ ...g, size: g.status === 'coming' ? g.headcount : g.seats })),
      published: !!w.settings?.seating_published,
    };
  });

  app.post('/weddings/:weddingId/events/:eventId/tables', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'seating');
    const ev = await eventOf(a.weddingId, (req.params as any).eventId);
    const b = req.body as any;
    const count = int(b.count ?? 1, 'count', 1, 100);
    const seats = int(b.seats, 'seats', 1, 60);
    const shape = oneOf(b.shape, 'shape', ['round', 'long', 'head'] as const, 'round');
    const existing = (await one('SELECT count(*)::int AS n, coalesce(max(sort),0)::int AS s FROM seating_tables WHERE event_id=$1', [ev.id]));
    const made = [];
    for (let i = 0; i < count; i++) {
      const name = count === 1 && b.name ? str(b.name, 'name', { max: 40 })! : shape === 'head' ? 'Head table' : `Table ${existing.n + i + 1}`;
      made.push(await one(`INSERT INTO seating_tables (wedding_id, event_id, name, shape, seats, sort) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
        [a.weddingId, ev.id, name, shape, seats, shape === 'head' ? -1 : existing.s + i + 1]));
    }
    return { tables: made };
  });

  app.patch('/weddings/:weddingId/tables/:tableId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const t = await one(`UPDATE seating_tables SET name=coalesce($3,name), seats=coalesce($4,seats), shape=coalesce($5,shape), sort=coalesce($6,sort)
      WHERE id=$2 AND wedding_id=$1 RETURNING *`, [a.weddingId, (req.params as any).tableId, b.name ? str(b.name, 'name', { max: 40 }) : null,
        b.seats !== undefined ? int(b.seats, 'seats', 1, 60) : null, b.shape ? oneOf(b.shape, 'shape', ['round', 'long', 'head'] as const) : null,
        b.sort !== undefined ? int(b.sort, 'sort', -1000, 1000) : null]);
    if (!t) throw notFound('table_not_found');
    return { table: t };
  });

  app.delete('/weddings/:weddingId/tables/:tableId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const r = await pool.query('DELETE FROM seating_tables WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).tableId]);
    if (!r.rowCount) throw notFound('table_not_found');
    return { ok: true };
  });

  // Seat one party (table_id null = unseat). Enforces capacity.
  app.put('/weddings/:weddingId/events/:eventId/seats/:guestId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'seating');
    const ev = await eventOf(a.weddingId, (req.params as any).eventId);
    const gid = (req.params as any).guestId;
    const tableId = (req.body as any)?.table_id ?? null;
    if (!(await one('SELECT 1 FROM guest_events ge JOIN guests g ON g.id=ge.guest_id WHERE ge.guest_id=$1 AND ge.event_id=$2 AND g.wedding_id=$3', [gid, ev.id, a.weddingId]))) {
      throw notFound('guest_not_invited_to_event');
    }
    await tx(async (c) => {
      if (!tableId) { await c.query('DELETE FROM seat_assignments WHERE guest_id=$1 AND event_id=$2', [gid, ev.id]); return; }
      const t = (await c.query('SELECT seats FROM seating_tables WHERE id=$1 AND event_id=$2 FOR UPDATE', [tableId, ev.id])).rows[0];
      if (!t) throw notFound('table_not_found');
      const used = (await c.query(`SELECT coalesce(sum(CASE WHEN r.status='coming' THEN r.headcount ELSE g.seats END),0)::int AS n
          FROM seat_assignments sa JOIN guests g ON g.id=sa.guest_id LEFT JOIN rsvps r ON r.guest_id=g.id AND r.event_id=sa.event_id
          WHERE sa.table_id=$1 AND sa.guest_id <> $2`, [tableId, gid])).rows[0].n;
      const me = (await c.query(`SELECT CASE WHEN r.status='coming' THEN r.headcount ELSE g.seats END AS n FROM guests g
          LEFT JOIN rsvps r ON r.guest_id=g.id AND r.event_id=$2 WHERE g.id=$1`, [gid, ev.id])).rows[0].n;
      if (used + me > t.seats) throw new HttpError(409, 'table_full', `That table has ${t.seats - used} free seats; this party needs ${me}.`);
      await c.query(`INSERT INTO seat_assignments (guest_id, event_id, table_id) VALUES ($1,$2,$3) ON CONFLICT (guest_id, event_id) DO UPDATE SET table_id=EXCLUDED.table_id`, [gid, ev.id, tableId]);
    });
    await publishGuest(gid);
    return { ok: true };
  });

  app.post('/weddings/:weddingId/events/:eventId/seating/suggest', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'seating');
    const ev = await eventOf(a.weddingId, (req.params as any).eventId);
    const keep = (req.body as any)?.keep_existing !== false;
    const onlyConfirmed = (req.body as any)?.only_confirmed === true;
    const tables = await q('SELECT id, name, seats, shape, sort FROM seating_tables WHERE event_id=$1', [ev.id]);
    if (!tables.length) throw bad('add_tables_first', 'Add tables first.');
    const rows = await q(`SELECT g.id, g.name, g.title, g.side, g.group_name, g.vip, g.tags, g.seats, r.status, r.headcount, sa.table_id
      FROM guest_events ge JOIN guests g ON g.id=ge.guest_id
      LEFT JOIN rsvps r ON r.guest_id=g.id AND r.event_id=ge.event_id
      LEFT JOIN seat_assignments sa ON sa.guest_id=g.id AND sa.event_id=ge.event_id
      WHERE ge.event_id=$1 AND coalesce(r.status,'') <> 'not_coming' AND ($2 = false OR r.status='coming')`, [ev.id, onlyConfirmed]);
    const conflicts = (await q('SELECT a, b FROM guest_conflicts WHERE wedding_id=$1', [a.weddingId])).map((c) => [c.a, c.b] as [string, string]);
    const plan = suggestSeating(rows.map((g) => ({
      id: g.id, name: g.name, size: g.status === 'coming' ? g.headcount : g.seats, side: g.side, group: g.group_name, vip: g.vip,
      elder: looksElder(g.title, g.tags), fixedTable: keep ? g.table_id : null,
    })), tables, conflicts);
    await tx(async (c) => {
      await c.query('DELETE FROM seat_assignments WHERE event_id=$1', [ev.id]);
      for (const [gid, tid] of Object.entries(plan.assignments)) await c.query('INSERT INTO seat_assignments (guest_id, event_id, table_id) VALUES ($1,$2,$3)', [gid, ev.id, tid]);
    });
    await enqueuePublish(a.weddingId);
    return { placed: Object.keys(plan.assignments).length, unplaced: plan.unplaced.length, warnings: plan.warnings };
  });

  app.post('/weddings/:weddingId/conflicts', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const [x, y] = [str((req.body as any)?.a, 'a')!, str((req.body as any)?.b, 'b')!].sort();
    if (x === y) throw bad('same_guest');
    const ok = await one('SELECT count(*)::int AS n FROM guests WHERE wedding_id=$1 AND id = ANY($2)', [a.weddingId, [x, y]]);
    if (ok.n !== 2) throw notFound('guest_not_found');
    const remove = (req.body as any)?.remove === true;
    if (remove) await pool.query('DELETE FROM guest_conflicts WHERE a=$1 AND b=$2', [x, y]);
    else await pool.query('INSERT INTO guest_conflicts (wedding_id, a, b) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [a.weddingId, x, y]);
    return { ok: true };
  });

  // Show "Find your seat" on guest pages and the venue QR board.
  app.post('/weddings/:weddingId/seating/publish', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'seating');
    const on = (req.body as any)?.published !== false;
    await pool.query(`UPDATE weddings SET settings = settings || jsonb_build_object('seating_published', $2::boolean) WHERE id=$1`, [a.weddingId, on]);
    await enqueuePublish(a.weddingId);
    return { published: on };
  });

  // =============== Couple-entered RSVPs (replies that came by WhatsApp or phone) ===============
  app.post('/weddings/:weddingId/read-reply', async (req) => {
    await weddingAccess(req, 'view');
    return readReply(str((req.body as any)?.text, 'text', { max: 2000 })!);
  });

  app.put('/weddings/:weddingId/guests/:guestId/rsvp', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    const gid = (req.params as any).guestId;
    const g = await one('SELECT seats FROM guests WHERE id=$1 AND wedding_id=$2', [gid, a.weddingId]);
    if (!g) throw notFound('guest_not_found');
    const b = req.body as any;
    const evs = Array.isArray(b.event_ids) && b.event_ids.length ? b.event_ids : (await q('SELECT event_id FROM guest_events WHERE guest_id=$1', [gid])).map((r) => r.event_id);
    const status = oneOf(b.status, 'status', ['coming', 'not_coming', 'maybe'] as const);
    const headcount = status === 'not_coming' ? 0 : int(b.headcount, 'headcount', 1, g.seats, g.seats);
    const meal = b.meal ? oneOf(b.meal, 'meal', ['vegetarian', 'vegan', 'halal'] as const) : null;
    for (const e of evs) {
      await pool.query(`INSERT INTO rsvps (guest_id, event_id, status, headcount, meal, message) SELECT $1, $2, $3, $4, $5, $6 WHERE EXISTS (SELECT 1 FROM guest_events WHERE guest_id=$1 AND event_id=$2)
        ON CONFLICT (guest_id, event_id) DO UPDATE SET status=EXCLUDED.status, headcount=EXCLUDED.headcount, meal=EXCLUDED.meal, updated_at=now()`,
        [gid, e, status, headcount, meal, str(b.note, 'note', { max: 500, optional: true })]);
    }
    await publishGuest(gid);
    return { ok: true };
  });

  // =============== Tasks and checklist ===============
  app.get('/weddings/:weddingId/tasks', async (req) => {
    const a = await weddingAccess(req, 'view');
    const kind = oneOf((req.query as any).kind, 'kind', ['task', 'checklist'] as const, 'task');
    return { tasks: await q(`SELECT t.*, coalesce(u.name, u.email, u.phone) AS assignee_name FROM tasks t LEFT JOIN users u ON u.id=t.assignee_id
      WHERE t.wedding_id=$1 AND t.kind=$2 ORDER BY t.months_before DESC NULLS LAST, t.done_at NULLS FIRST, t.due_date NULLS LAST, t.sort, t.created_at`, [a.weddingId, kind]) };
  });

  app.post('/weddings/:weddingId/tasks', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const kind = oneOf(b.kind, 'kind', ['task', 'checklist'] as const, 'task');
    if (kind === 'checklist') await assertFeature(a.weddingId, 'planning');
    if (b.assignee_id && !(await one('SELECT 1 FROM wedding_members WHERE wedding_id=$1 AND user_id=$2', [a.weddingId, b.assignee_id]))) throw bad('assignee_not_member');
    const t = await one(`INSERT INTO tasks (wedding_id, title, due_date, assignee_id, kind, months_before) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [a.weddingId, str(b.title, 'title', { max: 200 }), dateOrNull(b.due_date, 'due_date'), b.assignee_id ?? null, kind, b.months_before ?? null]);
    return { task: t };
  });

  app.post('/weddings/:weddingId/checklist/suggest', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'planning');
    const have = await one(`SELECT count(*)::int AS n FROM tasks WHERE wedding_id=$1 AND kind='checklist'`, [a.weddingId]);
    if (have.n > 0) throw bad('checklist_exists', 'The checklist already has tasks.');
    const w = await one('SELECT wedding_type FROM weddings WHERE id=$1', [a.weddingId]);
    const items = suggestedChecklist(w.wedding_type);
    const first = await one('SELECT min(starts_at) AS d FROM events WHERE wedding_id=$1', [a.weddingId]);
    for (const [i, it] of items.entries()) {
      const due = first?.d ? new Date(new Date(first.d).getTime() - it.months_before * 30.4 * 86400000).toISOString().slice(0, 10) : null;
      await pool.query(`INSERT INTO tasks (wedding_id, title, kind, months_before, due_date, sort) VALUES ($1,$2,'checklist',$3,$4,$5)`, [a.weddingId, it.title, it.months_before, due, i]);
    }
    return { added: items.length };
  });

  app.patch('/weddings/:weddingId/tasks/:taskId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    if (b.assignee_id && !(await one('SELECT 1 FROM wedding_members WHERE wedding_id=$1 AND user_id=$2', [a.weddingId, b.assignee_id]))) throw bad('assignee_not_member');
    const t = await one(`UPDATE tasks SET title=coalesce($3,title),
        due_date=CASE WHEN $4::boolean THEN $5::date ELSE due_date END,
        assignee_id=CASE WHEN $6::boolean THEN $7::uuid ELSE assignee_id END,
        done_at=CASE WHEN $8::boolean IS NULL THEN done_at WHEN $8 THEN coalesce(done_at, now()) ELSE NULL END
      WHERE id=$2 AND wedding_id=$1 RETURNING *`,
      [a.weddingId, (req.params as any).taskId, b.title ? str(b.title, 'title', { max: 200 }) : null,
        b.due_date !== undefined, dateOrNull(b.due_date, 'due_date'), b.assignee_id !== undefined, b.assignee_id ?? null,
        typeof b.done === 'boolean' ? b.done : null]);
    if (!t) throw notFound('task_not_found');
    return { task: t };
  });

  app.delete('/weddings/:weddingId/tasks/:taskId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await pool.query('DELETE FROM tasks WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).taskId]);
    return { ok: true };
  });

  // =============== Budget ===============
  app.get('/weddings/:weddingId/budget', async (req) => {
    const a = await weddingAccess(req, 'view');
    const items = await q('SELECT * FROM budget_items WHERE wedding_id=$1 ORDER BY category, created_at', [a.weddingId]);
    const sum = (f: (i: any) => number) => items.reduce((n, i) => n + f(i), 0);
    const cost = (i: any) => Number(i.total_lkr ?? i.estimated_lkr);
    const byCat: Record<string, { estimated: number; cost: number; paid: number }> = {};
    for (const i of items) {
      byCat[i.category] ??= { estimated: 0, cost: 0, paid: 0 };
      byCat[i.category].estimated += Number(i.estimated_lkr);
      byCat[i.category].cost += cost(i);
      byCat[i.category].paid += Number(i.paid_lkr);
    }
    const today = new Date().toISOString().slice(0, 10);
    return {
      items,
      totals: { estimated: sum((i) => Number(i.estimated_lkr)), cost: sum(cost), paid: sum((i) => Number(i.paid_lkr)), due: sum((i) => Math.max(0, cost(i) - Number(i.paid_lkr))) },
      categories: Object.entries(byCat).map(([category, v]) => ({ category, ...v })),
      // Payment reminders: unpaid balances due within 14 days or overdue.
      reminders: items.filter((i) => i.due_date && cost(i) > Number(i.paid_lkr) && new Date(i.due_date).getTime() - Date.parse(today) < 14 * 86400000)
        .map((i) => ({ id: i.id, name: i.name, vendor: i.vendor, due_date: i.due_date, amount: cost(i) - Number(i.paid_lkr), overdue: String(i.due_date instanceof Date ? i.due_date.toISOString().slice(0, 10) : i.due_date) < today })),
    };
  });

  app.post('/weddings/:weddingId/budget', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'planning');
    const b = req.body as any;
    const it = await one(`INSERT INTO budget_items (wedding_id, category, name, estimated_lkr, paid_lkr, total_lkr, due_date, vendor, notes)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [a.weddingId, str(b.category, 'category', { max: 40 }), str(b.name, 'name', { max: 100 }), money(b.estimated_lkr, 'estimated_lkr'),
        money(b.paid_lkr, 'paid_lkr'), b.total_lkr === undefined || b.total_lkr === null || b.total_lkr === '' ? null : money(b.total_lkr, 'total_lkr'),
        dateOrNull(b.due_date, 'due_date'), str(b.vendor, 'vendor', { max: 100, optional: true }), str(b.notes, 'notes', { max: 500, optional: true })]);
    return { item: it };
  });

  app.patch('/weddings/:weddingId/budget/:itemId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const sets: string[] = []; const vals: unknown[] = [a.weddingId, (req.params as any).itemId];
    const set = (c: string, v: unknown) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    if (b.category !== undefined) set('category', str(b.category, 'category', { max: 40 }));
    if (b.name !== undefined) set('name', str(b.name, 'name', { max: 100 }));
    if (b.estimated_lkr !== undefined) set('estimated_lkr', money(b.estimated_lkr, 'estimated_lkr'));
    if (b.paid_lkr !== undefined) set('paid_lkr', money(b.paid_lkr, 'paid_lkr'));
    if (b.total_lkr !== undefined) set('total_lkr', b.total_lkr === null || b.total_lkr === '' ? null : money(b.total_lkr, 'total_lkr'));
    if (b.due_date !== undefined) set('due_date', dateOrNull(b.due_date, 'due_date'));
    if (b.vendor !== undefined) set('vendor', str(b.vendor, 'vendor', { max: 100, optional: true }));
    if (b.notes !== undefined) set('notes', str(b.notes, 'notes', { max: 500, optional: true }));
    if (!sets.length) throw bad('nothing_to_update');
    const it = await one(`UPDATE budget_items SET ${sets.join(',')} WHERE id=$2 AND wedding_id=$1 RETURNING *`, vals);
    if (!it) throw notFound('item_not_found');
    return { item: it };
  });

  app.delete('/weddings/:weddingId/budget/:itemId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await pool.query('DELETE FROM budget_items WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).itemId]);
    return { ok: true };
  });

  // =============== Run sheet ===============
  app.get('/weddings/:weddingId/run-sheet', async (req) => {
    const a = await weddingAccess(req, 'view');
    return { items: await q(`SELECT * FROM run_sheet_items WHERE wedding_id=$1 ORDER BY event_id NULLS FIRST, sort, time`, [a.weddingId]) };
  });

  app.post('/weddings/:weddingId/run-sheet', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await assertFeature(a.weddingId, 'planning');
    const b = req.body as any;
    if (b.event_id) await eventOf(a.weddingId, b.event_id);
    const n = await one('SELECT coalesce(max(sort),0)::int AS s FROM run_sheet_items WHERE wedding_id=$1', [a.weddingId]);
    const it = await one(`INSERT INTO run_sheet_items (wedding_id, event_id, time, item, owner, notes, sort) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [a.weddingId, b.event_id ?? null, str(b.time, 'time', { max: 20 }), str(b.item, 'item', { max: 200 }), str(b.owner, 'owner', { max: 80, optional: true }),
        str(b.notes, 'notes', { max: 500, optional: true }), b.sort ?? n.s + 1]);
    return { item: it };
  });

  app.patch('/weddings/:weddingId/run-sheet/:itemId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const it = await one(`UPDATE run_sheet_items SET time=coalesce($3,time), item=coalesce($4,item), owner=coalesce($5,owner), notes=coalesce($6,notes), sort=coalesce($7,sort)
      WHERE id=$2 AND wedding_id=$1 RETURNING *`, [a.weddingId, (req.params as any).itemId,
        b.time ? str(b.time, 'time', { max: 20 }) : null, b.item ? str(b.item, 'item', { max: 200 }) : null,
        b.owner !== undefined ? str(b.owner, 'owner', { max: 80, optional: true }) ?? '' : null, b.notes !== undefined ? str(b.notes, 'notes', { max: 500, optional: true }) ?? '' : null,
        b.sort !== undefined ? int(b.sort, 'sort', -10000, 10000) : null]);
    if (!it) throw notFound('item_not_found');
    return { item: it };
  });

  app.delete('/weddings/:weddingId/run-sheet/:itemId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await pool.query('DELETE FROM run_sheet_items WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).itemId]);
    return { ok: true };
  });

  // =============== Readiness ===============
  app.get('/weddings/:weddingId/readiness', async (req) => {
    const a = await weddingAccess(req, 'view');
    const r = await one(`SELECT w.published_at IS NOT NULL AS published, w.expected_guests,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id) AS guests,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id AND g.sent_at IS NOT NULL) AS sent,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id AND EXISTS (SELECT 1 FROM rsvps r WHERE r.guest_id=g.id)) AS replied,
        (SELECT count(*)::int FROM rsvps r JOIN guests g ON g.id=r.guest_id WHERE g.wedding_id=w.id AND r.status='coming') AS coming,
        (SELECT count(*)::int FROM rsvps r JOIN guests g ON g.id=r.guest_id JOIN seat_assignments sa ON sa.guest_id=r.guest_id AND sa.event_id=r.event_id WHERE g.wedding_id=w.id AND r.status='coming') AS seated,
        (SELECT count(*)::int FROM seating_tables t WHERE t.wedding_id=w.id) AS tables,
        (SELECT count(*)::int FROM run_sheet_items x WHERE x.wedding_id=w.id) AS run_sheet,
        (SELECT count(*)::int FROM tasks t WHERE t.wedding_id=w.id AND t.kind='checklist') AS cl_total,
        (SELECT count(*)::int FROM tasks t WHERE t.wedding_id=w.id AND t.kind='checklist' AND t.done_at IS NOT NULL) AS cl_done,
        (SELECT min(starts_at) FROM events e WHERE e.wedding_id=w.id AND e.starts_at > now()) AS next_event
      FROM weddings w WHERE w.id=$1`, [a.weddingId]);
    return readiness({
      published: r.published, guests: r.guests, expectedGuests: r.expected_guests, sent: r.sent, replied: r.replied, coming: r.coming,
      seated: r.seated, tables: r.tables, runSheetItems: r.run_sheet, checklistTotal: r.cl_total, checklistDone: r.cl_done,
      daysToGo: r.next_event ? Math.ceil((new Date(r.next_event).getTime() - Date.now()) / 86400000) : null,
    });
  });

  // =============== Printable reports (branded; the browser saves them as PDF) ===============
  app.post('/weddings/:weddingId/report-link', async (req) => {
    const a = await weddingAccess(req, 'view');
    const kind = oneOf((req.body as any)?.kind, 'kind', ['guests', 'seating', 'run_sheet', 'qr_board'] as const);
    const exp = Date.now() + 30 * 60_000;
    const sig = createHmac('sha256', config.previewSecret).update(`report:${a.weddingId}:${kind}:${exp}`).digest('base64url');
    return { url: `${config.publicApiUrl}/api/reports/${a.weddingId}/${kind}?exp=${exp}&sig=${sig}` };
  });

  app.get('/reports/:weddingId/:kind', async (req, reply) => {
    const { weddingId, kind } = req.params as any;
    const { exp, sig } = req.query as any;
    const want = createHmac('sha256', config.previewSecret).update(`report:${weddingId}:${kind}:${exp}`).digest('base64url');
    if (!sig || !safeEqual(String(sig), want) || Number(exp) < Date.now()) throw new HttpError(403, 'report_link_expired');
    const w = await one(`SELECT w.*, p.business_name, p.logo_url, (p.plan <> 'free' AND p.studio_until > now()) AS white_label
      FROM weddings w LEFT JOIN planners p ON p.id=w.planner_id WHERE w.id=$1`, [weddingId]);
    if (!w) throw notFound();
    const lang = w.language as Lang;
    const events = await q('SELECT * FROM events WHERE wedding_id=$1 ORDER BY starts_at', [weddingId]);
    const evName = (e: any) => e.title ?? eventNames[lang][e.kind];
    const fmt = (d: any) => new Date(d).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Colombo' });
    let title = '';
    let body = '';
    if (kind === 'guests') {
      title = 'Guest list and headcount';
      const rows = await q(`SELECT g.name, g.title, g.side, g.group_name, g.seats, g.dietary,
          coalesce((SELECT json_object_agg(r.event_id, json_build_object('s', r.status, 'n', r.headcount, 'm', r.meal)) FROM rsvps r WHERE r.guest_id=g.id), '{}') AS r
        FROM guests g WHERE g.wedding_id=$1 ORDER BY g.side NULLS LAST, g.group_name NULLS LAST, g.name`, [weddingId]);
      const label: Record<string, string> = { coming: 'Coming', not_coming: 'Not coming', maybe: 'Maybe' };
      body = `<table><thead><tr><th>Name</th><th>Side</th><th>Group</th><th>Seats</th>${events.map((e) => `<th>${escapeHtml(evName(e))}</th>`).join('')}<th>Dietary</th></tr></thead><tbody>${
        rows.map((g) => `<tr><td>${escapeHtml([g.title, g.name].filter(Boolean).join(' '))}</td><td>${escapeHtml(g.side ?? '')}</td><td>${escapeHtml(g.group_name ?? '')}</td><td>${g.seats}</td>${
          events.map((e) => { const r = g.r[e.id]; return `<td>${r ? `${label[r.s]}${r.s !== 'not_coming' ? ` (${r.n})` : ''}${r.m ? `, ${escapeHtml(r.m)}` : ''}` : '—'}</td>`; }).join('')}<td>${escapeHtml(g.dietary ?? '')}</td></tr>`).join('')}</tbody></table>`;
      const totals = await q(`SELECT e.id, coalesce(sum(r.headcount) FILTER (WHERE r.status='coming'),0)::int AS coming,
          coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='vegetarian'),0)::int AS veg,
          coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='vegan'),0)::int AS vegan,
          coalesce(sum(r.headcount) FILTER (WHERE r.status='coming' AND r.meal='halal'),0)::int AS halal
        FROM events e LEFT JOIN rsvps r ON r.event_id=e.id WHERE e.wedding_id=$1 GROUP BY e.id`, [weddingId]);
      body = `<div class="cards">${events.map((e) => { const t = totals.find((x) => x.id === e.id); return `<div class="card"><b>${escapeHtml(evName(e))}</b><div class="big">${t.coming}</div>coming · ${t.veg} vegetarian · ${t.vegan} vegan · ${t.halal} halal</div>`; }).join('')}</div>` + body;
    } else if (kind === 'seating' || kind === 'qr_board') {
      title = kind === 'seating' ? 'Seating plan' : 'Find your seat';
      for (const e of events) {
        const rows = await q(`SELECT t.name AS table_name, t.sort, g.name, g.title FROM seat_assignments sa JOIN seating_tables t ON t.id=sa.table_id JOIN guests g ON g.id=sa.guest_id
          WHERE sa.event_id=$1 ORDER BY ${kind === 'seating' ? 't.sort, t.name, g.name' : 'g.name'}`, [e.id]);
        if (!rows.length) continue;
        body += `<h2>${escapeHtml(evName(e))}</h2>`;
        if (kind === 'seating') {
          const by = new Map<string, string[]>();
          for (const r of rows) by.set(r.table_name, [...(by.get(r.table_name) ?? []), [r.title, r.name].filter(Boolean).join(' ')]);
          body += `<div class="cards">${[...by].map(([t, names]) => `<div class="card"><b>${escapeHtml(t)}</b><ul>${names.map((n) => `<li>${escapeHtml(n)}</li>`).join('')}</ul></div>`).join('')}</div>`;
        } else {
          body += `<div class="cols">${rows.map((r) => `<div class="row"><span>${escapeHtml([r.title, r.name].filter(Boolean).join(' '))}</span><b>${escapeHtml(r.table_name)}</b></div>`).join('')}</div>`;
        }
      }
      if (kind === 'qr_board') {
        const url = `${config.guestBaseUrl}/${w.slug}/seat.html`;
        body = `<div class="qr"><div id="qr"></div><p>Scan to find your seat<br><small>${escapeHtml(url)}</small></p></div>` + body +
          `<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js"></script><script>var q=qrcode(0,'M');q.addData(${JSON.stringify(url)});q.make();document.getElementById('qr').innerHTML=q.createSvgTag({cellSize:6,margin:2});</script>`;
      }
      if (!body) body = '<p>No one is seated yet.</p>';
    } else if (kind === 'run_sheet') {
      title = 'Wedding-day run sheet';
      const rows = await q('SELECT * FROM run_sheet_items WHERE wedding_id=$1 ORDER BY event_id NULLS FIRST, sort, time', [weddingId]);
      const byEvent = new Map<string, any[]>();
      for (const r of rows) byEvent.set(r.event_id ?? '', [...(byEvent.get(r.event_id ?? '') ?? []), r]);
      for (const [eid, items] of byEvent) {
        const e = events.find((x) => x.id === eid);
        body += `<h2>${escapeHtml(e ? `${evName(e)} · ${fmt(e.starts_at)}` : 'General')}</h2><table><thead><tr><th>Time</th><th>What</th><th>Who</th><th>Notes</th></tr></thead><tbody>${
          items.map((r) => `<tr><td><b>${escapeHtml(r.time)}</b></td><td>${escapeHtml(r.item)}</td><td>${escapeHtml(r.owner ?? '')}</td><td>${escapeHtml(r.notes ?? '')}</td></tr>`).join('')}</tbody></table>`;
      }
      if (!body) body = '<p>The run sheet is empty.</p>';
    } else throw notFound();
    const brand = w.business_name ? `<div class="brand">${w.logo_url && w.white_label ? `<img src="${escapeHtml(w.logo_url)}" alt="">` : ''}<span>${escapeHtml(w.business_name)}</span></div>` : '';
    return reply.type('text/html; charset=utf-8').header('cache-control', 'no-store').send(`<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} · ${escapeHtml(w.partner1)} & ${escapeHtml(w.partner2)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&family=Noto+Sans+Sinhala:wght@400;600&family=Noto+Sans+Tamil:wght@400;600&display=swap">
<style>body{font:14px/1.5 Inter,'Noto Sans Sinhala','Noto Sans Tamil',system-ui,sans-serif;color:#222;max-width:1000px;margin:24px auto;padding:0 16px}
h1{margin:0;font-size:24px}h2{margin:24px 0 8px;font-size:18px;border-bottom:2px solid #a8742a;padding-bottom:4px}
.brand{display:flex;align-items:center;gap:8px;color:#666;margin-bottom:8px}.brand img{height:36px}
table{width:100%;border-collapse:collapse;margin:8px 0}th,td{border-bottom:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}th{background:#f6f1e7}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px;margin:12px 0}.card{border:1px solid #ddd;border-radius:8px;padding:10px}.card ul{margin:6px 0 0;padding-left:18px}
.big{font-size:28px;font-weight:600;color:#a8742a}.cols{columns:2;column-gap:32px}.row{display:flex;justify-content:space-between;border-bottom:1px dotted #ccc;padding:4px 0;break-inside:avoid;font-size:16px}
.qr{text-align:center;margin:16px 0}.qr svg{width:220px;height:220px}.qr p{font-size:20px}
.noprint{margin:16px 0}.noprint button{font:inherit;font-size:16px;padding:10px 18px;border-radius:20px;border:0;background:#a8742a;color:#fff;cursor:pointer}
@media print{.noprint{display:none}body{margin:0}}</style></head><body>
${brand}<h1>${escapeHtml(w.partner1)} & ${escapeHtml(w.partner2)}</h1><div>${escapeHtml(title)} · ${escapeHtml(fmt(new Date()))}</div>
<div class="noprint"><button onclick="print()">Print / Save as PDF</button></div>${body}</body></html>`);
  });
}
