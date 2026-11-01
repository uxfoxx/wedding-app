// Wedding Pass purchases.
//  • Web panel: card via the local payment gateway (webhook marks the wedding paid) or bank transfer (admin approves).
//  • Mobile apps: App Store / Google Play in-app purchase at a higher price that covers the store fee.
//    Apple's multiplatform rule (3.1.3(b)) lets the app unlock web purchases only if the same item is
//    also sold in-app, so the apps offer IAP and never link to the web checkout.
import { createHmac } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { config, pricing } from '../config.ts';
import { one, q, pool, tx } from '../db.ts';
import { weddingAccess } from '../lib/access.ts';
import { planInfo } from '../lib/entitlements.ts';
import { enqueuePublish } from '../lib/jobs.ts';
import { outbox } from '../lib/notify.ts';
import { HttpError, bad, escapeHtml, oneOf, randomToken, safeEqual, str } from '../lib/util.ts';
import { creditBalance, passQuote, rewardReferrer } from './growth.ts';

export function reference() {
  // Short, readable reference for bank transfers: WP-7K3Q9M
  return 'WP-' + randomToken(6).toUpperCase().replace(/[^A-Z0-9]/g, 'X').slice(0, 6);
}

export function signWebhook(body: string) {
  return createHmac('sha256', config.gatewaySecret).update(body).digest('hex');
}

/** Marks a payment paid and unlocks the wedding. Idempotent. */
export async function markPaid(paymentId: string, opts: { externalId?: string | null; approvedBy?: string | null } = {}) {
  return tx(async (c) => {
    const p = (await c.query(`UPDATE payments SET status='paid', paid_at=now(), external_id=coalesce($2, external_id), approved_by=coalesce($3, approved_by)
      WHERE id=$1 AND status='pending' RETURNING *`, [paymentId, opts.externalId ?? null, opts.approvedBy ?? null])).rows[0];
    if (!p) return null;
    if (p.credits_lkr > 0) {
      // Spend the credits now; if the balance changed meanwhile, the payment still stands (credits can't go below zero).
      const bal = await creditBalance(p.user_id, c);
      const use = Math.min(bal, p.credits_lkr);
      if (use > 0) await c.query(`INSERT INTO credits (user_id, amount_lkr, reason, payment_id) VALUES ($1,$2,'Used on Wedding Pass',$3)`, [p.user_id, -use, p.id]);
    }
    if (p.product === 'wedding_pass') {
      await c.query(`UPDATE weddings SET plan='pass', paid_at=now() WHERE id=$1`, [p.wedding_id]);
    } else if (p.product === 'design_for_me') {
      await c.query(`UPDATE design_jobs SET status='queued' WHERE wedding_id=$1 AND status='awaiting_payment'`, [p.wedding_id]);
    }
    return p;
  }).then(async (p) => {
    if (p) {
      await rewardReferrer(p);
      await enqueuePublish(p.wedding_id); // removes the "Made with" footer
      const u = await one('SELECT email, phone FROM users WHERE id=$1', [p.user_id]);
      const text = `Thank you! Payment ${p.reference} of LKR ${p.amount_lkr.toLocaleString('en-LK')} received for ${p.product === 'wedding_pass' ? 'the Wedding Pass' : 'Design it for me'}.`;
      if (u?.email) await outbox.email(u.email, 'Your receipt', text);
    }
    return p;
  });
}

export default async function paymentRoutes(app: FastifyInstance) {
  app.get('/weddings/:weddingId/billing', async (req) => {
    const a = await weddingAccess(req, 'view');
    const info = await planInfo(a.weddingId);
    const payments = await q(`SELECT id, product, method, amount_lkr, status, reference, created_at, paid_at FROM payments WHERE wedding_id=$1 ORDER BY created_at DESC`, [a.weddingId]);
    return {
      plan: info,
      prices: { passWebLkr: pricing.passWebLkr, passAppLkr: pricing.passAppLkr, designForMeLkr: pricing.designForMeLkr },
      payments,
      bank: { name: 'Bank account details are set by the admin', note: 'Use the reference as the payment description.' },
    };
  });

  // Web panel checkout. Returns a URL on the gateway's hosted page.
  app.post('/weddings/:weddingId/checkout', async (req) => {
    const a = await weddingAccess(req, 'edit_all', { write: false });
    const b = req.body as any;
    const product = oneOf(b?.product, 'product', ['wedding_pass', 'design_for_me'] as const, 'wedding_pass');
    const method = oneOf(b?.method, 'method', ['gateway', 'bank_transfer'] as const, 'gateway');
    if (product === 'wedding_pass' && (await planInfo(a.weddingId)).plan === 'pass') throw bad('already_paid');
    const quote = product === 'wedding_pass' ? await passQuote(a.weddingId, a.user.id)
      : { list: pricing.designForMeLkr, discount: 0, reason: null, credits: 0, total: pricing.designForMeLkr };
    const p = await one(`INSERT INTO payments (wedding_id, user_id, product, method, amount_lkr, reference, list_price_lkr, discount_lkr, credits_lkr, discount_reason)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id, reference, amount_lkr`,
      [a.weddingId, a.user.id, product, method, quote.total, reference(), quote.list, quote.discount, quote.credits, quote.reason]);
    if (quote.total === 0) {
      await markPaid(p.id);
      return { paymentId: p.id, reference: p.reference, amount_lkr: 0, status: 'paid', quote };
    }
    if (method === 'bank_transfer') {
      return { quote, paymentId: p.id, reference: p.reference, amount_lkr: p.amount_lkr, status: 'pending', instructions: 'Transfer the amount and use the reference as the description. We unlock the wedding as soon as the payment is confirmed (usually within one working day).' };
    }
    // Development stands in for the gateway with a local page; production redirects to the provider.
    return { quote, paymentId: p.id, reference: p.reference, amount_lkr: p.amount_lkr, checkoutUrl: `${config.publicApiUrl}/api/payments/dev-checkout/${p.id}` };
  });

  // Gateway webhook (architecture decision 6). Signed with a shared secret.
  app.post('/payments/webhook', async (req) => {
    const sig = String(req.headers['x-signature'] ?? '');
    const raw = (req as any).rawBody as string;
    if (!raw || !safeEqual(sig, signWebhook(raw))) throw new HttpError(401, 'bad_signature');
    const b = JSON.parse(raw);
    const p = await one('SELECT id, amount_lkr FROM payments WHERE reference=$1', [b.reference]);
    if (!p) throw new HttpError(404, 'unknown_payment');
    if (b.status !== 'paid') {
      await pool.query(`UPDATE payments SET status='failed' WHERE id=$1 AND status='pending'`, [p.id]);
      return { ok: true };
    }
    if (Number(b.amount_lkr) !== p.amount_lkr) throw bad('amount_mismatch');
    await markPaid(p.id, { externalId: b.transaction_id ?? null });
    return { ok: true };
  });

  // In-app purchase receipt. Needs App Store Server API / Google Play Developer API credentials,
  // which only exist once the store listings are set up. Until then it refuses rather than trusting the client.
  app.post('/weddings/:weddingId/iap', async (req) => {
    await weddingAccess(req, 'edit_all', { write: false });
    oneOf((req.body as any)?.store, 'store', ['app_store', 'play_store'] as const);
    str((req.body as any)?.receipt, 'receipt', { max: 20000 });
    throw new HttpError(501, 'iap_not_configured', 'In-app purchase verification is not configured on this server yet.');
  });

  // "Design it for me": the couple fills a short brief; a designer builds the invitation.
  app.post('/weddings/:weddingId/design-request', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const b = req.body as any;
    const brief = {
      style: str(b?.style, 'style', { max: 200, optional: true }),
      colours: str(b?.colours, 'colours', { max: 200, optional: true }),
      notes: str(b?.notes, 'notes', { max: 2000, optional: true }),
      reference_links: Array.isArray(b?.reference_links) ? b.reference_links.slice(0, 5).map((x: unknown) => str(x, 'reference_links', { max: 500 })) : [],
    };
    const job = await one(`INSERT INTO design_jobs (wedding_id, brief) VALUES ($1,$2) RETURNING id, status`, [a.weddingId, JSON.stringify(brief)]);
    return { job, price_lkr: pricing.designForMeLkr };
  });

  app.get('/weddings/:weddingId/design-request', async (req) => {
    const a = await weddingAccess(req, 'view');
    return { jobs: await q('SELECT id, brief, status, messages, created_at FROM design_jobs WHERE wedding_id=$1 ORDER BY created_at DESC', [a.weddingId]) };
  });

  app.post('/weddings/:weddingId/design-request/:jobId/approve', async (req) => {
    const a = await weddingAccess(req, 'edit_all');
    const r = await pool.query(`UPDATE design_jobs SET status='approved' WHERE id=$1 AND wedding_id=$2 AND status='review'`, [(req.params as any).jobId, a.weddingId]);
    if (!r.rowCount) throw bad('not_ready_for_approval');
    return { ok: true };
  });

  // Development-only stand-in for the gateway's hosted checkout page.
  if (config.env !== 'production') {
    app.get('/payments/dev-checkout/:id', async (req, reply) => {
      const p = await one('SELECT reference, amount_lkr, status FROM payments WHERE id=$1', [(req.params as any).id]);
      if (!p) throw new HttpError(404, 'unknown_payment');
      const body = JSON.stringify({ reference: p.reference, amount_lkr: p.amount_lkr, status: 'paid', transaction_id: 'dev-' + p.reference });
      return reply.type('text/html').send(`<!doctype html><meta name="viewport" content="width=device-width"><body style="font:18px system-ui;max-width:420px;margin:40px auto;padding:0 16px">
        <h1>Test checkout</h1><p>Reference ${escapeHtml(p.reference)} · LKR ${p.amount_lkr}</p><p>Status: ${escapeHtml(p.status)}</p>
        <button id="pay" style="font-size:18px;padding:12px 24px">Pay (test)</button><p id="r"></p>
        <script>document.getElementById('pay').onclick=async()=>{const r=await fetch('/api/payments/webhook',{method:'POST',headers:{'content-type':'application/json','x-signature':${JSON.stringify(signWebhook(body))}},body:${JSON.stringify(body)}});document.getElementById('r').textContent=r.ok?'Paid. You can close this page.':'Failed'}</script>`);
    });
  }
}
