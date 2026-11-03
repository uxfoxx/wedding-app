// The couple's cover photo, gallery and background music, uploaded from the phone or the web
// panel. Like guest photos, the bytes go straight to storage; the API only signs and checks.
import type { FastifyInstance } from 'fastify';
import { pricing } from '../config.ts';
import { one, q, pool } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { mediaUrl, storage, uploadTarget, usingObjectStorage } from '../lib/storage.ts';
import { bad, notFound, oneOf, randomToken } from '../lib/util.ts';
import { weddingSummary } from './weddings.ts';

const PHOTO: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const AUDIO: Record<string, string> = { 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/x-m4a': 'm4a' };
export const MAX_MUSIC_BYTES = 15 * 1024 * 1024;
export const MAX_GALLERY = 12;

/** Deletes this wedding's uploaded files that the invitation no longer uses. */
export async function pruneInvitationMedia(weddingId: string) {
  const w = await one('SELECT invitation FROM weddings WHERE id=$1', [weddingId]);
  const inv = w?.invitation ?? {};
  const used = new Set<string>([inv.cover_photo_url, inv.music_url, ...(inv.photos ?? [])].filter(Boolean));
  const rows = await q<{ id: string; path: string }>(`SELECT id, path FROM invitation_media WHERE wedding_id=$1 AND ready`, [weddingId]);
  for (const m of rows) {
    if (used.has(mediaUrl(m.path))) continue;
    await storage.del(m.path);
    await pool.query('DELETE FROM invitation_media WHERE id=$1', [m.id]);
  }
}

export default async function invitationMediaRoutes(app: FastifyInstance) {
  // Step 1: ask where to upload. kind: cover (replaces), photo (adds to the gallery) or music (replaces).
  app.post('/weddings/:weddingId/invitation-media', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const kind = oneOf(b?.kind, 'kind', ['cover', 'photo', 'music'] as const);
    const ext = (kind === 'music' ? AUDIO : PHOTO)[String(b?.content_type)];
    if (!ext) throw bad('unsupported_type', kind === 'music' ? 'Music must be an MP3 or M4A file.' : 'Photos must be JPEG, PNG or WebP.');
    const size = Number(b?.size);
    const max = kind === 'music' ? MAX_MUSIC_BYTES : pricing.maxPhotoBytes;
    if (!Number.isInteger(size) || size <= 0 || size > max) throw bad('too_large', `Files can be up to ${Math.round(max / 1048576)} MB.`);
    if (kind === 'photo') {
      const w = await one('SELECT invitation FROM weddings WHERE id=$1', [a.weddingId]);
      if ((w.invitation?.photos ?? []).length >= MAX_GALLERY) throw bad('gallery_full', `The gallery holds up to ${MAX_GALLERY} photos.`);
    }
    const token = randomToken(24);
    const path = `media/invitations/${a.weddingId}/${randomToken(12)}.${ext}`;
    const m = await one(`INSERT INTO invitation_media (wedding_id, kind, path, content_type, size_bytes, upload_token) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
      [a.weddingId, kind, path, b.content_type, size, token]);
    return { id: m.id, upload_url: await uploadTarget(path, b.content_type, size, `i_${token}`), method: 'PUT' };
  });

  // Step 2: once the bytes are stored, put the file on the invitation and republish.
  app.post('/weddings/:weddingId/invitation-media/:id/complete', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const m = await one('SELECT * FROM invitation_media WHERE id=$1 AND wedding_id=$2 AND NOT ready', [(req.params as any).id, a.weddingId]);
    if (!m) throw notFound();
    const size = await storage.size(m.path);
    if (size === null) throw bad('not_uploaded');
    if (size > (m.kind === 'music' ? MAX_MUSIC_BYTES : pricing.maxPhotoBytes)) {
      await storage.del(m.path);
      await pool.query('DELETE FROM invitation_media WHERE id=$1', [m.id]);
      throw bad('too_large');
    }
    await pool.query('UPDATE invitation_media SET ready=true, size_bytes=$2, upload_token=NULL WHERE id=$1', [m.id, size]);
    const url = mediaUrl(m.path);
    if (m.kind === 'photo') {
      // Appended only while there is room, checked again here in case two uploads raced.
      await pool.query(`UPDATE weddings SET invitation = jsonb_set(invitation, '{photos}', coalesce(invitation->'photos', '[]'::jsonb) || to_jsonb($2::text))
        WHERE id=$1 AND jsonb_array_length(coalesce(invitation->'photos', '[]'::jsonb)) < $3`, [a.weddingId, url, MAX_GALLERY]);
    } else {
      await pool.query(`UPDATE weddings SET invitation = invitation || jsonb_build_object($2::text, $3::text) WHERE id=$1`,
        [a.weddingId, m.kind === 'cover' ? 'cover_photo_url' : 'music_url', url]);
    }
    await pruneInvitationMedia(a.weddingId);
    const w = await one('SELECT published_at FROM weddings WHERE id=$1', [a.weddingId]);
    if (w.published_at) await enqueuePublish(a.weddingId);
    return { url, ...(await weddingSummary(a.weddingId, a.role)) };
  });

  // Development stand-in for the presigned upload.
  if (!usingObjectStorage) {
    app.put('/dev-upload/i_:token', { bodyLimit: Math.max(MAX_MUSIC_BYTES, pricing.maxPhotoBytes) }, async (req) => {
      const m = await one('SELECT path, content_type, size_bytes FROM invitation_media WHERE upload_token=$1 AND NOT ready', [(req.params as any).token]);
      if (!m || req.headers['content-type'] !== m.content_type || !Buffer.isBuffer(req.body) || req.body.length > Number(m.size_bytes)) throw notFound();
      await storage.put(m.path, req.body as Buffer, m.content_type);
      return { ok: true };
    });
  }
}
