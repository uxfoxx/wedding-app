// Planner accounts: a business runs many client weddings from one account.
//   • Owner sees every client wedding; coordinators see only weddings assigned to them.
//   • A wedding always has one owner. A planner can create it, invite the couple, and hand over
//     ownership (keeping edit access) or keep it.
//   • A single wedding is never cheaper through a planner than a couple's own pass.
import type { FastifyInstance } from 'fastify';
import { config } from '../config.ts';
import { one, q, pool, tx } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { requireUser, type AuthUser } from '../lib/auth.ts';
import { paywall } from '../lib/entitlements.ts';
import { normalizePhone } from '../lib/phone.ts';
import { HttpError, bad, notFound, oneOf, randomToken, sha256, str } from '../lib/util.ts';
import { weddingSummary } from './weddings.ts';

const STUDIO_QUOTA: Record<string, number> = { studio10: 10, studio_unlimited: Infinity };
const TEAM_LIMIT = { free: 1, paid: 3, studio: Infinity };

export interface PlannerCtx { user: AuthUser; planner: any; role: 'owner' | 'coordinator' }

export async function plannerCtx(req: any, need: 'owner' | 'coordinator' = 'coordinator'): Promise<PlannerCtx> {
  const user = await requireUser(req);
  const row = await one(`SELECT p.*, m.role AS member_role FROM planner_members m JOIN planners p ON p.id=m.planner_id WHERE m.user_id=$1 LIMIT 1`, [user.id]);
  if (!row) throw new HttpError(404, 'not_a_planner', 'Set up your planner business first.');
  const { member_role, ...planner } = row;
  if (need === 'owner' && member_role !== 'owner') throw new HttpError(403, 'owner_only', 'Only the business owner can do this.');
  return { user, planner, role: member_role };
}

const studioActive = (p: any) => p.plan !== 'free' && p.studio_until && new Date(p.studio_until) > new Date();

async function activeUnpaidCount(plannerId: string): Promise<number> {
  // Active = an event in the future or within the last 90 days (or no event yet).
  const r = await one(`SELECT count(*)::int AS n FROM weddings w WHERE w.planner_id=$1 AND w.plan='free' AND NOT w.covered_by_studio
      AND coalesce((SELECT max(coalesce(ends_at, starts_at)) FROM events e WHERE e.wedding_id=w.id), now()) > now() - interval '90 days'`, [plannerId]);
  return r.n;
}

async function teamLimit(p: any): Promise<number> {
  if (studioActive(p)) return TEAM_LIMIT.studio;
  const paid = await one(`SELECT 1 FROM weddings WHERE planner_id=$1 AND plan='pass' LIMIT 1`, [p.id]);
  return paid ? TEAM_LIMIT.paid : TEAM_LIMIT.free;
}

export default async function plannerRoutes(app: FastifyInstance) {
  // ---- Business profile ----
  app.post('/planners', async (req) => {
    const u = await requireUser(req);
    const b = req.body as any;
    if (await one('SELECT 1 FROM planner_members WHERE user_id=$1', [u.id])) throw bad('already_planner');
    const phone = b.phone ? normalizePhone(b.phone) : null;
    const p = await tx(async (c) => {
      const p = (await c.query(`INSERT INTO planners (owner_id, business_name, phone, district) VALUES ($1,$2,$3,$4) RETURNING *`,
        [u.id, str(b.business_name, 'business_name', { max: 80 }), phone, str(b.district, 'district', { max: 60, optional: true })])).rows[0];
      await c.query(`INSERT INTO planner_members (planner_id, user_id, role) VALUES ($1,$2,'owner')`, [p.id, u.id]);
      return p;
    });
    return { planner: p, role: 'owner' };
  });

  app.get('/planner', async (req) => {
    const ctx = await plannerCtx(req);
    return { planner: ctx.planner, role: ctx.role, studioActive: studioActive(ctx.planner), teamLimit: await teamLimit(ctx.planner) };
  });

  app.patch('/planner', async (req) => {
    const ctx = await plannerCtx(req, 'owner');
    const b = req.body as any;
    const logo = b.logo_url !== undefined ? str(b.logo_url, 'logo_url', { max: 1000, optional: true }) : undefined;
    if (logo && !/^https:\/\//.test(logo)) throw bad('invalid_input', 'logo_url must start with https://');
    const p = await one(`UPDATE planners SET business_name=coalesce($2,business_name), phone=coalesce($3,phone), district=coalesce($4,district),
        logo_url=CASE WHEN $5::boolean THEN $6 ELSE logo_url END WHERE id=$1 RETURNING *`,
      [ctx.planner.id, b.business_name ? str(b.business_name, 'business_name', { max: 80 }) : null, b.phone ? normalizePhone(b.phone) : null,
        b.district ? str(b.district, 'district', { max: 60 }) : null, logo !== undefined, logo ?? null]);
    return { planner: p };
  });

  // ---- Team ----
  app.get('/planner/team', async (req) => {
    const ctx = await plannerCtx(req);
    const team = await q(`SELECT u.id, u.name, u.email, u.phone, m.role,
        (SELECT count(*)::int FROM wedding_members wm JOIN weddings w ON w.id=wm.wedding_id WHERE wm.user_id=u.id AND w.planner_id=m.planner_id) AS weddings
      FROM planner_members m JOIN users u ON u.id=m.user_id WHERE m.planner_id=$1 ORDER BY m.created_at`, [ctx.planner.id]);
    return { team, limit: await teamLimit(ctx.planner) };
  });

  app.post('/planner/team/invite', async (req) => {
    const ctx = await plannerCtx(req, 'owner');
    const n = await one('SELECT count(*)::int AS n FROM planner_members WHERE planner_id=$1', [ctx.planner.id]);
    const limit = await teamLimit(ctx.planner);
    if (n.n >= limit) throw paywall('team', limit === 1 ? 'Add team members once you run a paid wedding (up to 3), or unlimited with Studio.' : 'Your plan includes up to 3 team members. Studio has no limit.');
    const token = randomToken(18);
    await pool.query(`INSERT INTO planner_invites (token_hash, planner_id, expires_at) VALUES ($1,$2, now() + interval '14 days')`, [sha256(token), ctx.planner.id]);
    const link = `${config.webPanelUrl}/#team=${token}`;
    return { token, link, message: `${ctx.planner.business_name} invited you to join their team. Open this link to join: ${link}` };
  });

  app.post('/planner-invites/:token/accept', async (req) => {
    const u = await requireUser(req);
    const inv = await one(`UPDATE planner_invites SET accepted_by=$2 WHERE token_hash=$1 AND accepted_by IS NULL AND expires_at > now() RETURNING planner_id`,
      [sha256((req.params as any).token), u.id]);
    if (!inv) throw new HttpError(410, 'invite_expired');
    if (await one('SELECT 1 FROM planner_members WHERE user_id=$1', [u.id])) throw bad('already_in_a_team', 'This account already belongs to a planner business.');
    await pool.query(`INSERT INTO planner_members (planner_id, user_id, role) VALUES ($1,$2,'coordinator')`, [inv.planner_id, u.id]);
    return { ok: true };
  });

  app.delete('/planner/team/:userId', async (req) => {
    const ctx = await plannerCtx(req, 'owner');
    const uid = (req.params as any).userId;
    if (uid === ctx.user.id) throw bad('cannot_remove_owner');
    await tx(async (c) => {
      await c.query(`DELETE FROM wedding_members WHERE user_id=$1 AND via_planner AND wedding_id IN (SELECT id FROM weddings WHERE planner_id=$2)`, [uid, ctx.planner.id]);
      await c.query(`DELETE FROM planner_members WHERE planner_id=$1 AND user_id=$2 AND role <> 'owner'`, [ctx.planner.id, uid]);
    });
    return { ok: true };
  });

  // ---- Client weddings ----
  app.post('/planner/weddings', async (req) => {
    const ctx = await plannerCtx(req);
    const b = req.body as any;
    const p = ctx.planner;
    let covered = false;
    if (studioActive(p)) {
      const used = await one(`SELECT count(*)::int AS n FROM weddings WHERE planner_id=$1 AND covered_by_studio AND created_at >= date_trunc('month', now())`, [p.id]);
      covered = used.n < STUDIO_QUOTA[p.plan];
    }
    if (!covered && !p.approved_at && (await one('SELECT count(*)::int AS n FROM weddings WHERE planner_id=$1', [p.id])).n >= 1) {
      throw new HttpError(403, 'planner_not_approved', 'We are checking your business. You can run one wedding until then.');
    }
    if (!covered && (await activeUnpaidCount(p.id)) >= 1) {
      throw paywall('planner_weddings', 'The free planner plan runs one unpaid wedding at a time. Get the Wedding Pass for it (you or the couple can pay), or use Studio for several.');
    }
    const id = await tx(async (c) => {
      const w = (await c.query(`INSERT INTO weddings (owner_id, kind, partner1, partner2, wedding_type, district, expected_guests, mode, language, slug,
          planner_id, covered_by_studio, client_name, client_phone)
        VALUES ($1,$2,$3,$4,$5,$6,$7,'advanced',$8,$9,$10,$11,$12,$13) RETURNING id`,
        [ctx.user.id, oneOf(b.kind, 'kind', ['wedding', 'engagement', 'homecoming', 'other'] as const, 'wedding'),
          str(b.partner1, 'partner1', { max: 60 }), str(b.partner2, 'partner2', { max: 60 }),
          oneOf(b.wedding_type, 'wedding_type', ['buddhist', 'hindu', 'muslim', 'christian', 'civil', 'mixed'] as const, 'buddhist'),
          str(b.district, 'district', { max: 60, optional: true }), b.expected_guests ? Number(b.expected_guests) : null,
          oneOf(b.language, 'language', ['en', 'si', 'ta'] as const, 'en'), randomToken(9), p.id, covered,
          str(b.client_name, 'client_name', { max: 100, optional: true }), b.client_phone ? normalizePhone(b.client_phone) : null])).rows[0];
      await c.query(`INSERT INTO wedding_members (wedding_id, user_id, role, via_planner) VALUES ($1,$2,'owner',true)`, [w.id, ctx.user.id]);
      // The business owner always has access to client weddings created by a coordinator.
      if (ctx.role !== 'owner') {
        await c.query(`INSERT INTO wedding_members (wedding_id, user_id, role, via_planner) VALUES ($1,$2,'edit_all',true) ON CONFLICT DO NOTHING`, [w.id, p.owner_id]);
      }
      if (b.event?.starts_at) {
        const d = new Date(b.event.starts_at);
        if (Number.isNaN(d.getTime())) throw bad('invalid_input', 'event.starts_at');
        const kinds: Record<string, string> = { buddhist: 'poruwa', hindu: 'kovil', muslim: 'nikah', christian: 'church', civil: 'registration', mixed: 'reception' };
        await c.query(`INSERT INTO events (wedding_id, kind, starts_at, venue) VALUES ($1,$2,$3,$4)`,
          [w.id, kinds[b.wedding_type ?? 'buddhist'] ?? 'reception', d, str(b.event.venue, 'venue', { max: 120, optional: true })]);
      }
      return w.id as string;
    });
    return weddingSummary(id, 'owner');
  });

  // Dashboard: every active client wedding with days to go, RSVP progress and open tasks.
  app.get('/planner/dashboard', async (req) => {
    const ctx = await plannerCtx(req);
    const rows = await q(`SELECT w.id, w.partner1, w.partner2, w.client_name, w.plan, w.covered_by_studio, w.published_at,
        (SELECT min(starts_at) FROM events e WHERE e.wedding_id=w.id AND e.starts_at > now() - interval '1 day') AS next_event,
        (SELECT max(coalesce(ends_at, starts_at)) FROM events e WHERE e.wedding_id=w.id) AS last_event,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id) AS guests,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id AND EXISTS (SELECT 1 FROM rsvps r WHERE r.guest_id=g.id)) AS replied,
        (SELECT count(*)::int FROM tasks t WHERE t.wedding_id=w.id AND t.done_at IS NULL) AS open_tasks,
        (SELECT count(*)::int FROM tasks t WHERE t.wedding_id=w.id AND t.done_at IS NULL AND t.due_date < current_date) AS overdue_tasks,
        coalesce((SELECT json_agg(json_build_object('id', u.id, 'name', coalesce(u.name, u.email, u.phone))) FROM wedding_members wm JOIN users u ON u.id=wm.user_id
          JOIN planner_members pm ON pm.user_id=u.id AND pm.planner_id=w.planner_id WHERE wm.wedding_id=w.id), '[]') AS team
      FROM weddings w
      WHERE w.planner_id=$1 AND ($2 = 'owner' OR EXISTS (SELECT 1 FROM wedding_members wm WHERE wm.wedding_id=w.id AND wm.user_id=$3))
      ORDER BY next_event NULLS LAST, w.created_at DESC`, [ctx.planner.id, ctx.role, ctx.user.id]);
    const now = Date.now();
    const weddings = rows.map((w) => ({
      ...w,
      days_to_go: w.next_event ? Math.ceil((new Date(w.next_event).getTime() - now) / 86400000) : null,
      archived: w.last_event ? new Date(w.last_event).getTime() < now - 90 * 86400000 : false,
    }));
    return { weddings, planner: { business_name: ctx.planner.business_name, approved: !!ctx.planner.approved_at, plan: ctx.planner.plan, studioActive: studioActive(ctx.planner) } };
  });

  // Assign / unassign a team member to a client wedding.
  app.post('/planner/weddings/:weddingId/assign', async (req) => {
    const ctx = await plannerCtx(req, 'owner');
    const wid = (req.params as any).weddingId;
    const uid = str((req.body as any)?.user_id, 'user_id')!;
    const assign = (req.body as any)?.assigned !== false;
    if (!(await one('SELECT 1 FROM weddings WHERE id=$1 AND planner_id=$2', [wid, ctx.planner.id]))) throw notFound('wedding_not_found');
    if (!(await one('SELECT 1 FROM planner_members WHERE planner_id=$1 AND user_id=$2', [ctx.planner.id, uid]))) throw notFound('member_not_found');
    if (assign) await pool.query(`INSERT INTO wedding_members (wedding_id, user_id, role, via_planner) VALUES ($1,$2,'edit_all',true) ON CONFLICT DO NOTHING`, [wid, uid]);
    else await pool.query(`DELETE FROM wedding_members WHERE wedding_id=$1 AND user_id=$2 AND via_planner AND role <> 'owner'`, [wid, uid]);
    return { ok: true };
  });

  // Client notes and contact (visible to the planner team only).
  app.patch('/weddings/:weddingId/planner-notes', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const ctx = await plannerCtx(req);
    const w = await one('SELECT planner_id FROM weddings WHERE id=$1', [a.weddingId]);
    if (w.planner_id !== ctx.planner.id) throw new HttpError(403, 'not_your_client');
    const b = req.body as any;
    await pool.query(`UPDATE weddings SET planner_notes=coalesce($2, planner_notes), client_name=coalesce($3, client_name), client_phone=coalesce($4, client_phone) WHERE id=$1`,
      [a.weddingId, b.notes !== undefined ? str(b.notes, 'notes', { max: 5000, optional: true }) ?? '' : null,
        b.client_name ? str(b.client_name, 'client_name', { max: 100 }) : null, b.client_phone ? normalizePhone(b.client_phone) : null]);
    return { ok: true };
  });

  app.get('/weddings/:weddingId/planner-notes', async (req) => {
    const a = await weddingAccess(req, 'view');
    const ctx = await plannerCtx(req);
    const w = await one('SELECT planner_id, planner_notes, client_name, client_phone FROM weddings WHERE id=$1', [a.weddingId]);
    if (w.planner_id !== ctx.planner.id) throw new HttpError(403, 'not_your_client');
    return { notes: w.planner_notes, client_name: w.client_name, client_phone: w.client_phone };
  });

  // Hand over ownership (e.g. to the couple). The previous owner keeps "edit everything".
  app.post('/weddings/:weddingId/transfer-ownership', async (req) => {
    const a = await weddingAccess(req, 'owner');
    const to = str((req.body as any)?.user_id, 'user_id')!;
    if (to === a.user.id) throw bad('already_owner');
    await tx(async (c) => {
      const m = await c.query('SELECT 1 FROM wedding_members WHERE wedding_id=$1 AND user_id=$2', [a.weddingId, to]);
      if (!m.rowCount) throw bad('not_a_member', 'Invite them to the wedding first.');
      await c.query(`UPDATE wedding_members SET role='edit_all' WHERE wedding_id=$1 AND user_id=$2`, [a.weddingId, a.user.id]);
      await c.query(`UPDATE wedding_members SET role='owner' WHERE wedding_id=$1 AND user_id=$2`, [a.weddingId, to]);
      await c.query(`UPDATE weddings SET owner_id=$2 WHERE id=$1`, [a.weddingId, to]);
    });
    return { ok: true };
  });

  // ---- Tasks across all client weddings ----
  app.get('/planner/tasks', async (req) => {
    const ctx = await plannerCtx(req);
    const mine = (req.query as any).mine === 'true';
    const tasks = await q(`SELECT t.*, w.partner1, w.partner2, coalesce(u.name, u.email) AS assignee_name FROM tasks t
        JOIN weddings w ON w.id=t.wedding_id LEFT JOIN users u ON u.id=t.assignee_id
      WHERE w.planner_id=$1 AND t.done_at IS NULL AND t.kind='task'
        AND ($2 = 'owner' OR EXISTS (SELECT 1 FROM wedding_members wm WHERE wm.wedding_id=w.id AND wm.user_id=$3))
        AND (NOT $4 OR t.assignee_id=$3)
      ORDER BY t.due_date NULLS LAST, t.created_at LIMIT 500`, [ctx.planner.id, ctx.role, ctx.user.id, mine]);
    return { tasks };
  });

  // ---- Reusable templates ----
  app.get('/planner/templates', async (req) => {
    const ctx = await plannerCtx(req);
    return { templates: await q('SELECT * FROM planner_templates WHERE planner_id=$1 ORDER BY kind, name', [ctx.planner.id]) };
  });

  app.post('/planner/templates', async (req) => {
    const ctx = await plannerCtx(req);
    const b = req.body as any;
    const kind = oneOf(b.kind, 'kind', ['checklist', 'run_sheet', 'budget'] as const);
    let items = b.items;
    // "Save from wedding": copy the current checklist / run sheet / budget of a client wedding.
    if (b.from_wedding_id) {
      if (!(await one('SELECT 1 FROM weddings WHERE id=$1 AND planner_id=$2', [b.from_wedding_id, ctx.planner.id]))) throw notFound('wedding_not_found');
      items = kind === 'checklist' ? await q(`SELECT title, months_before FROM tasks WHERE wedding_id=$1 AND kind='checklist' ORDER BY months_before DESC, sort`, [b.from_wedding_id])
        : kind === 'run_sheet' ? await q(`SELECT time, item, owner, notes FROM run_sheet_items WHERE wedding_id=$1 ORDER BY sort, time`, [b.from_wedding_id])
        : await q(`SELECT category, name, estimated_lkr FROM budget_items WHERE wedding_id=$1 ORDER BY created_at`, [b.from_wedding_id]);
    }
    if (!Array.isArray(items) || items.length > 300) throw bad('invalid_input', 'items must be a list');
    const t = await one(`INSERT INTO planner_templates (planner_id, kind, name, items) VALUES ($1,$2,$3,$4) RETURNING *`,
      [ctx.planner.id, kind, str(b.name, 'name', { max: 80 }), JSON.stringify(items)]);
    return { template: t };
  });

  app.delete('/planner/templates/:id', async (req) => {
    const ctx = await plannerCtx(req);
    await pool.query('DELETE FROM planner_templates WHERE id=$1 AND planner_id=$2', [(req.params as any).id, ctx.planner.id]);
    return { ok: true };
  });

  app.post('/weddings/:weddingId/apply-template/:templateId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const ctx = await plannerCtx(req);
    const t = await one('SELECT * FROM planner_templates WHERE id=$1 AND planner_id=$2', [(req.params as any).templateId, ctx.planner.id]);
    if (!t) throw notFound('template_not_found');
    const items = t.items as any[];
    await tx(async (c) => {
      for (const [i, it] of items.entries()) {
        if (t.kind === 'checklist') await c.query(`INSERT INTO tasks (wedding_id, title, kind, months_before, sort) VALUES ($1,$2,'checklist',$3,$4)`, [a.weddingId, String(it.title).slice(0, 200), it.months_before ?? null, i]);
        else if (t.kind === 'run_sheet') await c.query(`INSERT INTO run_sheet_items (wedding_id, time, item, owner, notes, sort) VALUES ($1,$2,$3,$4,$5,$6)`, [a.weddingId, String(it.time).slice(0, 20), String(it.item).slice(0, 200), it.owner ?? null, it.notes ?? null, i]);
        else await c.query(`INSERT INTO budget_items (wedding_id, category, name, estimated_lkr) VALUES ($1,$2,$3,$4)`, [a.weddingId, String(it.category).slice(0, 40), String(it.name).slice(0, 100), Math.max(0, Number(it.estimated_lkr) || 0)]);
      }
    });
    return { added: items.length };
  });
}
