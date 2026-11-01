// Guest experience on the day: live updates, menu, guest photos/videos, photo wall, guestbook
// (text and voice notes), song requests, Find your seat, and the keepsake page.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join, normalize } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { config, pricing } from '../config.ts';
import { one, q, pool } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { assertFeature, planInfo } from '../lib/entitlements.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { normName } from '../lib/duplicates.ts';
import { mediaUrl, storage, uploadUrl } from '../lib/storage.ts';
import { HttpError, bad, notFound, oneOf, randomToken, str } from '../lib/util.ts';

const TYPES: Record<string, { kind: 'photo' | 'video' | 'voice'; ext: string }> = {
  'image/jpeg': { kind: 'photo', ext: 'jpg' }, 'image/png': { kind: 'photo', ext: 'png' }, 'image/webp': { kind: 'photo', ext: 'webp' },
  'image/heic': { kind: 'photo', ext: 'heic' },
  'video/mp4': { kind: 'video', ext: 'mp4' }, 'video/quicktime': { kind: 'video', ext: 'mov' }, 'video/webm': { kind: 'video', ext: 'webm' },
  'audio/webm': { kind: 'voice', ext: 'webm' }, 'audio/ogg': { kind: 'voice', ext: 'ogg' }, 'audio/mp4': { kind: 'voice', ext: 'm4a' }, 'audio/mpeg': { kind: 'voice', ext: 'mp3' },
};
const MAX = { photo: pricing.maxPhotoBytes, video: pricing.maxVideoBytes, voice: pricing.maxVoiceBytes };

/** A published wedding that has the Wedding Pass, looked up by its public slug. */
async function publicWedding(slug: unknown, feature?: 'uploads' | 'seating') {
  if (typeof slug !== 'string' || !/^[A-Za-z0-9_-]{6,20}$/.test(slug)) throw notFound('invalid_link');
  const w = await one('SELECT id, settings, published_at, partner1, partner2 FROM weddings WHERE slug=$1', [slug]);
  if (!w?.published_at) throw notFound('invalid_link');
  if (feature) {
    const info = await planInfo(w.id);
    if (!info.limits[feature]) throw notFound('not_available');
    if (feature === 'uploads' && w.settings?.uploads_enabled === false) throw new HttpError(403, 'uploads_closed', 'The couple has closed uploads.');
  }
  return w;
}

async function guestIdFromToken(weddingId: string, token: unknown): Promise<string | null> {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{16,64}$/.test(token)) return null;
  return (await one('SELECT id FROM guests WHERE token=$1 AND wedding_id=$2', [token, weddingId]))?.id ?? null;
}

const pub = (u: any) => ({ id: u.id, kind: u.kind, url: mediaUrl(u.path), uploader: u.uploader, created_at: u.created_at });

export default async function experienceRoutes(app: FastifyInstance) {
  // =============== Couple side ===============
  app.get('/weddings/:weddingId/experience', async (req) => {
    const a = await weddingAccess(req, 'view');
    const w = await one('SELECT slug, settings, invitation FROM weddings WHERE id=$1', [a.weddingId]);
    const counts = await one(`SELECT
        (SELECT count(*)::int FROM uploads WHERE wedding_id=$1 AND status='pending') AS pending,
        (SELECT count(*)::int FROM uploads WHERE wedding_id=$1 AND status='approved') AS approved,
        (SELECT coalesce(sum(size_bytes),0)::bigint FROM uploads WHERE wedding_id=$1 AND status <> 'uploading') AS bytes,
        (SELECT count(*)::int FROM guestbook_entries WHERE wedding_id=$1) AS guestbook,
        (SELECT count(*)::int FROM song_requests WHERE wedding_id=$1 AND played_at IS NULL) AS songs`, [a.weddingId]);
    const base = `${config.guestBaseUrl}/${w.slug}`;
    return {
      settings: { uploads_enabled: w.settings?.uploads_enabled !== false, wall_requires_approval: w.settings?.wall_requires_approval !== false, seating_published: !!w.settings?.seating_published },
      menu: w.invitation?.menu ?? [],
      updates: await q('SELECT id, body, kind, created_at FROM wedding_updates WHERE wedding_id=$1 ORDER BY created_at DESC', [a.weddingId]),
      counts: { ...counts, storage_mb: Math.round(Number(counts.bytes) / 1048576), storage_limit_mb: w.settings?.storage_limit_mb ?? pricing.weddingStorageMb },
      links: { share: `${base}/share.html`, wall: `${base}/wall.html`, seat: `${base}/seat.html`, keepsake: `${base}/keepsake.html` },
    };
  });

  app.patch('/weddings/:weddingId/experience/settings', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const patch: Record<string, boolean> = {};
    for (const k of ['uploads_enabled', 'wall_requires_approval']) if (typeof b[k] === 'boolean') patch[k] = b[k];
    await pool.query(`UPDATE weddings SET settings = settings || $2::jsonb WHERE id=$1`, [a.weddingId, JSON.stringify(patch)]);
    return { ok: true };
  });

  // Live updates: shown on every guest page; a WhatsApp send queue goes to confirmed guests.
  app.post('/weddings/:weddingId/updates', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const u = await one(`INSERT INTO wedding_updates (wedding_id, body, kind, created_by) VALUES ($1,$2,$3,$4) RETURNING *`,
      [a.weddingId, str(b.body, 'body', { max: 500 }), oneOf(b.kind, 'kind', ['info', 'time', 'venue', 'dress_code', 'parking'] as const, 'info'), a.user.id]);
    await enqueuePublish(a.weddingId);
    return { update: u };
  });

  app.delete('/weddings/:weddingId/updates/:id', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    await pool.query('DELETE FROM wedding_updates WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).id]);
    await enqueuePublish(a.weddingId);
    return { ok: true };
  });

  // Digital menu with allergens.
  app.put('/weddings/:weddingId/menu', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const items = (req.body as any)?.items;
    if (!Array.isArray(items) || items.length > 60) throw bad('invalid_input', 'items must be a list');
    const clean = items.map((it: any, i: number) => ({
      course: str(it.course, `items[${i}].course`, { max: 40, optional: true }),
      name: str(it.name, `items[${i}].name`, { max: 100 }),
      note: str(it.note, `items[${i}].note`, { max: 200, optional: true }),
      allergens: Array.isArray(it.allergens) ? it.allergens.slice(0, 10).map((x: unknown) => str(x, 'allergen', { max: 30 })) : [],
      diet: Array.isArray(it.diet) ? it.diet.filter((d: unknown) => ['vegetarian', 'vegan', 'halal'].includes(d as string)) : [],
    }));
    await pool.query(`UPDATE weddings SET invitation = invitation || jsonb_build_object('menu', $2::jsonb) WHERE id=$1`, [a.weddingId, JSON.stringify(clean)]);
    await enqueuePublish(a.weddingId);
    return { items: clean };
  });

  app.get('/weddings/:weddingId/uploads', async (req) => {
    const a = await weddingAccess(req, 'view');
    const status = oneOf((req.query as any).status, 'status', ['pending', 'approved', 'hidden'] as const, 'pending');
    const rows = await q(`SELECT * FROM uploads WHERE wedding_id=$1 AND status=$2 ORDER BY reported_at DESC NULLS LAST, created_at DESC LIMIT 500`, [a.weddingId, status]);
    return { uploads: rows.map((u) => ({ ...pub(u), status: u.status, reported: !!u.reported_at, size_bytes: u.size_bytes })) };
  });

  app.post('/weddings/:weddingId/uploads/moderate', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const status = oneOf(b.status, 'status', ['approved', 'hidden'] as const);
    if (!Array.isArray(b.ids) || b.ids.length > 500) throw bad('invalid_input');
    const r = await pool.query(`UPDATE uploads SET status=$3, reported_at = CASE WHEN $3='approved' THEN NULL ELSE reported_at END
      WHERE wedding_id=$1 AND id::text = ANY($2) AND status <> 'uploading'`, [a.weddingId, b.ids.map(String), status]);
    return { updated: r.rowCount };
  });

  app.get('/weddings/:weddingId/guestbook', async (req) => {
    const a = await weddingAccess(req, 'view');
    const rows = await q(`SELECT e.*, u.path FROM guestbook_entries e LEFT JOIN uploads u ON u.id=e.upload_id WHERE e.wedding_id=$1 ORDER BY e.created_at DESC`, [a.weddingId]);
    return { entries: rows.map(({ path, ...e }) => ({ ...e, voice_url: path ? mediaUrl(path) : null, reported: !!e.reported_at })) };
  });

  app.patch('/weddings/:weddingId/guestbook/:id', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const status = oneOf((req.body as any)?.status, 'status', ['visible', 'hidden'] as const);
    const r = await pool.query('UPDATE guestbook_entries SET status=$3 WHERE id=$2 AND wedding_id=$1', [a.weddingId, (req.params as any).id, status]);
    if (!r.rowCount) throw notFound();
    return { ok: true };
  });

  app.get('/weddings/:weddingId/songs', async (req) => {
    const a = await weddingAccess(req, 'view');
    return { songs: await q('SELECT * FROM song_requests WHERE wedding_id=$1 ORDER BY played_at NULLS FIRST, created_at', [a.weddingId]) };
  });

  app.patch('/weddings/:weddingId/songs/:id', async (req) => {
    const a = await weddingAccess(req, 'edit_guests');
    await pool.query(`UPDATE song_requests SET played_at = CASE WHEN $3 THEN now() ELSE NULL END WHERE id=$2 AND wedding_id=$1`, [a.weddingId, (req.params as any).id, (req.body as any)?.played !== false]);
    return { ok: true };
  });

  // =============== Guest side (no login) ===============

  // Step 1: ask where to upload. The bytes then go straight to storage.
  app.post('/public/uploads', { config: { rateLimit: 40 } }, async (req) => {
    const b = req.body as any;
    const w = await publicWedding(b?.slug, 'uploads');
    const type = TYPES[String(b?.content_type)];
    if (!type) throw bad('unsupported_type', 'Photos (JPG, PNG, WebP, HEIC), videos (MP4, MOV, WebM) or voice notes only.');
    const size = Number(b?.size);
    if (!Number.isInteger(size) || size <= 0 || size > MAX[type.kind]) throw bad('too_large', `That file is too large (max ${Math.round(MAX[type.kind] / 1048576)} MB).`);
    const used = await one(`SELECT coalesce(sum(size_bytes),0)::bigint AS b FROM uploads WHERE wedding_id=$1 AND status <> 'hidden'`, [w.id]);
    const limitMb = w.settings?.storage_limit_mb ?? pricing.weddingStorageMb;
    if (Number(used.b) + size > limitMb * 1048576) throw new HttpError(507, 'storage_full', 'The album is full. Please ask the couple.');
    const token = randomToken(24);
    const path = `media/${w.id}/${randomToken(12)}.${type.ext}`;
    const u = await one(`INSERT INTO uploads (wedding_id, kind, path, content_type, size_bytes, uploader, guest_id, upload_token) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
      [w.id, type.kind, path, b.content_type, size, str(b.name, 'name', { max: 60, optional: true }), await guestIdFromToken(w.id, b.token), token]);
    return { id: u.id, upload_token: token, upload_url: uploadUrl(`g_${token}`), method: 'PUT' };
  });

  // Step 2: confirm the upload finished. Photos go to the wall now, or wait for the couple's approval.
  app.post('/public/uploads/:id/complete', { config: { rateLimit: 60 } }, async (req) => {
    const token = String((req.body as any)?.upload_token ?? '');
    const u = await one(`SELECT u.*, w.settings FROM uploads u JOIN weddings w ON w.id=u.wedding_id WHERE u.id=$1 AND u.upload_token=$2 AND u.status='uploading'`, [(req.params as any).id, token]);
    if (!u) throw notFound('upload_not_found');
    // Trust storage, not the browser: the file must exist and match the size that was allowed.
    const actual = await storage.size(u.path);
    if (actual === null) throw bad('not_uploaded', 'The file has not arrived yet.');
    if (actual > MAX[u.kind as 'photo' | 'video' | 'voice']) { await storage.del(u.path); throw bad('too_large'); }
    await pool.query('UPDATE uploads SET size_bytes=$2 WHERE id=$1', [u.id, actual]);
    const status = u.kind === 'voice' || u.settings?.wall_requires_approval === false ? 'approved' : 'pending';
    await pool.query(`UPDATE uploads SET status=$2 WHERE id=$1`, [u.id, status]);
    return { status };
  });

  // Development stand-in for object storage (production uses presigned URLs on R2/S3).
  if (config.env !== 'production') {
    app.put('/dev-upload/g_:token', { bodyLimit: pricing.maxVideoBytes }, async (req) => {
      const u = await one(`SELECT path, content_type, size_bytes FROM uploads WHERE upload_token=$1 AND status='uploading'`, [(req.params as any).token]);
      if (!u) throw notFound();
      const body = req.body as Buffer;
      if (!Buffer.isBuffer(body) || req.headers['content-type'] !== u.content_type) throw bad('wrong_type');
      if (body.length > MAX[TYPES[u.content_type].kind]) throw bad('too_large');
      const root = normalize(config.storageDir);
      const file = normalize(join(root, u.path));
      if (!file.startsWith(root)) throw bad('bad_path');
      await mkdir(dirname(file), { recursive: true });
      await writeFile(file, body);
      return { ok: true };
    });
  }

  app.post('/public/report', { config: { rateLimit: 20 } }, async (req) => {
    const b = req.body as any;
    const w = await publicWedding(b?.slug);
    const kind = oneOf(b?.kind, 'kind', ['upload', 'guestbook'] as const);
    // A report takes the item off the wall/keepsake until the couple (or admin) reviews it.
    if (kind === 'upload') await pool.query(`UPDATE uploads SET reported_at=now(), status='pending' WHERE id=$1 AND wedding_id=$2 AND status='approved'`, [b.id, w.id]);
    else await pool.query(`UPDATE guestbook_entries SET reported_at=now(), status='hidden' WHERE id=$1 AND wedding_id=$2`, [b.id, w.id]);
    return { ok: true };
  });

  app.post('/public/guestbook', { config: { rateLimit: 20 } }, async (req) => {
    const b = req.body as any;
    const w = await publicWedding(b?.slug, 'uploads');
    const message = str(b.message, 'message', { max: 1500, optional: true });
    let uploadId: string | null = null;
    if (b.upload_id) {
      const up = await one(`SELECT id FROM uploads WHERE id=$1 AND wedding_id=$2 AND kind='voice' AND status <> 'uploading'`, [b.upload_id, w.id]);
      if (!up) throw bad('voice_note_not_found');
      uploadId = up.id;
    }
    if (!message && !uploadId) throw bad('empty', 'Write a message or record a voice note.');
    const e = await one(`INSERT INTO guestbook_entries (wedding_id, name, message, upload_id) VALUES ($1,$2,$3,$4) RETURNING id`,
      [w.id, str(b.name, 'name', { max: 60 }), message, uploadId]);
    return { id: e.id };
  });

  app.post('/public/songs', { config: { rateLimit: 20 } }, async (req) => {
    const b = req.body as any;
    const w = await publicWedding(b?.slug, 'uploads');
    const e = await one(`INSERT INTO song_requests (wedding_id, name, song) VALUES ($1,$2,$3) RETURNING id`,
      [w.id, str(b.name, 'name', { max: 60, optional: true }), str(b.song, 'song', { max: 150 })]);
    return { id: e.id };
  });

  // Live photo wall for a screen at the reception (one screen polls; guests never do).
  app.get('/public/wall', { config: { rateLimit: 30 } }, async (req) => {
    const { slug, after } = req.query as any;
    const w = await publicWedding(slug, 'uploads');
    const rows = await q(`SELECT * FROM uploads WHERE wedding_id=$1 AND status='approved' AND kind IN ('photo','video')
      AND ($2::timestamptz IS NULL OR created_at > $2) ORDER BY created_at DESC LIMIT 200`, [w.id, after || null]);
    return { couple: `${w.partner1} & ${w.partner2}`, items: rows.map(pub) };
  });

  // After the wedding: album + guestbook as a keepsake page.
  app.get('/public/keepsake', { config: { rateLimit: 30 } }, async (req) => {
    const w = await publicWedding((req.query as any).slug, 'uploads');
    const photos = await q(`SELECT * FROM uploads WHERE wedding_id=$1 AND status='approved' AND kind IN ('photo','video') ORDER BY created_at LIMIT 2000`, [w.id]);
    const book = await q(`SELECT e.id, e.name, e.message, e.created_at, u.path FROM guestbook_entries e LEFT JOIN uploads u ON u.id=e.upload_id
      WHERE e.wedding_id=$1 AND e.status='visible' ORDER BY e.created_at`, [w.id]);
    return { couple: `${w.partner1} & ${w.partner2}`, photos: photos.map(pub), guestbook: book.map(({ path, ...e }) => ({ ...e, voice_url: path ? mediaUrl(path) : null })) };
  });

  // Find your seat by name (from the QR board at the venue entrance).
  app.post('/public/find-seat', { config: { rateLimit: 30 } }, async (req) => {
    const b = req.body as any;
    const w = await publicWedding(b?.slug, 'seating');
    if (!w.settings?.seating_published) throw notFound('not_available');
    const name = normName(str(b.name, 'name', { max: 80 })!);
    if (name.length < 3) throw bad('name_too_short');
    const rows = await q(`SELECT g.name, g.title, t.name AS table_name, e.kind, e.title AS event_title, e.starts_at
      FROM seat_assignments sa JOIN guests g ON g.id=sa.guest_id JOIN seating_tables t ON t.id=sa.table_id JOIN events e ON e.id=sa.event_id
      WHERE g.wedding_id=$1 ORDER BY e.starts_at`, [w.id]);
    // Match every word typed against the guest's name; never return more than a handful.
    const words = name.split(' ');
    const hits = rows.filter((r) => { const n = normName(r.name); return words.every((x) => n.includes(x)); }).slice(0, 6);
    return { matches: hits.map((r) => ({ name: [r.title, r.name].filter(Boolean).join(' '), table: r.table_name, event: r.event_title ?? r.kind })) };
  });
}
