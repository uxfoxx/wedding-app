// Vendor marketplace. Curated directory; contact is free and direct. No booking payments or commission.
import type { FastifyInstance } from 'fastify';
import { config, pricing } from '../config.ts';
import { one, q, pool, tx } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { requireUser, userFromRequest } from '../lib/auth.ts';
import { normalizePhone } from '../lib/phone.ts';
import { mediaUrl, storage, uploadTarget, usingObjectStorage } from '../lib/storage.ts';
import { HttpError, bad, int, notFound, oneOf, randomToken, str } from '../lib/util.ts';
import { enqueue } from '../lib/jobs.ts';

const republish = (vendorId: string) => enqueue('publish_vendor', { vendorId }, { key: `publish_vendor:${vendorId}`, delayMs: 2000 });

const VENDOR_MEDIA: Record<string, { kind: 'photo' | 'video'; ext: string }> = {
  'image/jpeg': { kind: 'photo', ext: 'jpg' }, 'image/png': { kind: 'photo', ext: 'png' }, 'image/webp': { kind: 'photo', ext: 'webp' },
  'video/mp4': { kind: 'video', ext: 'mp4' }, 'video/quicktime': { kind: 'video', ext: 'mov' },
};
const LANG_SET = ['en', 'si', 'ta'];

async function myVendor(req: any) {
  const u = await requireUser(req);
  const v = await one('SELECT * FROM vendors WHERE owner_id=$1', [u.id]);
  if (!v) throw new HttpError(404, 'not_a_vendor', 'Set up your business profile first.');
  return { user: u, vendor: v };
}

function strList(v: unknown, field: string, max = 30): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) throw bad('invalid_input', `${field} must be a list`);
  return v.map((x) => str(x, field, { max: 40 })!).filter(Boolean);
}

/** Public card shown in search results. Featured and verified are always labelled. */
const CARD_SQL = `SELECT v.id, v.slug, v.business_name, v.category, v.district, v.service_areas, v.languages, v.years_active,
    (v.featured_until > now()) AS featured, (v.verified_until > now()) AS verified_badge,
    (v.phone_verified AND v.registration_checked AND v.portfolio_checked) AS checked,
    (SELECT min(starting_lkr) FROM vendor_packages p WHERE p.vendor_id=v.id) AS starting_lkr,
    (SELECT round(avg(rating)::numeric, 1) FROM reviews r WHERE r.vendor_id=v.id AND r.status='visible') AS rating,
    (SELECT count(*)::int FROM reviews r WHERE r.vendor_id=v.id AND r.status='visible') AS reviews,
    (SELECT round(avg(extract(epoch FROM (e.first_reply_at - e.created_at)) / 3600)::numeric, 1) FROM enquiries e WHERE e.vendor_id=v.id AND e.first_reply_at IS NOT NULL) AS reply_hours,
    (SELECT path FROM vendor_media m WHERE m.vendor_id=v.id AND m.ready AND m.kind='photo' ORDER BY m.sort, m.created_at LIMIT 1) AS cover_path
  FROM vendors v`;

const card = (v: any) => {
  const { cover_path, ...rest } = v;
  return { ...rest, cover_url: cover_path ? mediaUrl(cover_path) : null, rating: v.rating === null ? null : Number(v.rating), reply_hours: v.reply_hours === null ? null : Number(v.reply_hours) };
};

export default async function vendorRoutes(app: FastifyInstance) {
  app.get('/vendor-categories', async () => ({ categories: await q('SELECT id, name FROM vendor_categories WHERE active ORDER BY sort') }));

  // ================= Vendor side =================
  app.post('/vendors', async (req) => {
    const u = await requireUser(req);
    if (await one('SELECT 1 FROM vendors WHERE owner_id=$1', [u.id])) throw bad('already_vendor');
    const b = req.body as any;
    const cat = await one('SELECT id FROM vendor_categories WHERE id=$1 AND active', [b.category]);
    if (!cat) throw bad('invalid_category');
    const v = await one(`INSERT INTO vendors (owner_id, slug, business_name, category, district, service_areas, languages, years_active, phone, whatsapp, description)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`,
      [u.id, randomToken(8).toLowerCase().replace(/[^a-z0-9]/g, 'x'), str(b.business_name, 'business_name', { max: 80 }), cat.id, str(b.district, 'district', { max: 40 }),
        strList(b.service_areas, 'service_areas'), strList(b.languages, 'languages').filter((l) => LANG_SET.includes(l)),
        b.years_active ? int(b.years_active, 'years_active', 0, 80) : null, b.phone ? normalizePhone(b.phone) : null, b.whatsapp ? normalizePhone(b.whatsapp) : null,
        str(b.description, 'description', { max: 3000, optional: true })]);
    return { vendor: v };
  });

  app.get('/vendor', async (req) => {
    const { vendor } = await myVendor(req);
    const media = await q('SELECT * FROM vendor_media WHERE vendor_id=$1 AND ready ORDER BY sort, created_at', [vendor.id]);
    const packages = await q('SELECT * FROM vendor_packages WHERE vendor_id=$1 ORDER BY sort, starting_lkr', [vendor.id]);
    return { vendor, media: media.map((m) => ({ ...m, url: mediaUrl(m.path) })), packages, public_url: `${config.guestBaseUrl.replace(/\/site$/, '')}/site/vendors/${vendor.slug}.html` };
  });

  // ---- Vendor money: featured placement and the verified badge, paid by the vendor ----
  // Closed until VENDOR_PROMOTIONS=on (the document: only once couples use the directory).
  async function featuredSlotsLeft(vendor: any) {
    const c = await one(`SELECT featured_slots, (SELECT count(*)::int FROM vendors x WHERE x.category=c.id AND x.featured_until > now() AND x.id <> $2) AS used
      FROM vendor_categories c WHERE c.id=$1`, [vendor.category, vendor.id]);
    // A vendor already featured keeps its slot when it extends.
    return vendor.featured_until && new Date(vendor.featured_until) > new Date() ? Math.max(1, c.featured_slots - c.used) : Math.max(0, c.featured_slots - c.used);
  }

  app.get('/vendor/promotions', async (req) => {
    const { vendor } = await myVendor(req);
    return {
      open: pricing.vendorPromotionsOpen && vendor.status === 'approved',
      prices: { featured_month_lkr: pricing.vendorFeaturedMonthLkr, verified_year_lkr: pricing.vendorVerifiedYearLkr },
      featured_until: vendor.featured_until, verified_until: vendor.verified_until,
      featured_slots_left: await featuredSlotsLeft(vendor),
      payments: await q(`SELECT id, product, method, amount_lkr, months, status, reference, created_at, paid_at FROM payments WHERE vendor_id=$1 ORDER BY created_at DESC LIMIT 20`, [vendor.id]),
    };
  });

  app.post('/vendor/checkout', async (req) => {
    const { user, vendor } = await myVendor(req);
    if (!pricing.vendorPromotionsOpen) throw new HttpError(403, 'promotions_closed', 'Paid placements are not open yet.');
    if (vendor.status !== 'approved') throw bad('not_approved', 'Your profile must be approved first.');
    const b = req.body as any;
    const product = oneOf(b?.product, 'product', ['vendor_featured', 'vendor_verified'] as const);
    const method = oneOf(b?.method, 'method', ['gateway', 'bank_transfer'] as const, 'gateway');
    const months = product === 'vendor_verified' ? 12 : int(b?.months, 'months', 1, 12, 1);
    if (product === 'vendor_featured' && (await featuredSlotsLeft(vendor)) < 1) throw new HttpError(409, 'no_featured_slots', 'All featured places in your category are taken. Try again next month.');
    const amount = product === 'vendor_verified' ? pricing.vendorVerifiedYearLkr : pricing.vendorFeaturedMonthLkr * months;
    const { reference } = await import('./payments.ts');
    const p = await one(`INSERT INTO payments (vendor_id, user_id, product, method, amount_lkr, list_price_lkr, months, reference) VALUES ($1,$2,$3,$4,$5,$5,$6,$7) RETURNING id, reference, amount_lkr`,
      [vendor.id, user.id, product, method, amount, months, reference()]);
    if (method === 'bank_transfer') {
      return { paymentId: p.id, reference: p.reference, amount_lkr: p.amount_lkr, status: 'pending', instructions: 'Transfer the amount and use the reference as the description. It starts as soon as the payment is confirmed (usually within one working day).' };
    }
    return { paymentId: p.id, reference: p.reference, amount_lkr: p.amount_lkr, checkoutUrl: `${config.publicApiUrl}/api/payments/dev-checkout/${p.id}` };
  });

  app.patch('/vendor', async (req) => {
    const { vendor } = await myVendor(req);
    const b = req.body as any;
    const sets: string[] = []; const vals: unknown[] = [vendor.id];
    const set = (c: string, v: unknown) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    if (b.business_name !== undefined) set('business_name', str(b.business_name, 'business_name', { max: 80 }));
    if (b.district !== undefined) set('district', str(b.district, 'district', { max: 40 }));
    if (b.service_areas !== undefined) set('service_areas', strList(b.service_areas, 'service_areas'));
    if (b.languages !== undefined) set('languages', strList(b.languages, 'languages').filter((l) => LANG_SET.includes(l)));
    if (b.years_active !== undefined) set('years_active', b.years_active === null ? null : int(b.years_active, 'years_active', 0, 80));
    if (b.phone !== undefined) { set('phone', b.phone ? normalizePhone(b.phone) : null); set('phone_verified', false); }
    if (b.whatsapp !== undefined) set('whatsapp', b.whatsapp ? normalizePhone(b.whatsapp) : null);
    if (b.description !== undefined) set('description', str(b.description, 'description', { max: 3000, optional: true }));
    if (!sets.length) throw bad('nothing_to_update');
    const updated = await one(`UPDATE vendors SET ${sets.join(',')} WHERE id=$1 RETURNING *`, vals);
    await republish(vendor.id);
    return { vendor: updated };
  });

  // Every new vendor is reviewed by the team before going live.
  app.post('/vendor/submit', async (req) => {
    const { vendor } = await myVendor(req);
    if (!['draft'].includes(vendor.status)) throw bad('already_submitted');
    const m = await one('SELECT count(*)::int AS n FROM vendor_media WHERE vendor_id=$1 AND ready', [vendor.id]);
    const p = await one('SELECT count(*)::int AS n FROM vendor_packages WHERE vendor_id=$1', [vendor.id]);
    if (m.n < 3) throw bad('portfolio_too_small', 'Add at least 3 photos or videos of your real work.');
    if (p.n < 1) throw bad('no_packages', 'Add at least one package with a starting price.');
    if (!vendor.phone) throw bad('no_phone', 'Add a phone number we can verify.');
    await pool.query(`UPDATE vendors SET status='pending' WHERE id=$1`, [vendor.id]);
    return { status: 'pending' };
  });

  // Portfolio: direct upload to storage, like guest photos.
  app.post('/vendor/media', async (req) => {
    const { vendor } = await myVendor(req);
    const b = req.body as any;
    const type = VENDOR_MEDIA[String(b.content_type)];
    if (!type) throw bad('unsupported_type');
    const size = Number(b.size);
    const max = type.kind === 'photo' ? pricing.maxPhotoBytes : pricing.maxVideoBytes;
    if (!Number.isInteger(size) || size <= 0 || size > max) throw bad('too_large');
    const n = await one('SELECT count(*)::int AS n FROM vendor_media WHERE vendor_id=$1', [vendor.id]);
    if (n.n >= 60) throw bad('portfolio_full', 'Up to 60 items.');
    const token = randomToken(24);
    const path = `media/vendors/${vendor.id}/${randomToken(12)}.${type.ext}`;
    const m = await one(`INSERT INTO vendor_media (vendor_id, kind, path, content_type, size_bytes, caption, upload_token, sort) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
      [vendor.id, type.kind, path, b.content_type, size, str(b.caption, 'caption', { max: 200, optional: true }), token, n.n]);
    return { id: m.id, upload_token: token, upload_url: await uploadTarget(path, b.content_type, size, `v_${token}`), method: 'PUT' };
  });

  app.post('/vendor/media/:id/complete', async (req) => {
    const { vendor } = await myVendor(req);
    const m = await one('SELECT * FROM vendor_media WHERE id=$1 AND vendor_id=$2', [(req.params as any).id, vendor.id]);
    if (!m) throw notFound();
    const size = await storage.size(m.path);
    if (size === null) throw bad('not_uploaded');
    // New photos go back to the team's originality check.
    await pool.query('UPDATE vendor_media SET ready=true, size_bytes=$2 WHERE id=$1', [m.id, size]);
    if (vendor.status === 'approved') await pool.query('UPDATE vendors SET portfolio_checked=false WHERE id=$1', [vendor.id]);
    await republish(vendor.id);
    return { ok: true, url: mediaUrl(m.path) };
  });

  app.delete('/vendor/media/:id', async (req) => {
    const { vendor } = await myVendor(req);
    const m = await one('DELETE FROM vendor_media WHERE id=$1 AND vendor_id=$2 RETURNING path', [(req.params as any).id, vendor.id]);
    if (m) await storage.del(m.path);
    return { ok: true };
  });

  // Development stand-in for presigned portfolio uploads.
  if (!usingObjectStorage) {
    app.put('/dev-upload/v_:token', { bodyLimit: pricing.maxVideoBytes }, async (req) => {
      const m = await one('SELECT path, content_type FROM vendor_media WHERE upload_token=$1 AND NOT ready', [(req.params as any).token]);
      if (!m || req.headers['content-type'] !== m.content_type || !Buffer.isBuffer(req.body)) throw notFound();
      await storage.put(m.path, req.body as Buffer, m.content_type);
      return { ok: true };
    });
  }

  app.post('/vendor/packages', async (req) => {
    const { vendor } = await myVendor(req);
    const b = req.body as any;
    const p = await one(`INSERT INTO vendor_packages (vendor_id, name, includes, addons, starting_lkr, negotiable) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [vendor.id, str(b.name, 'name', { max: 80 }), str(b.includes, 'includes', { max: 2000, optional: true }), str(b.addons, 'addons', { max: 1000, optional: true }),
        int(Math.round(Number(b.starting_lkr)), 'starting_lkr', 0, 100_000_000), b.negotiable !== false]);
    return { package: p };
  });

  app.patch('/vendor/packages/:id', async (req) => {
    const { vendor } = await myVendor(req);
    const b = req.body as any;
    const p = await one(`UPDATE vendor_packages SET name=coalesce($3,name), includes=coalesce($4,includes), addons=coalesce($5,addons),
        starting_lkr=coalesce($6,starting_lkr), negotiable=coalesce($7,negotiable) WHERE id=$1 AND vendor_id=$2 RETURNING *`,
      [(req.params as any).id, vendor.id, b.name ? str(b.name, 'name', { max: 80 }) : null, b.includes !== undefined ? str(b.includes, 'includes', { max: 2000, optional: true }) ?? '' : null,
        b.addons !== undefined ? str(b.addons, 'addons', { max: 1000, optional: true }) ?? '' : null,
        b.starting_lkr !== undefined ? int(Math.round(Number(b.starting_lkr)), 'starting_lkr', 0, 100_000_000) : null, typeof b.negotiable === 'boolean' ? b.negotiable : null]);
    if (!p) throw notFound();
    return { package: p };
  });

  app.delete('/vendor/packages/:id', async (req) => {
    const { vendor } = await myVendor(req);
    await pool.query('DELETE FROM vendor_packages WHERE id=$1 AND vendor_id=$2', [(req.params as any).id, vendor.id]);
    return { ok: true };
  });

  // Availability: booked dates hide the vendor from searches for those dates.
  app.get('/vendor/availability', async (req) => {
    const { vendor } = await myVendor(req);
    return { blocked: (await q(`SELECT to_char(day, 'YYYY-MM-DD') AS day FROM vendor_blocked_dates WHERE vendor_id=$1 AND day >= current_date ORDER BY day`, [vendor.id])).map((r) => r.day) };
  });

  app.put('/vendor/availability', async (req) => {
    const { vendor } = await myVendor(req);
    const b = req.body as any;
    if (!Array.isArray(b.days) || b.days.length > 366 || !b.days.every((d: unknown) => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d))) throw bad('invalid_input', 'days must be YYYY-MM-DD dates');
    if (b.blocked === false) await pool.query('DELETE FROM vendor_blocked_dates WHERE vendor_id=$1 AND day = ANY($2::date[])', [vendor.id, b.days]);
    else await pool.query('INSERT INTO vendor_blocked_dates (vendor_id, day) SELECT $1, unnest($2::date[]) ON CONFLICT DO NOTHING', [vendor.id, b.days]);
    return { ok: true };
  });

  // Enquiry inbox.
  app.get('/vendor/enquiries', async (req) => {
    const { vendor } = await myVendor(req);
    return { enquiries: await q(`SELECT e.*, w.partner1, w.partner2, w.wedding_type,
        (SELECT body FROM enquiry_messages m WHERE m.enquiry_id=e.id ORDER BY created_at DESC LIMIT 1) AS last_message,
        (SELECT count(*)::int FROM enquiry_messages m WHERE m.enquiry_id=e.id) AS messages
      FROM enquiries e JOIN weddings w ON w.id=e.wedding_id WHERE e.vendor_id=$1 ORDER BY e.created_at DESC LIMIT 500`, [vendor.id]) };
  });

  app.get('/vendor/enquiries/:id', async (req) => {
    const { vendor } = await myVendor(req);
    const e = await one(`SELECT e.*, w.partner1, w.partner2, w.wedding_type, u.phone AS contact_phone, u.email AS contact_email, u.name AS contact_name
      FROM enquiries e JOIN weddings w ON w.id=e.wedding_id JOIN users u ON u.id=e.sender_id WHERE e.id=$1 AND e.vendor_id=$2`, [(req.params as any).id, vendor.id]);
    if (!e) throw notFound();
    const messages = await q('SELECT id, from_side, body, created_at FROM enquiry_messages WHERE enquiry_id=$1 ORDER BY created_at', [e.id]);
    const wa = e.contact_phone ? `https://wa.me/${e.contact_phone.replace('+', '')}?text=${encodeURIComponent(`Hello ${e.contact_name ?? ''}, this is ${vendor.business_name} about your wedding enquiry.`)}` : null;
    return { enquiry: e, messages, whatsapp: wa };
  });

  app.post('/vendor/enquiries/:id/reply', async (req) => {
    const { user, vendor } = await myVendor(req);
    const e = await one('SELECT id FROM enquiries WHERE id=$1 AND vendor_id=$2', [(req.params as any).id, vendor.id]);
    if (!e) throw notFound();
    await tx(async (c) => {
      await c.query(`INSERT INTO enquiry_messages (enquiry_id, from_side, author_id, body) VALUES ($1,'vendor',$2,$3)`, [e.id, user.id, str((req.body as any)?.body, 'body', { max: 3000 })]);
      await c.query('UPDATE enquiries SET first_reply_at = coalesce(first_reply_at, now()) WHERE id=$1', [e.id]);
    });
    return { ok: true };
  });

  app.patch('/vendor/enquiries/:id', async (req) => {
    const { vendor } = await myVendor(req);
    const status = oneOf((req.body as any)?.status, 'status', ['new', 'quoted', 'booked', 'declined'] as const);
    const r = await pool.query(`UPDATE enquiries SET vendor_status=$3, first_reply_at = CASE WHEN $3 <> 'new' THEN coalesce(first_reply_at, now()) ELSE first_reply_at END
      WHERE id=$1 AND vendor_id=$2`, [(req.params as any).id, vendor.id, status]);
    if (!r.rowCount) throw notFound();
    return { ok: true };
  });

  // Ask the couple for a review after their wedding: a WhatsApp message with a link.
  app.post('/vendor/enquiries/:id/request-review', async (req) => {
    const { vendor } = await myVendor(req);
    const e = await one(`SELECT e.id, e.wedding_id, e.wedding_date, u.phone, u.name FROM enquiries e JOIN users u ON u.id=e.sender_id WHERE e.id=$1 AND e.vendor_id=$2`, [(req.params as any).id, vendor.id]);
    if (!e) throw notFound();
    if (!e.wedding_date || new Date(e.wedding_date) > new Date()) throw bad('too_early', 'You can ask for a review after the wedding date.');
    const link = `${config.webPanelUrl}/#review=${vendor.id}&wedding=${e.wedding_id}`;
    const text = `Hello ${e.name ?? ''}, thank you for choosing ${vendor.business_name}! If you have a minute, we would love your review: ${link}`;
    return { text, whatsapp: e.phone ? `https://wa.me/${e.phone.replace('+', '')}?text=${encodeURIComponent(text)}` : `https://wa.me/?text=${encodeURIComponent(text)}` };
  });

  app.get('/vendor/reviews', async (req) => {
    const { vendor } = await myVendor(req);
    return { reviews: await q(`SELECT r.id, r.rating, r.body, r.reply, r.created_at, w.partner1, w.partner2 FROM reviews r JOIN weddings w ON w.id=r.wedding_id
      WHERE r.vendor_id=$1 AND r.status='visible' ORDER BY r.created_at DESC`, [vendor.id]) };
  });

  // Vendors can reply publicly to reviews.
  app.post('/vendor/reviews/:id/reply', async (req) => {
    const { vendor } = await myVendor(req);
    const r = await pool.query(`UPDATE reviews SET reply=$3, replied_at=now() WHERE id=$1 AND vendor_id=$2`, [(req.params as any).id, vendor.id, str((req.body as any)?.reply, 'reply', { max: 1500 })]);
    if (!r.rowCount) throw notFound();
    await republish(vendor.id);
    return { ok: true };
  });

  app.get('/vendor/stats', async (req) => {
    const { vendor } = await myVendor(req);
    const s = await one(`SELECT
        (SELECT coalesce(sum(views),0)::int FROM vendor_views WHERE vendor_id=$1 AND day > current_date - 30) AS views_30d,
        (SELECT count(*)::int FROM enquiries WHERE vendor_id=$1 AND created_at > now() - interval '30 days') AS enquiries_30d,
        (SELECT count(*)::int FROM enquiries WHERE vendor_id=$1 AND vendor_status='booked') AS booked,
        (SELECT count(*)::int FROM shortlists WHERE vendor_id=$1) AS shortlisted,
        (SELECT round(avg(extract(epoch FROM (first_reply_at - created_at)) / 3600)::numeric, 1) FROM enquiries WHERE vendor_id=$1 AND first_reply_at IS NOT NULL) AS reply_hours,
        (SELECT count(*)::int FROM enquiries WHERE vendor_id=$1 AND first_reply_at IS NULL) AS unanswered`, [vendor.id]);
    const days = await q(`SELECT to_char(d, 'YYYY-MM-DD') AS day, coalesce(v.views,0) AS views FROM generate_series(current_date - 13, current_date, interval '1 day') d
      LEFT JOIN vendor_views v ON v.vendor_id=$1 AND v.day=d::date ORDER BY d`, [vendor.id]);
    return { ...s, reply_hours: s.reply_hours === null ? null : Number(s.reply_hours), days };
  });

  // ================= Couples and planners =================

  // Browse the directory: category, district, price, language, free on a date.
  app.get('/vendors', async (req) => {
    const qs = req.query as any;
    const where = [`v.status='approved'`];
    const vals: unknown[] = [];
    const add = (sql: string, v: unknown) => { vals.push(v); where.push(sql.replace('?', `$${vals.length}`)); };
    if (qs.category) add('v.category = ?', qs.category);
    if (qs.district) add('(v.district = ? OR ? = ANY(v.service_areas))'.replace('?', `$${vals.length + 1}`).replace('?', `$${vals.length + 1}`), qs.district);
    if (qs.language) add('? = ANY(v.languages)', qs.language);
    if (qs.max_price) add('EXISTS (SELECT 1 FROM vendor_packages p WHERE p.vendor_id=v.id AND p.starting_lkr <= ?)', Number(qs.max_price));
    if (qs.min_price) add('EXISTS (SELECT 1 FROM vendor_packages p WHERE p.vendor_id=v.id AND p.starting_lkr >= ?)', Number(qs.min_price));
    if (qs.date && /^\d{4}-\d{2}-\d{2}$/.test(qs.date)) add('NOT EXISTS (SELECT 1 FROM vendor_blocked_dates b WHERE b.vendor_id=v.id AND b.day = ?::date)', qs.date);
    if (qs.q) add('(v.business_name ILIKE ? OR v.description ILIKE $' + (vals.length + 1) + ')', `%${String(qs.q).slice(0, 60).replace(/[%_]/g, '\\$&')}%`);
    const rows = await q(`${CARD_SQL} WHERE ${where.join(' AND ')}`, vals);
    // Featured first (labelled), then rating and reply time.
    const cards = rows.map(card).sort((a, b) =>
      Number(b.featured) - Number(a.featured) || (b.rating ?? 0) - (a.rating ?? 0) || (a.reply_hours ?? 99) - (b.reply_hours ?? 99) || a.business_name.localeCompare(b.business_name));
    return { vendors: cards.slice(0, 200) };
  });

  app.get('/vendors/:slug', async (req) => {
    const v = await one(`${CARD_SQL} WHERE v.slug=$1 AND v.status='approved'`, [(req.params as any).slug]);
    if (!v) throw notFound('vendor_not_found');
    const full = await one('SELECT description, phone, whatsapp FROM vendors WHERE id=$1', [v.id]);
    const media = await q('SELECT id, kind, path, caption FROM vendor_media WHERE vendor_id=$1 AND ready ORDER BY sort, created_at', [v.id]);
    const packages = await q('SELECT id, name, includes, addons, starting_lkr, negotiable FROM vendor_packages WHERE vendor_id=$1 ORDER BY sort, starting_lkr', [v.id]);
    const reviews = await q(`SELECT r.id, r.rating, r.body, r.reply, r.created_at, w.partner1 FROM reviews r JOIN weddings w ON w.id=r.wedding_id
      WHERE r.vendor_id=$1 AND r.status='visible' ORDER BY r.created_at DESC LIMIT 50`, [v.id]);
    const viewer = await userFromRequest(req);
    if (!viewer || !(await one('SELECT 1 FROM vendors WHERE id=$1 AND owner_id=$2', [v.id, viewer.id]))) {
      await pool.query(`INSERT INTO vendor_views (vendor_id, views) VALUES ($1, 1) ON CONFLICT (vendor_id, day) DO UPDATE SET views = vendor_views.views + 1`, [v.id]);
    }
    return {
      vendor: { ...card(v), description: full.description, whatsapp: full.whatsapp ?? full.phone },
      media: media.map((m) => ({ id: m.id, kind: m.kind, caption: m.caption, url: mediaUrl(m.path) })),
      packages, reviews,
    };
  });

  // "Suggested for your wedding": serves the district, free on the date, packages near the budget.
  app.get('/weddings/:weddingId/vendor-suggestions', async (req) => {
    const a = await weddingAccess(req, 'view');
    const category = String((req.query as any).category ?? '');
    const w = await one(`SELECT w.district, (SELECT min(starts_at) FROM events e WHERE e.wedding_id=w.id) AS date FROM weddings w WHERE w.id=$1`, [a.weddingId]);
    const budget = await one(`SELECT sum(coalesce(total_lkr, estimated_lkr))::bigint AS b FROM budget_items WHERE wedding_id=$1 AND category = $2`, [a.weddingId, ({
      photographers: 'Photography', venues: 'Venue', decorators: 'Decoration', caterers: 'Food & drinks', makeup: 'Makeup & hair', bridal: 'Attire', music: 'Music', planners: 'Other',
    } as Record<string, string>)[category] ?? '']);
    const day = w.date ? new Date(new Date(w.date).getTime() + 5.5 * 3600000).toISOString().slice(0, 10) : null;
    const rows = await q(`${CARD_SQL} WHERE v.status='approved' AND ($1 = '' OR v.category=$1)
        AND ($2::text IS NULL OR v.district=$2 OR $2 = ANY(v.service_areas))
        AND ($3::date IS NULL OR NOT EXISTS (SELECT 1 FROM vendor_blocked_dates b WHERE b.vendor_id=v.id AND b.day=$3::date))`, [category, w.district, day]);
    const target = budget?.b ? Number(budget.b) : null;
    const cards = rows.map(card).map((c) => ({ ...c, fits_budget: target === null || c.starting_lkr === null ? null : Number(c.starting_lkr) <= target * 1.15 }))
      .sort((x, y) => Number(y.fits_budget ?? true) - Number(x.fits_budget ?? true) || (y.rating ?? 0) - (x.rating ?? 0) || (x.reply_hours ?? 99) - (y.reply_hours ?? 99));
    return { vendors: cards.slice(0, 20), based_on: { district: w.district, date: day, budget_lkr: target } };
  });

  // Shortlist (compare up to three side by side in the app).
  app.get('/weddings/:weddingId/shortlist', async (req) => {
    const a = await weddingAccess(req, 'view');
    const rows = await q(`${CARD_SQL} JOIN shortlists s ON s.vendor_id=v.id WHERE s.wedding_id=$1 ORDER BY s.created_at`, [a.weddingId]);
    const packs = await q(`SELECT p.vendor_id, p.name, p.starting_lkr, p.includes FROM vendor_packages p JOIN shortlists s ON s.vendor_id=p.vendor_id WHERE s.wedding_id=$1 ORDER BY p.starting_lkr`, [a.weddingId]);
    return { vendors: rows.map(card).map((c) => ({ ...c, packages: packs.filter((p) => p.vendor_id === c.id) })) };
  });

  app.put('/weddings/:weddingId/shortlist/:vendorId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const v = await one(`SELECT id FROM vendors WHERE id=$1 AND status='approved'`, [(req.params as any).vendorId]);
    if (!v) throw notFound('vendor_not_found');
    await pool.query('INSERT INTO shortlists (wedding_id, vendor_id, added_by) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [a.weddingId, v.id, a.user.id]);
    return { ok: true };
  });

  app.delete('/weddings/:weddingId/shortlist/:vendorId', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await pool.query('DELETE FROM shortlists WHERE wedding_id=$1 AND vendor_id=$2', [a.weddingId, (req.params as any).vendorId]);
    return { ok: true };
  });

  // One enquiry to several vendors, carrying the wedding's details.
  app.post('/weddings/:weddingId/enquiries', { config: { rateLimit: 20 } }, async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    if (!Array.isArray(b.vendor_ids) || !b.vendor_ids.length || b.vendor_ids.length > 10) throw bad('invalid_input', 'Choose 1–10 vendors.');
    const today = await one(`SELECT count(*)::int AS n FROM enquiries WHERE wedding_id=$1 AND created_at > now() - interval '1 day'`, [a.weddingId]);
    if (today.n + b.vendor_ids.length > 30) throw new HttpError(429, 'too_many_enquiries', 'You have contacted many vendors today. Please try again tomorrow.');
    const message = str(b.message, 'message', { max: 3000 })!;
    const w = await one(`SELECT w.expected_guests, w.district, (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id) AS guests,
        (SELECT coalesce(sum(r.headcount),0)::int FROM rsvps r JOIN guests g ON g.id=r.guest_id WHERE g.wedding_id=w.id AND r.status='coming') AS coming,
        e.starts_at, e.venue, e.address
      FROM weddings w LEFT JOIN LATERAL (SELECT starts_at, venue, address FROM events WHERE wedding_id=w.id ORDER BY starts_at LIMIT 1) e ON true WHERE w.id=$1`, [a.weddingId]);
    const guestCount = w.coming || w.expected_guests || (w.guests ? w.guests * 2 : null);
    const budget = b.share_budget === true && b.budget_lkr ? int(Math.round(Number(b.budget_lkr)), 'budget_lkr', 0, 1_000_000_000) : null;
    const created: string[] = [];
    await tx(async (c) => {
      for (const vid of b.vendor_ids) {
        const v = (await c.query(`SELECT id FROM vendors WHERE id=$1 AND status='approved'`, [vid])).rows[0];
        if (!v) continue;
        const e = (await c.query(`INSERT INTO enquiries (vendor_id, wedding_id, sender_id, wedding_date, location, guest_count, budget_lkr) VALUES ($1,$2,$3,$4,$5,$6,$7)
          ON CONFLICT (vendor_id, wedding_id) DO UPDATE SET couple_status = enquiries.couple_status RETURNING id`,
          [v.id, a.weddingId, a.user.id, w.starts_at, [w.venue, w.address, w.district].filter(Boolean).join(', ') || null, guestCount, budget])).rows[0];
        await c.query(`INSERT INTO enquiry_messages (enquiry_id, from_side, author_id, body) VALUES ($1,'couple',$2,$3)`, [e.id, a.user.id, message]);
        await c.query(`INSERT INTO shortlists (wedding_id, vendor_id, added_by) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, [a.weddingId, v.id, a.user.id]);
        created.push(e.id);
      }
    });
    return { sent: created.length };
  });

  app.get('/weddings/:weddingId/enquiries', async (req) => {
    const a = await weddingAccess(req, 'view');
    const rows = await q(`SELECT e.*, v.business_name, v.category, v.slug, v.whatsapp, v.phone,
        coalesce((SELECT json_agg(json_build_object('from', m.from_side, 'body', m.body, 'at', m.created_at) ORDER BY m.created_at) FROM enquiry_messages m WHERE m.enquiry_id=e.id), '[]') AS messages,
        EXISTS (SELECT 1 FROM reviews r WHERE r.vendor_id=e.vendor_id AND r.wedding_id=e.wedding_id) AS reviewed
      FROM enquiries e JOIN vendors v ON v.id=e.vendor_id WHERE e.wedding_id=$1 ORDER BY e.created_at DESC`, [a.weddingId]);
    return { enquiries: rows.map(({ phone, whatsapp, ...e }) => ({ ...e, whatsapp: (whatsapp ?? phone) ? `https://wa.me/${String(whatsapp ?? phone).replace('+', '')}` : null })) };
  });

  app.post('/weddings/:weddingId/enquiries/:id/messages', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const e = await one('SELECT id FROM enquiries WHERE id=$1 AND wedding_id=$2', [(req.params as any).id, a.weddingId]);
    if (!e) throw notFound();
    await pool.query(`INSERT INTO enquiry_messages (enquiry_id, from_side, author_id, body) VALUES ($1,'couple',$2,$3)`, [e.id, a.user.id, str((req.body as any)?.body, 'body', { max: 3000 })]);
    return { ok: true };
  });

  // Track each vendor. Booking adds the vendor to the budget and the run sheet.
  app.patch('/weddings/:weddingId/enquiries/:id', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const status = oneOf(b.status, 'status', ['contacted', 'quoted', 'booked', 'rejected'] as const);
    const e = await one(`UPDATE enquiries e SET couple_status=$3 FROM vendors v WHERE e.id=$1 AND e.wedding_id=$2 AND v.id=e.vendor_id
      RETURNING e.id, e.couple_status, v.business_name, v.category, (SELECT name FROM vendor_categories c WHERE c.id=v.category) AS category_name`, [(req.params as any).id, a.weddingId, status]);
    if (!e) throw notFound();
    if (status === 'booked') {
      const cat: Record<string, string> = { photographers: 'Photography', venues: 'Venue', decorators: 'Decoration', caterers: 'Food & drinks', makeup: 'Makeup & hair', bridal: 'Attire', music: 'Music' };
      const price = b.price_lkr ? int(Math.round(Number(b.price_lkr)), 'price_lkr', 0, 1_000_000_000) : null;
      if (!(await one('SELECT 1 FROM budget_items WHERE wedding_id=$1 AND vendor=$2', [a.weddingId, e.business_name]))) {
        await pool.query(`INSERT INTO budget_items (wedding_id, category, name, estimated_lkr, total_lkr, vendor) VALUES ($1,$2,$3,$4,$4,$5)`,
          [a.weddingId, cat[e.category] ?? 'Other', e.category_name, price ?? 0, e.business_name]);
      }
      if (!(await one('SELECT 1 FROM run_sheet_items WHERE wedding_id=$1 AND owner=$2', [a.weddingId, e.business_name]))) {
        const ev = await one('SELECT id FROM events WHERE wedding_id=$1 ORDER BY starts_at LIMIT 1', [a.weddingId]);
        await pool.query(`INSERT INTO run_sheet_items (wedding_id, event_id, time, item, owner, sort) VALUES ($1,$2,'TBC',$3,$4,-1)`,
          [a.weddingId, ev?.id ?? null, `${e.category_name} arrives and sets up`, e.business_name]);
      }
    }
    return { ok: true };
  });

  // Verified reviews: only a wedding that contacted the vendor, only after the wedding date,
  // and only a real wedding (paid, or invitations actually sent), so fake weddings can't review.
  app.post('/weddings/:weddingId/reviews', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const e = await one(`SELECT e.id, w.plan, (SELECT max(starts_at) FROM events ev WHERE ev.wedding_id=w.id) AS last,
        (SELECT count(*)::int FROM guests g WHERE g.wedding_id=w.id AND g.sent_at IS NOT NULL) AS sent
      FROM enquiries e JOIN weddings w ON w.id=e.wedding_id WHERE e.wedding_id=$1 AND e.vendor_id=$2`, [a.weddingId, b.vendor_id]);
    if (!e) throw new HttpError(403, 'not_contacted', 'You can review vendors you contacted through the app.');
    if (!e.last || new Date(e.last) > new Date()) throw new HttpError(403, 'too_early', 'Reviews open after your wedding.');
    if (e.plan !== 'pass' && e.sent < 10) throw new HttpError(403, 'not_verified', 'Reviews come from weddings that used the app for their invitations.');
    const r = await one(`INSERT INTO reviews (vendor_id, wedding_id, author_id, rating, body) VALUES ($1,$2,$3,$4,$5)
      ON CONFLICT (vendor_id, wedding_id) DO UPDATE SET rating=EXCLUDED.rating, body=EXCLUDED.body RETURNING id`,
      [b.vendor_id, a.weddingId, a.user.id, int(b.rating, 'rating', 1, 5), str(b.body, 'body', { max: 2000, optional: true })]);
    return { id: r.id };
  });

  // Complaints go to the team. Three open complaints from different real weddings hide the vendor
  // until the team has looked (so one competitor can't take a vendor down).
  app.post('/weddings/:weddingId/complaints', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    if (!(await one('SELECT 1 FROM enquiries WHERE wedding_id=$1 AND vendor_id=$2', [a.weddingId, b.vendor_id]))) throw new HttpError(403, 'not_contacted');
    await pool.query(`INSERT INTO vendor_complaints (vendor_id, wedding_id, author_id, body) VALUES ($1,$2,$3,$4) ON CONFLICT (vendor_id, wedding_id) DO UPDATE SET body=EXCLUDED.body, status='open'`,
      [b.vendor_id, a.weddingId, a.user.id, str(b.body, 'body', { max: 3000 })]);
    const open = await one(`SELECT count(DISTINCT c.wedding_id)::int AS n FROM vendor_complaints c JOIN weddings w ON w.id=c.wedding_id
      WHERE c.vendor_id=$1 AND c.status='open' AND (w.plan='pass' OR (SELECT count(*) FROM guests g WHERE g.wedding_id=w.id AND g.sent_at IS NOT NULL) >= 10)`, [b.vendor_id]);
    if (open.n >= 3) await pool.query(`UPDATE vendors SET status='under_review' WHERE id=$1 AND status='approved'`, [b.vendor_id]);
    return { ok: true };
  });

  // Planners: preferred vendors, shared into a client's shortlist.
  app.get('/planner/preferred-vendors', async (req) => {
    const u = await requireUser(req);
    const p = await one('SELECT planner_id FROM planner_members WHERE user_id=$1', [u.id]);
    if (!p) throw notFound('not_a_planner');
    return { vendors: (await q(`${CARD_SQL} JOIN planner_preferred_vendors pp ON pp.vendor_id=v.id WHERE pp.planner_id=$1 AND v.status='approved'`, [p.planner_id])).map(card) };
  });

  app.put('/planner/preferred-vendors/:vendorId', async (req) => {
    const u = await requireUser(req);
    const p = await one('SELECT planner_id FROM planner_members WHERE user_id=$1', [u.id]);
    if (!p) throw notFound('not_a_planner');
    const on = (req.body as any)?.preferred !== false;
    if (on) await pool.query('INSERT INTO planner_preferred_vendors VALUES ($1,$2) ON CONFLICT DO NOTHING', [p.planner_id, (req.params as any).vendorId]);
    else await pool.query('DELETE FROM planner_preferred_vendors WHERE planner_id=$1 AND vendor_id=$2', [p.planner_id, (req.params as any).vendorId]);
    return { ok: true };
  });
}
