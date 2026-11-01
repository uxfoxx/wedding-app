// Every request on a wedding checks the person's role on it (architecture decision 5).
import type { FastifyRequest } from 'fastify';
import { one } from '../db.ts';
import { requireUser, type AuthUser } from './auth.ts';
import { HttpError } from './util.ts';
import { planInfo } from './entitlements.ts';

export type Role = 'owner' | 'edit_all' | 'edit_guests' | 'view';
const RANK: Record<Role, number> = { view: 1, edit_guests: 2, edit_all: 3, owner: 4 };

export interface WeddingAccess { user: AuthUser; weddingId: string; role: Role }

/**
 * need = minimum role. Staff (admin/support) may read any wedding for support but
 * cannot edit through the couple endpoints; they use the admin endpoints, which are audited.
 */
export async function weddingAccess(req: FastifyRequest, need: Role, opts: { write?: boolean } = {}): Promise<WeddingAccess> {
  const user = await requireUser(req);
  const weddingId = (req.params as any).weddingId as string;
  if (!/^[0-9a-f-]{36}$/i.test(weddingId ?? '')) throw new HttpError(404, 'wedding_not_found');
  const m = await one<{ role: Role }>('SELECT role FROM wedding_members WHERE wedding_id=$1 AND user_id=$2', [weddingId, user.id]);
  let role: Role | undefined = m?.role;
  if (!role && user.staff_role && need === 'view') role = 'view';
  if (!role) throw new HttpError(404, 'wedding_not_found'); // don't reveal that it exists
  if (RANK[role] < RANK[need]) throw new HttpError(403, 'insufficient_role', `This needs "${need}" permission on the wedding.`);
  const write = opts.write ?? need !== 'view';
  if (write) {
    const info = await planInfo(weddingId);
    if (info.readOnly) throw new HttpError(409, 'wedding_archived', 'This wedding is now a read-only keepsake.');
  }
  return { user, weddingId, role };
}
