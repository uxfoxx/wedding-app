// Growth: referrals and credits, partner codes (discounts + co-branded templates), the
// "Real weddings" showcase, and attribution for sign-ups that came from a guest page.
import type { FastifyInstance } from 'fastify';
import { config, pricing } from '../config.ts';
import { one, q, pool, type Queryable } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { requireUser } from '../lib/auth.ts';
import { HttpError, bad, notFound, randomToken } from '../lib/util.ts';

export const growth = {
  referralDiscountLkr: Number(process.env.REFERRAL_DISCOUNT_LKR ?? 1000),
  referralCreditLkr: Number(process.env.REFERRAL_CREDIT_LKR ?? 1000),
};

export async function referralCodeFor(userId: string): Promise<string> {
  const have = await one('SELECT code FROM referral_codes WHERE user_id=$1', [userId]);
  if (have) return have.code;
  for (;;) {
    const code = randomToken(6).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
    if (code.length < 6) continue;
    const r = await pool.query('INSERT INTO referral_codes (code, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [code, userId]);
    if (r.rowCount) return code;
  }
}

export async function creditBalance(userId: string, db: Queryable = pool): Promise<number> {
  return (await one('SELECT coalesce(sum(amount_lkr),0)::int AS b FROM credits WHERE user_id=$1', [userId], db)).b;
}

/** Price for a Wedding Pass bought on the web: list price, then partner/referral discount, then credits. */
export async function passQuote(weddingId: string, userId: string) {
  const w = await one(`SELECT w.referral_code, w.partner_code, rc.user_id AS referrer, pc.discount_lkr AS partner_discount, pc.partner_name, pc.active AS partner_active
    FROM weddings w LEFT JOIN referral_codes rc ON rc.code=w.referral_code LEFT JOIN partner_codes pc ON pc.code=w.partner_code WHERE w.id=$1`, [weddingId]);
  const list = pricing.passWebLkr;
  let discount = 0;
  let reason: string | null = null;
  if (w.partner_code && w.partner_active && w.partner_discount > 0) { discount = w.partner_discount; reason = `Partner offer: ${w.partner_name}`; }
  else if (w.referral_code && w.referrer !== userId) { discount = growth.referralDiscountLkr; reason = 'Friend referral'; }
  discount = Math.min(discount, list);
  const credits = Math.min(await creditBalance(userId), list - discount);
  return { list, discount, reason, credits, total: list - discount - credits };
}

/** After a Wedding Pass is paid: the referrer earns a credit (once per referred wedding). */
export async function rewardReferrer(payment: any) {
  if (payment.product !== 'wedding_pass' || !payment.wedding_id) return;
  // Only real purchases earn rewards: not free grants by the team.
  if (payment.method === 'admin_grant' || Number(payment.amount_lkr) + Number(payment.credits_lkr ?? 0) <= 0) return;
  const w = await one(`SELECT rc.user_id FROM weddings w JOIN referral_codes rc ON rc.code=w.referral_code WHERE w.id=$1`, [payment.wedding_id]);
  if (!w || w.user_id === payment.user_id) return;
  const already = await one(`SELECT 1 FROM credits c JOIN payments p ON p.id=c.payment_id WHERE c.user_id=$1 AND p.wedding_id=$2 AND c.amount_lkr > 0`, [w.user_id, payment.wedding_id]);
  if (!already) await pool.query(`INSERT INTO credits (user_id, amount_lkr, reason, payment_id) VALUES ($1,$2,'Referral reward',$3)`, [w.user_id, growth.referralCreditLkr, payment.id]);
}

export default async function growthRoutes(app: FastifyInstance) {
  app.get('/me/referral', async (req) => {
    const u = await requireUser(req);
    const code = await referralCodeFor(u.id);
    const link = `${config.webPanelUrl}/#ref=${code}`;
    const joined = await one(`SELECT count(*)::int AS n, count(*) FILTER (WHERE plan='pass')::int AS paid FROM weddings WHERE referral_code=$1`, [code]);
    return {
      code, link, credits_lkr: await creditBalance(u.id), referred: joined.n, referred_paid: joined.paid,
      message: `We made our wedding invitation with this app. Use my link for LKR ${growth.referralDiscountLkr} off the Wedding Pass: ${link}`,
      offer: { friend_discount_lkr: growth.referralDiscountLkr, your_credit_lkr: growth.referralCreditLkr },
    };
  });

  // Landing for partner QR codes (venues, photographers, salons).
  app.get('/public/partner/:code', async (req) => {
    const p = await one(`SELECT code, partner_name, discount_lkr, template_id FROM partner_codes WHERE code=$1 AND active`, [String((req.params as any).code).toUpperCase()]);
    if (!p) throw notFound('invalid_code');
    return { partner: p };
  });

  // Attach a referral or partner code to a wedding (at sign-up, or later before paying).
  app.post('/weddings/:weddingId/code', async (req) => {
    const a = await weddingAccess(req, 'owner');
    const code = String((req.body as any)?.code ?? '').trim().toUpperCase();
    if (await one(`SELECT 1 FROM payments WHERE wedding_id=$1 AND status='paid' AND product='wedding_pass'`, [a.weddingId])) throw bad('already_paid');
    const partner = await one('SELECT code FROM partner_codes WHERE code=$1 AND active', [code]);
    if (partner) {
      await pool.query('UPDATE weddings SET partner_code=$2 WHERE id=$1', [a.weddingId, code]);
      await pool.query('UPDATE partner_codes SET uses=uses+1 WHERE code=$1', [code]);
      return { applied: 'partner' };
    }
    const ref = await one('SELECT user_id FROM referral_codes WHERE code=$1', [code]);
    if (ref) {
      if (ref.user_id === a.user.id) throw bad('own_code', 'You can\'t use your own referral code.');
      await pool.query('UPDATE weddings SET referral_code=$2 WHERE id=$1', [a.weddingId, code]);
      return { applied: 'referral' };
    }
    throw new HttpError(404, 'invalid_code', 'That code was not found.');
  });

  app.get('/weddings/:weddingId/quote', async (req) => {
    const a = await weddingAccess(req, 'view');
    return passQuote(a.weddingId, a.user.id);
  });

  // "Real weddings" showcase, only with the couple's permission and the team's approval.
  app.post('/weddings/:weddingId/showcase', async (req) => {
    const a = await weddingAccess(req, 'owner');
    const on = (req.body as any)?.share === true;
    await pool.query(`UPDATE weddings SET showcase = CASE WHEN $2 THEN (CASE WHEN showcase='approved' THEN 'approved' ELSE 'requested' END) ELSE 'off' END WHERE id=$1`, [a.weddingId, on]);
    return { showcase: (await one('SELECT showcase FROM weddings WHERE id=$1', [a.weddingId])).showcase };
  });

  app.get('/public/showcase', async () => {
    const rows = await q(`SELECT w.partner1, w.partner2, w.wedding_type, w.district, w.slug, w.invitation->>'cover_photo_url' AS cover, t.name AS template, t.layout,
        (SELECT min(starts_at) FROM events e WHERE e.wedding_id=w.id) AS date,
        coalesce((SELECT json_agg(json_build_object('name', v.business_name, 'category', v.category, 'slug', v.slug)) FROM enquiries e JOIN vendors v ON v.id=e.vendor_id
          WHERE e.wedding_id=w.id AND e.couple_status='booked' AND v.status='approved'), '[]') AS vendors
      FROM weddings w LEFT JOIN templates t ON t.id=w.template_id WHERE w.showcase='approved' AND w.published_at IS NOT NULL ORDER BY date DESC NULLS LAST LIMIT 60`);
    return { weddings: rows.map((r) => ({ ...r, page_url: `${config.guestBaseUrl}/${r.slug}/` })) };
  });
}
