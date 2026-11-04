// Admin console (staff role, same app and web panel). Every change is written to the audit log.
import type { FastifyInstance } from 'fastify';
import { config, pricing } from '../config.ts';
import { enqueue } from '../lib/jobs.ts';
import { one, q, pool } from '../db.ts';
import { requireStaff } from '../lib/auth.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { markPaid, reference } from './payments.ts';
import { weddingSummary } from './weddings.ts';
import { HttpError, bad, notFound, oneOf, str } from '../lib/util.ts';

async function audit(actorId: string, action: string, target: string, details: Record<string, unknown> = {}) {
  await pool.query('INSERT INTO audit_log (actor_id, action, target, details) VALUES ($1,$2,$3,$4)', [actorId, action, target, JSON.stringify(details)]);
}

export default async function adminRoutes(app: FastifyInstance) {
  app.get('/admin/stats', async (req) => {
    await requireStaff(req);
    const days = await q(`SELECT d::date AS day,
        (SELECT count(*) FROM users WHERE created_at::date = d::date)::int AS signups,
        (SELECT count(*) FROM weddings WHERE created_at::date = d::date)::int AS weddings,
        (SELECT count(*) FROM payments WHERE status='paid' AND product='wedding_pass' AND paid_at::date = d::date)::int AS paid,
        (SELECT count(*) FROM guests WHERE sent_at::date = d::date)::int AS invitations_sent,
        (SELECT count(*) FROM rsvps WHERE updated_at::date = d::date)::int AS rsvps
      FROM generate_series(current_date - 13, current_date, interval '1 day') d ORDER BY d DESC`);
    const totals = await one(`SELECT (SELECT count(*) FROM weddings)::int AS weddings,
        (SELECT count(DISTINCT wedding_id) FROM guests WHERE sent_at IS NOT NULL)::int AS weddings_sent,
        (SELECT count(*) FROM weddings WHERE plan='pass')::int AS paid_weddings,
        (SELECT count(*) FROM payments WHERE status='pending' AND method='bank_transfer')::int AS pending_transfers,
        (SELECT count(*) FROM jobs WHERE done_at IS NULL AND attempts >= 5)::int AS failed_jobs,
        (SELECT count(*) FROM planners WHERE approved_at IS NULL)::int AS pending_planners,
        (SELECT count(*) FROM uploads WHERE reported_at IS NOT NULL)::int + (SELECT count(*) FROM guestbook_entries WHERE reported_at IS NOT NULL)::int AS open_reports,
        (SELECT count(*) FROM planners p WHERE (SELECT count(*) FROM weddings w WHERE w.planner_id=p.id) >= 2)::int AS planners_2plus`);
    return { totals, days, phase1Gate: { weddingsSent: { target: 100, now: totals.weddings_sent }, paid: { target: 20, now: totals.paid_weddings } }, phase2Gate: { planners2plus: { target: 20, now: totals.planners_2plus } } };
  });

  app.get('/admin/search', async (req) => {
    await requireStaff(req);
    const term = str((req.query as any).q, 'q', { max: 100 })!;
    const like = `%${term.replace(/[%_]/g, '\\$&')}%`;
    const [users, weddings, payments] = await Promise.all([
      q(`SELECT id, email, phone, name, staff_role, blocked_at, created_at FROM users WHERE email ILIKE $1 OR phone ILIKE $1 OR name ILIKE $1 OR id::text=$2 LIMIT 20`, [like, term]),
      q(`SELECT id, partner1, partner2, plan, created_at FROM weddings WHERE partner1 ILIKE $1 OR partner2 ILIKE $1 OR slug=$2 OR id::text=$2 LIMIT 20`, [like, term]),
      q(`SELECT id, wedding_id, reference, method, amount_lkr, status, created_at FROM payments WHERE reference ILIKE $1 OR id::text=$2 LIMIT 20`, [like, term]),
    ]);
    return { users, weddings, payments };
  });

  app.get('/admin/weddings/:id', async (req) => {
    await requireStaff(req);
    const id = (req.params as any).id;
    if (!(await one('SELECT 1 FROM weddings WHERE id=$1', [id]))) throw notFound();
    const summary = await weddingSummary(id, 'staff');
    const members = await q('SELECT u.id, u.name, u.email, u.phone, m.role FROM wedding_members m JOIN users u ON u.id=m.user_id WHERE m.wedding_id=$1', [id]);
    const payments = await q('SELECT * FROM payments WHERE wedding_id=$1 ORDER BY created_at DESC', [id]);
    return { ...summary, members, payments };
  });

  app.get('/admin/payments', async (req) => {
    await requireStaff(req);
    const status = (req.query as any).status ?? 'pending';
    // Vendor payments have no wedding; they show the business name instead.
    return { payments: await q(`SELECT p.*, w.partner1, w.partner2, v.business_name, u.email FROM payments p LEFT JOIN weddings w ON w.id=p.wedding_id
      LEFT JOIN vendors v ON v.id=p.vendor_id JOIN users u ON u.id=p.user_id
      WHERE p.status=$1 ORDER BY p.created_at DESC LIMIT 200`, [status]) };
  });

  // Confirm a bank transfer.
  app.post('/admin/payments/:id/approve', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const p = await markPaid((req.params as any).id, { approvedBy: s.id });
    if (!p) throw bad('not_pending');
    await audit(s.id, 'payment.approve', p.id, { reference: p.reference });
    return { payment: p };
  });

  // Refund: full refund within 7 days if no invitation was sent (feature document policy).
  app.post('/admin/payments/:id/refund', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const override = (req.body as any)?.override === true;
    const reason = str((req.body as any)?.reason, 'reason', { max: 500 })!;
    const p = await one('SELECT * FROM payments WHERE id=$1', [(req.params as any).id]);
    if (!p || p.status !== 'paid') throw bad('not_refundable');
    const sent = await one('SELECT count(*)::int AS n FROM guests WHERE wedding_id=$1 AND sent_at IS NOT NULL', [p.wedding_id]);
    const age = (Date.now() - new Date(p.paid_at).getTime()) / 86400000;
    if (!override && (age > pricing.refundWindowDays || sent.n > 0)) {
      throw new HttpError(409, 'outside_refund_policy', `Paid ${age.toFixed(1)} days ago; ${sent.n} invitations sent. Pass override:true to refund anyway.`);
    }
    await pool.query(`UPDATE payments SET status='refunded', refunded_at=now() WHERE id=$1`, [p.id]);
    if (p.product === 'wedding_pass') {
      const other = await one(`SELECT 1 FROM payments WHERE wedding_id=$1 AND product='wedding_pass' AND status='paid' AND id<>$2`, [p.wedding_id, p.id]);
      if (!other) await pool.query(`UPDATE weddings SET plan='free', paid_at=NULL WHERE id=$1`, [p.wedding_id]);
      await enqueuePublish(p.wedding_id);
    } else if (p.vendor_id && p.months) {
      // Take back exactly what this payment bought; time from other payments stays.
      const col = p.product === 'vendor_featured' ? 'featured_until' : 'verified_until';
      await pool.query(`UPDATE vendors SET ${col} = CASE WHEN ${col} - make_interval(months => $2) > now() THEN ${col} - make_interval(months => $2) END WHERE id=$1`, [p.vendor_id, p.months]);
      await enqueue('publish_vendor', { vendorId: p.vendor_id }, { key: `publish_vendor:${p.vendor_id}` });
    }
    // The money itself is returned in the gateway's dashboard or by bank transfer.
    await audit(s.id, 'payment.refund', p.id, { reason, override });
    return { refunded: true };
  });

  // Free upgrade (support goodwill, partners, testing).
  app.post('/admin/weddings/:id/grant-pass', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const id = (req.params as any).id;
    const reason = str((req.body as any)?.reason, 'reason', { max: 500 })!;
    const p = await one(`INSERT INTO payments (wedding_id, user_id, product, method, amount_lkr, reference)
      SELECT id, owner_id, 'wedding_pass', 'admin_grant', 0, $2 FROM weddings WHERE id=$1 RETURNING id`, [id, reference()]);
    if (!p) throw notFound();
    await markPaid(p.id, { approvedBy: s.id });
    await audit(s.id, 'wedding.grant_pass', id, { reason });
    return { ok: true };
  });

  app.post('/admin/users/:id/block', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const id = (req.params as any).id;
    const blocked = (req.body as any)?.blocked !== false;
    const reason = str((req.body as any)?.reason, 'reason', { max: 500 })!;
    if (id === s.id) throw bad('cannot_block_self');
    await pool.query('UPDATE users SET blocked_at = CASE WHEN $2 THEN now() ELSE NULL END WHERE id=$1', [id, blocked]);
    if (blocked) await pool.query('DELETE FROM sessions WHERE user_id=$1', [id]);
    await audit(s.id, blocked ? 'user.block' : 'user.unblock', id, { reason });
    return { ok: true };
  });

  // Take down an abusive guest page.
  // A staff member who lost their phone sets the authenticator app up again on next sign-in.
  app.post('/admin/users/:id/reset-mfa', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const id = (req.params as any).id;
    const reason = str((req.body as any)?.reason, 'reason', { max: 300 });
    const r = await pool.query('UPDATE users SET totp_secret=NULL, totp_enabled_at=NULL, totp_last_step=NULL WHERE id=$1 AND staff_role IS NOT NULL', [id]);
    if (!r.rowCount) throw notFound();
    await pool.query('UPDATE sessions SET mfa_at=NULL WHERE user_id=$1', [id]);
    await audit(s.id, 'user.reset_mfa', id, { reason });
    return { ok: true };
  });

  app.post('/admin/weddings/:id/takedown', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const id = (req.params as any).id;
    const reason = str((req.body as any)?.reason, 'reason', { max: 500 })!;
    const w = await one('UPDATE weddings SET published_at=NULL WHERE id=$1 RETURNING slug', [id]);
    if (!w) throw notFound();
    const { storage } = await import('../lib/storage.ts');
    await storage.del(`site/${w.slug}`);
    await audit(s.id, 'wedding.takedown', id, { reason });
    return { ok: true };
  });

  // Templates and wording are data: publish new ones without an app update.
  // The lists include unpublished rows, which the couple-facing lists hide.
  app.get('/admin/templates', async (req) => {
    await requireStaff(req, ['admin', 'designer']);
    return { templates: await q('SELECT id, name, category, premium, layout, published, sort, partner_code FROM templates ORDER BY sort, id') };
  });

  app.get('/admin/wordings', async (req) => {
    await requireStaff(req, ['admin', 'designer']);
    return { wordings: await q(`SELECT id, language, tone, event_kind, faith, body, published FROM wordings
      ORDER BY language, event_kind, array_position(ARRAY['formal','religious','modern','casual'], tone), faith NULLS FIRST`) };
  });

  app.put('/admin/templates/:id', async (req) => {
    const s = await requireStaff(req, ['admin', 'designer']);
    const b = req.body as any;
    const id = String((req.params as any).id);
    if (!/^[a-z0-9-]{3,40}$/.test(id)) throw bad('invalid_id');
    const L = b.layout;
    if (!L?.palette || !['serif', 'sans', 'script'].includes(L.headingFont)) throw bad('invalid_layout');
    for (const k of ['bg', 'surface', 'ink', 'accent', 'muted']) if (!/^#[0-9a-f]{6}$/i.test(L.palette[k] ?? '')) throw bad('invalid_layout', `palette.${k} must be a #rrggbb colour`);
    const layout = {
      palette: L.palette, headingFont: L.headingFont,
      ornament: oneOf(L.ornament, 'ornament', ['none', 'lotus', 'kolam', 'floral', 'geometric', 'cross', 'arch', 'lines'] as const, 'none'),
      animation: oneOf(L.animation, 'animation', ['none', 'envelope', 'curtain', 'scroll'] as const, 'none'),
      hero: oneOf(L.hero, 'hero', ['photo', 'monogram', 'pattern'] as const, 'monogram'),
    };
    await pool.query(`INSERT INTO templates (id, name, category, premium, layout, published, sort) VALUES ($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, category=EXCLUDED.category, premium=EXCLUDED.premium, layout=EXCLUDED.layout, published=EXCLUDED.published, sort=EXCLUDED.sort`,
      [id, str(b.name, 'name', { max: 60 }), str(b.category, 'category', { max: 30 }), !!b.premium, JSON.stringify(layout), b.published !== false, Number(b.sort ?? 100)]);
    await audit(s.id, 'template.save', id);
    return { ok: true };
  });

  app.post('/admin/wordings', async (req) => {
    const s = await requireStaff(req, ['admin', 'designer']);
    const b = req.body as any;
    const w = await one(`INSERT INTO wordings (language, tone, event_kind, faith, body) VALUES ($1,$2,$3,$4,$5) RETURNING id`, [
      oneOf(b.language, 'language', ['en', 'si', 'ta'] as const), oneOf(b.tone, 'tone', ['formal', 'modern', 'religious', 'casual'] as const),
      oneOf(b.event_kind, 'event_kind', ['wedding', 'homecoming', 'engagement'] as const, 'wedding'),
      b.faith ? oneOf(b.faith, 'faith', ['buddhist', 'hindu', 'muslim', 'christian'] as const) : null, str(b.body, 'body', { max: 2000 })]);
    await audit(s.id, 'wording.create', w.id);
    return { id: w.id };
  });

  app.patch('/admin/wordings/:id', async (req) => {
    const s = await requireStaff(req, ['admin', 'designer']);
    const b = req.body as any;
    // faith: a faith, or '' to make the wording suit any wedding; left out = unchanged.
    const r = await pool.query(`UPDATE wordings SET body=coalesce($2, body), published=coalesce($3, published), tone=coalesce($4, tone),
        event_kind=coalesce($5, event_kind), faith=CASE WHEN $6::boolean THEN $7 ELSE faith END WHERE id=$1`,
      [(req.params as any).id, b.body ? str(b.body, 'body', { max: 2000 }) : null, typeof b.published === 'boolean' ? b.published : null,
        b.tone ? oneOf(b.tone, 'tone', ['formal', 'modern', 'religious', 'casual'] as const) : null,
        b.event_kind ? oneOf(b.event_kind, 'event_kind', ['wedding', 'homecoming', 'engagement'] as const) : null,
        b.faith !== undefined, b.faith ? oneOf(b.faith, 'faith', ['buddhist', 'hindu', 'muslim', 'christian'] as const) : null]);
    if (!r.rowCount) throw notFound();
    await audit(s.id, 'wording.update', (req.params as any).id);
    return { ok: true };
  });

  // "Design it for me" jobs.
  app.get('/admin/design-jobs', async (req) => {
    await requireStaff(req, ['admin', 'designer']);
    return { jobs: await q(`SELECT j.*, w.partner1, w.partner2 FROM design_jobs j JOIN weddings w ON w.id=j.wedding_id ORDER BY j.created_at DESC LIMIT 200`) };
  });

  app.patch('/admin/design-jobs/:id', async (req) => {
    const s = await requireStaff(req, ['admin', 'designer']);
    const b = req.body as any;
    const status = b.status ? oneOf(b.status, 'status', ['queued', 'in_progress', 'review', 'cancelled'] as const) : null;
    const msg = b.message ? { from: 'designer', by: s.id, text: str(b.message, 'message', { max: 2000 }), at: new Date().toISOString() } : null;
    const r = await pool.query(`UPDATE design_jobs SET status=coalesce($2, status), designer_id=coalesce($3, designer_id),
        messages = CASE WHEN $4::jsonb IS NULL THEN messages ELSE messages || jsonb_build_array($4::jsonb) END WHERE id=$1`,
      [(req.params as any).id, status, b.designer_id ?? null, msg ? JSON.stringify(msg) : null]);
    if (!r.rowCount) throw notFound();
    await audit(s.id, 'design_job.update', (req.params as any).id, { status });
    return { ok: true };
  });


  // ---- Phase 2: planners, moderation, storage ----
  app.get('/admin/planners', async (req) => {
    await requireStaff(req);
    const status = (req.query as any).status ?? 'pending';
    return { planners: await q(`SELECT p.*, u.email, u.phone AS owner_phone,
        (SELECT count(*)::int FROM weddings w WHERE w.planner_id=p.id) AS weddings
      FROM planners p JOIN users u ON u.id=p.owner_id
      WHERE ($1='all' OR ($1='pending' AND p.approved_at IS NULL) OR ($1='approved' AND p.approved_at IS NOT NULL))
      ORDER BY p.created_at DESC LIMIT 200`, [status]) };
  });

  app.post('/admin/planners/:id/approve', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const r = await one(`UPDATE planners SET approved_at=now(), approved_by=$2 WHERE id=$1 AND approved_at IS NULL RETURNING id, business_name`, [(req.params as any).id, s.id]);
    if (!r) throw bad('not_pending');
    await audit(s.id, 'planner.approve', r.id, { business_name: r.business_name });
    return { ok: true };
  });

  // Planner billing: record a Studio subscription period (paid by card/transfer outside the app stores).
  app.post('/admin/planners/:id/studio', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const b = req.body as any;
    const plan = oneOf(b.plan, 'plan', ['free', 'studio10', 'studio_unlimited'] as const);
    const months = plan === 'free' ? 0 : Math.max(1, Math.min(12, Number(b.months) || 1));
    const r = await one(`UPDATE planners SET plan=$2, studio_until = CASE WHEN $3 = 0 THEN NULL
        ELSE greatest(coalesce(studio_until, now()), now()) + make_interval(months => $3) END WHERE id=$1 RETURNING id, plan, studio_until`,
      [(req.params as any).id, plan, months]);
    if (!r) throw notFound();
    await audit(s.id, 'planner.studio', r.id, { plan, months, reference: b.reference ?? null });
    return { planner: r };
  });

  // Reported guest photos and guestbook messages across all weddings.
  app.get('/admin/reports', async (req) => {
    await requireStaff(req);
    const uploads = await q(`SELECT u.id, u.wedding_id, u.kind, u.path, u.uploader, u.reported_at, w.partner1, w.partner2 FROM uploads u JOIN weddings w ON w.id=u.wedding_id
      WHERE u.reported_at IS NOT NULL ORDER BY u.reported_at DESC LIMIT 200`);
    const entries = await q(`SELECT e.id, e.wedding_id, e.name, e.message, e.reported_at, w.partner1, w.partner2 FROM guestbook_entries e JOIN weddings w ON w.id=e.wedding_id
      WHERE e.reported_at IS NOT NULL ORDER BY e.reported_at DESC LIMIT 200`);
    const { mediaUrl } = await import('../lib/storage.ts');
    return { uploads: uploads.map((u) => ({ ...u, url: mediaUrl(u.path) })), guestbook: entries };
  });

  app.post('/admin/reports/resolve', async (req) => {
    const s = await requireStaff(req);
    const b = req.body as any;
    const kind = oneOf(b.kind, 'kind', ['upload', 'guestbook'] as const);
    const action = oneOf(b.action, 'action', ['restore', 'remove'] as const);
    if (kind === 'upload') {
      if (action === 'remove') {
        const u = await one(`UPDATE uploads SET status='hidden', reported_at=NULL WHERE id=$1 RETURNING path`, [b.id]);
        if (u) { const { storage } = await import('../lib/storage.ts'); await storage.del(u.path); }
      } else await pool.query(`UPDATE uploads SET status='approved', reported_at=NULL WHERE id=$1`, [b.id]);
    } else {
      await pool.query(`UPDATE guestbook_entries SET status=$2, reported_at=NULL WHERE id=$1`, [b.id, action === 'remove' ? 'hidden' : 'visible']);
    }
    await audit(s.id, `report.${action}`, String(b.id), { kind });
    return { ok: true };
  });

  // Storage per wedding: usage and limit.
  app.get('/admin/storage', async (req) => {
    await requireStaff(req);
    return { weddings: await q(`SELECT w.id, w.partner1, w.partner2, coalesce((w.settings->>'storage_limit_mb')::int, $1) AS limit_mb,
        round(coalesce(sum(u.size_bytes),0) / 1048576.0)::int AS used_mb, count(u.*)::int AS files
      FROM weddings w JOIN uploads u ON u.wedding_id=w.id AND u.status <> 'hidden' GROUP BY w.id ORDER BY used_mb DESC LIMIT 200`, [pricing.weddingStorageMb]) };
  });

  app.post('/admin/weddings/:id/storage-limit', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const mb = Number((req.body as any)?.limit_mb);
    if (!Number.isInteger(mb) || mb < 100 || mb > 100000) throw bad('invalid_input', 'limit_mb must be 100–100000');
    await pool.query(`UPDATE weddings SET settings = settings || jsonb_build_object('storage_limit_mb', $2::int) WHERE id=$1`, [(req.params as any).id, mb]);
    await audit(s.id, 'wedding.storage_limit', (req.params as any).id, { mb });
    return { ok: true };
  });


  // ---- Phase 3: vendor marketplace ----
  app.get('/admin/vendors', async (req) => {
    await requireStaff(req);
    const status = (req.query as any).status ?? 'pending';
    return { vendors: await q(`SELECT v.*, u.email AS owner_email,
        (SELECT count(*)::int FROM vendor_media m WHERE m.vendor_id=v.id AND m.ready) AS media,
        (SELECT count(*)::int FROM vendor_packages p WHERE p.vendor_id=v.id) AS packages,
        (SELECT count(*)::int FROM vendor_complaints c WHERE c.vendor_id=v.id AND c.status='open') AS open_complaints
      FROM vendors v JOIN users u ON u.id=v.owner_id WHERE ($1='all' OR v.status=$1) ORDER BY v.created_at DESC LIMIT 300`, [status]) };
  });

  // Checks before a vendor goes live: phone/WhatsApp verified, business registration or NIC, original portfolio.
  app.post('/admin/vendors/:id/checks', async (req) => {
    const s = await requireStaff(req);
    const b = req.body as any;
    await pool.query(`UPDATE vendors SET phone_verified=coalesce($2,phone_verified), registration_checked=coalesce($3,registration_checked), portfolio_checked=coalesce($4,portfolio_checked) WHERE id=$1`,
      [(req.params as any).id, typeof b.phone_verified === 'boolean' ? b.phone_verified : null, typeof b.registration_checked === 'boolean' ? b.registration_checked : null,
        typeof b.portfolio_checked === 'boolean' ? b.portfolio_checked : null]);
    await audit(s.id, 'vendor.checks', (req.params as any).id, b);
    return { ok: true };
  });

  app.post('/admin/vendors/:id/status', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const status = oneOf((req.body as any)?.status, 'status', ['approved', 'suspended', 'draft'] as const);
    const reason = str((req.body as any)?.reason, 'reason', { max: 500 })!;
    const v = await one('SELECT * FROM vendors WHERE id=$1', [(req.params as any).id]);
    if (!v) throw notFound();
    if (status === 'approved' && !(v.phone_verified && v.portfolio_checked)) throw bad('checks_missing', 'Verify the phone and check the portfolio is original before approving.');
    await pool.query(`UPDATE vendors SET status=$2, approved_at = CASE WHEN $2='approved' THEN coalesce(approved_at, now()) ELSE approved_at END WHERE id=$1`, [v.id, status]);
    if (status === 'approved') await pool.query(`UPDATE vendor_complaints SET status='dismissed' WHERE vendor_id=$1 AND status='open' AND $2`, [v.id, (req.body as any)?.dismiss_complaints === true]);
    await enqueue('publish_vendor', { vendorId: v.id }, { key: `publish_vendor:${v.id}` });
    await audit(s.id, `vendor.${status}`, v.id, { reason });
    return { ok: true };
  });

  // Vendor money (only once couples use the directory): featured placement and the annual verified badge.
  app.post('/admin/vendors/:id/promotion', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const b = req.body as any;
    const kind = oneOf(b.kind, 'kind', ['featured', 'verified'] as const);
    const months = Math.max(0, Math.min(12, Number(b.months) || 0));
    const v = await one('SELECT id, category, status FROM vendors WHERE id=$1', [(req.params as any).id]);
    if (!v || v.status !== 'approved') throw bad('not_approved');
    if (kind === 'featured' && months > 0) {
      const cat = await one(`SELECT featured_slots, (SELECT count(*)::int FROM vendors x WHERE x.category=c.id AND x.featured_until > now() AND x.id <> $2) AS used FROM vendor_categories c WHERE c.id=$1`, [v.category, v.id]);
      if (cat.used >= cat.featured_slots) throw new HttpError(409, 'no_featured_slots', 'All featured slots in this category are taken.');
    }
    const col = kind === 'featured' ? 'featured_until' : 'verified_until';
    const r = await one(`UPDATE vendors SET ${col} = CASE WHEN $2 = 0 THEN NULL ELSE greatest(coalesce(${col}, now()), now()) + make_interval(months => $2) END WHERE id=$1 RETURNING ${col} AS until`, [v.id, kind === 'verified' && months > 0 ? 12 : months]);
    await enqueue('publish_vendor', { vendorId: v.id }, { key: `publish_vendor:${v.id}` });
    await audit(s.id, `vendor.${kind}`, v.id, { months, reference: b.reference ?? null });
    return { until: r.until };
  });

  app.get('/admin/vendor-complaints', async (req) => {
    await requireStaff(req);
    return { complaints: await q(`SELECT c.*, v.business_name, w.partner1, w.partner2 FROM vendor_complaints c JOIN vendors v ON v.id=c.vendor_id JOIN weddings w ON w.id=c.wedding_id
      WHERE c.status='open' ORDER BY c.created_at DESC LIMIT 200`) };
  });

  app.post('/admin/vendor-complaints/:id', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const status = oneOf((req.body as any)?.status, 'status', ['upheld', 'dismissed'] as const);
    const c = await one(`UPDATE vendor_complaints SET status=$2 WHERE id=$1 RETURNING vendor_id`, [(req.params as any).id, status]);
    if (!c) throw notFound();
    // If no open complaints remain and the vendor was hidden for review, bring them back.
    const open = await one(`SELECT count(*)::int AS n FROM vendor_complaints WHERE vendor_id=$1 AND status='open'`, [c.vendor_id]);
    if (open.n === 0 && status === 'dismissed') await pool.query(`UPDATE vendors SET status='approved' WHERE id=$1 AND status='under_review'`, [c.vendor_id]);
    await audit(s.id, `complaint.${status}`, (req.params as any).id);
    return { ok: true };
  });

  app.get('/admin/reviews', async (req) => {
    await requireStaff(req);
    return { reviews: await q(`SELECT r.*, v.business_name FROM reviews r JOIN vendors v ON v.id=r.vendor_id ORDER BY r.reported_at DESC NULLS LAST, r.created_at DESC LIMIT 200`) };
  });

  app.post('/admin/reviews/:id', async (req) => {
    const s = await requireStaff(req);
    const status = oneOf((req.body as any)?.status, 'status', ['visible', 'hidden'] as const);
    const r = await one('UPDATE reviews SET status=$2, reported_at=NULL WHERE id=$1 RETURNING vendor_id', [(req.params as any).id, status]);
    if (!r) throw notFound();
    await enqueue('publish_vendor', { vendorId: r.vendor_id }, { key: `publish_vendor:${r.vendor_id}` });
    await audit(s.id, `review.${status}`, (req.params as any).id);
    return { ok: true };
  });

  app.get('/admin/categories', async (req) => {
    await requireStaff(req);
    return { categories: await q(`SELECT c.*, (SELECT count(*)::int FROM vendors v WHERE v.category=c.id AND v.status='approved') AS vendors,
      (SELECT count(*)::int FROM vendors v WHERE v.category=c.id AND v.featured_until > now()) AS featured FROM vendor_categories c ORDER BY sort`) };
  });

  app.put('/admin/categories/:id', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const b = req.body as any;
    const id = String((req.params as any).id);
    if (!/^[a-z_]{3,30}$/.test(id)) throw bad('invalid_id');
    await pool.query(`INSERT INTO vendor_categories (id, name, active, featured_slots, sort) VALUES ($1,$2,$3,$4,$5)
      ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, active=EXCLUDED.active, featured_slots=EXCLUDED.featured_slots, sort=EXCLUDED.sort`,
      [id, str(b.name, 'name', { max: 60 }), b.active !== false, Math.max(0, Math.min(20, Number(b.featured_slots ?? 3))), Number(b.sort ?? 100)]);
    await audit(s.id, 'category.save', id);
    return { ok: true };
  });

  // Growth: partner codes (venue/photographer/salon QR codes) and the showcase.
  app.get('/admin/partner-codes', async (req) => {
    await requireStaff(req);
    return { codes: await q(`SELECT p.*, (SELECT count(*)::int FROM weddings w WHERE w.partner_code=p.code AND w.plan='pass') AS paid FROM partner_codes p ORDER BY created_at DESC`) };
  });

  app.put('/admin/partner-codes/:code', async (req) => {
    const s = await requireStaff(req, ['admin']);
    const b = req.body as any;
    const code = String((req.params as any).code).toUpperCase();
    if (!/^[A-Z0-9]{4,20}$/.test(code)) throw bad('invalid_code', 'Codes are 4–20 letters or digits.');
    if (b.template_id && !(await one('SELECT 1 FROM templates WHERE id=$1', [b.template_id]))) throw bad('invalid_template');
    await pool.query(`INSERT INTO partner_codes (code, partner_name, vendor_id, discount_lkr, template_id, active) VALUES ($1,$2,$3,$4,$5,$6)
      ON CONFLICT (code) DO UPDATE SET partner_name=EXCLUDED.partner_name, vendor_id=EXCLUDED.vendor_id, discount_lkr=EXCLUDED.discount_lkr, template_id=EXCLUDED.template_id, active=EXCLUDED.active`,
      [code, str(b.partner_name, 'partner_name', { max: 80 }), b.vendor_id ?? null, Math.max(0, Math.min(pricing.passWebLkr, Number(b.discount_lkr) || 0)), b.template_id ?? null, b.active !== false]);
    // A co-branded template is reserved for this partner's couples.
    if (b.template_id) await pool.query('UPDATE templates SET partner_code=$2 WHERE id=$1', [b.template_id, code]);
    await audit(s.id, 'partner_code.save', code, { discount: b.discount_lkr });
    return { ok: true, qr_link: `${config.webPanelUrl}/#code=${code}` };
  });

  app.get('/admin/showcase', async (req) => {
    await requireStaff(req);
    return { weddings: await q(`SELECT id, partner1, partner2, slug, showcase FROM weddings WHERE showcase='requested' ORDER BY created_at DESC LIMIT 100`) };
  });

  app.post('/admin/showcase/:id', async (req) => {
    const s = await requireStaff(req);
    const approve = (req.body as any)?.approve === true;
    await pool.query(`UPDATE weddings SET showcase=$2 WHERE id=$1 AND showcase <> 'off'`, [(req.params as any).id, approve ? 'approved' : 'off']);
    await audit(s.id, approve ? 'showcase.approve' : 'showcase.decline', (req.params as any).id);
    return { ok: true };
  });

  app.get('/admin/marketplace-stats', async (req) => {
    await requireStaff(req);
    // Phase 3 gates: 30% of paid weddings contact a vendor; vendors reply within 24 hours on average.
    return await one(`SELECT
      (SELECT count(*)::int FROM vendors WHERE status='approved') AS vendors,
      (SELECT count(*)::int FROM vendors WHERE status='pending') AS pending,
      (SELECT count(*)::int FROM weddings WHERE plan='pass') AS paid_weddings,
      (SELECT count(DISTINCT e.wedding_id)::int FROM enquiries e JOIN weddings w ON w.id=e.wedding_id WHERE w.plan='pass') AS paid_weddings_contacting,
      (SELECT round(avg(extract(epoch FROM (first_reply_at - created_at)) / 3600)::numeric, 1) FROM enquiries WHERE first_reply_at IS NOT NULL) AS avg_reply_hours,
      (SELECT count(*)::int FROM weddings WHERE source_slug IS NOT NULL) AS viral_signups,
      (SELECT count(*)::int FROM weddings WHERE referral_code IS NOT NULL) AS referral_signups,
      (SELECT count(*)::int FROM weddings WHERE partner_code IS NOT NULL) AS partner_signups`);
  });

  app.get('/admin/audit', async (req) => {
    await requireStaff(req, ['admin']);
    return { entries: await q('SELECT a.*, u.email AS actor_email FROM audit_log a LEFT JOIN users u ON u.id=a.actor_id ORDER BY at DESC LIMIT 200') };
  });

  app.get('/admin/jobs/failed', async (req) => {
    await requireStaff(req, ['admin']);
    return { jobs: await q('SELECT id, type, payload, attempts, error, run_at FROM jobs WHERE done_at IS NULL AND attempts >= 5 ORDER BY id DESC LIMIT 100') };
  });
}
