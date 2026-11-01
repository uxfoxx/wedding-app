// A vendor's public profile as a static page on the CDN, for sharing on social media.
import { config } from '../config.ts';
import { one, q } from '../db.ts';
import { mediaUrl, storage } from './storage.ts';
import { escapeHtml } from './util.ts';

const lkr = (n: number) => 'LKR ' + Math.round(n).toLocaleString('en-LK');

export async function publishVendorPage(vendorId: string) {
  const v = await one(`SELECT v.*, c.name AS category_name, (v.verified_until > now()) AS verified_badge,
      (SELECT round(avg(rating)::numeric,1) FROM reviews r WHERE r.vendor_id=v.id AND r.status='visible') AS rating,
      (SELECT count(*)::int FROM reviews r WHERE r.vendor_id=v.id AND r.status='visible') AS reviews
    FROM vendors v JOIN vendor_categories c ON c.id=v.category WHERE v.id=$1`, [vendorId]);
  if (!v) return;
  const path = `site/vendors/${v.slug}.html`;
  if (v.status !== 'approved') { await storage.del(path); return; }
  const media = await q('SELECT kind, path, caption FROM vendor_media WHERE vendor_id=$1 AND ready ORDER BY sort, created_at LIMIT 24', [vendorId]);
  const packs = await q('SELECT name, includes, starting_lkr, negotiable FROM vendor_packages WHERE vendor_id=$1 ORDER BY sort, starting_lkr', [vendorId]);
  const revs = await q(`SELECT rating, body, reply FROM reviews WHERE vendor_id=$1 AND status='visible' ORDER BY created_at DESC LIMIT 10`, [vendorId]);
  const cover = media.find((m) => m.kind === 'photo');
  const wa = v.whatsapp ?? v.phone;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(v.business_name)} · ${escapeHtml(v.category_name)}</title>
<meta name="description" content="${escapeHtml(`${v.category_name} in ${v.district}${v.description ? ' · ' + v.description.slice(0, 140) : ''}`)}">
<meta property="og:title" content="${escapeHtml(v.business_name)}"><meta property="og:description" content="${escapeHtml(`${v.category_name} · ${v.district}`)}">
${cover ? `<meta property="og:image" content="${escapeHtml(mediaUrl(cover.path))}">` : ''}
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&family=Noto+Sans+Sinhala&family=Noto+Sans+Tamil&display=swap">
<style>*{box-sizing:border-box}body{margin:0;background:#fbf6ec;color:#2b1d12;font:1rem/1.6 Inter,'Noto Sans Sinhala','Noto Sans Tamil',system-ui,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}h1{margin:.2em 0;font-size:2rem}.muted{color:#6f6553}.card{background:#fff;border-radius:14px;padding:16px;margin:14px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px}.grid img,.grid video{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px}
.badge{display:inline-block;padding:2px 10px;border-radius:12px;background:#a8742a;color:#fff;font-size:.85rem;margin-right:6px}
.btn{display:inline-block;min-height:48px;padding:12px 20px;border-radius:24px;background:#1f8f4e;color:#fff;text-decoration:none;font-weight:600;margin:6px 6px 0 0}.btn.alt{background:#a8742a}</style></head>
<body><main><div class="muted">${escapeHtml(v.category_name)} · ${escapeHtml(v.district)}</div><h1>${escapeHtml(v.business_name)}</h1>
<div>${v.verified_badge ? '<span class="badge">Verified</span>' : ''}${v.rating ? `★ ${v.rating} (${v.reviews} reviews)` : ''}</div>
${v.description ? `<p>${escapeHtml(v.description)}</p>` : ''}
<div>${wa ? `<a class="btn" href="https://wa.me/${escapeHtml(String(wa).replace('+', ''))}">WhatsApp</a>` : ''}<a class="btn alt" href="${escapeHtml(config.webPanelUrl)}/#vendor=${escapeHtml(v.slug)}">Enquire with your wedding details</a></div>
<div class="grid" style="margin-top:16px">${media.map((m) => m.kind === 'video' ? `<video src="${escapeHtml(mediaUrl(m.path))}" controls preload="none"></video>` : `<img src="${escapeHtml(mediaUrl(m.path))}" alt="${escapeHtml(m.caption ?? '')}" loading="lazy">`).join('')}</div>
${packs.length ? `<h2>Packages</h2>${packs.map((p) => `<div class="card"><b>${escapeHtml(p.name)}</b> · from ${lkr(Number(p.starting_lkr))}${p.negotiable ? ' (negotiable)' : ''}${p.includes ? `<p>${escapeHtml(p.includes)}</p>` : ''}</div>`).join('')}` : ''}
${revs.length ? `<h2>Reviews from couples</h2>${revs.map((r) => `<div class="card">${'★'.repeat(r.rating)}${r.body ? `<p>${escapeHtml(r.body)}</p>` : ''}${r.reply ? `<p class="muted"><b>Reply:</b> ${escapeHtml(r.reply)}</p>` : ''}</div>`).join('')}` : ''}
<p class="muted">Reviews come only from couples who planned their wedding in the app and contacted this vendor.</p></main></body></html>`;
  await storage.put(path, html, 'text/html; charset=utf-8', 'public, max-age=300');
}
