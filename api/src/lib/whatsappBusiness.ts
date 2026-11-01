// Optional WhatsApp Business Platform (Meta Cloud API). Off by default: Meta charges per
// conversation, so it is switched on only once revenue covers the cost. When on, it sends
// approved template messages: automatic reminders to guests who haven't replied.
// Until then, all sending stays on the couple's own phone (free).
import { config } from '../config.ts';
import { q, pool } from '../db.ts';
import { guestLink } from './publisher.ts';
import { waDigits } from './phone.ts';

export const waBusiness = {
  enabled: process.env.WHATSAPP_BUSINESS_ENABLED === 'true',
  token: process.env.WHATSAPP_TOKEN ?? '',
  phoneNumberId: process.env.WHATSAPP_PHONE_NUMBER_ID ?? '',
  reminderTemplate: process.env.WHATSAPP_REMINDER_TEMPLATE ?? 'rsvp_reminder',   // must be approved by Meta
  maxPerWeddingPerDay: Number(process.env.WHATSAPP_MAX_PER_WEDDING_PER_DAY ?? 200),
};

export function waBusinessReady() {
  return waBusiness.enabled && !!waBusiness.token && !!waBusiness.phoneNumberId;
}

/** Sends one approved template message. Returns the Meta message id. */
export async function sendTemplate(toE164: string, lang: string, params: string[]): Promise<string> {
  const r = await fetch(`https://graph.facebook.com/v21.0/${waBusiness.phoneNumberId}/messages`, {
    method: 'POST',
    headers: { authorization: `Bearer ${waBusiness.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      messaging_product: 'whatsapp', to: waDigits(toE164), type: 'template',
      template: { name: waBusiness.reminderTemplate, language: { code: lang === 'si' ? 'si' : lang === 'ta' ? 'ta' : 'en' }, components: [{ type: 'body', parameters: params.map((text) => ({ type: 'text', text })) }] },
    }),
  });
  const j: any = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`WhatsApp API ${r.status}: ${JSON.stringify(j.error ?? j)}`);
  return j.messages?.[0]?.id ?? '';
}

/**
 * Daily job: remind guests with no reply 7+ days after their invitation, once, for weddings that
 * turned automatic reminders on (settings.auto_reminders) and have the Wedding Pass.
 */
export async function sendAutoReminders(): Promise<number> {
  if (!waBusinessReady()) return 0;
  const rows = await q(`SELECT g.id, g.name, g.phone, g.token, w.slug, w.language, w.partner1, w.partner2 FROM guests g JOIN weddings w ON w.id=g.wedding_id
    WHERE w.plan='pass' AND (w.settings->>'auto_reminders')::boolean IS TRUE AND g.phone IS NOT NULL AND g.sent_at < now() - interval '7 days'
      AND NOT EXISTS (SELECT 1 FROM rsvps r WHERE r.guest_id=g.id) AND NOT ('auto_reminded' = ANY(g.tags))
      AND EXISTS (SELECT 1 FROM events e WHERE e.wedding_id=w.id AND e.starts_at > now())
    ORDER BY w.id LIMIT 1000`);
  let sent = 0;
  const perWedding = new Map<string, number>();
  for (const g of rows) {
    const n = perWedding.get(g.slug) ?? 0;
    if (n >= waBusiness.maxPerWeddingPerDay) continue;
    try {
      await sendTemplate(g.phone, g.language, [g.name, `${g.partner1} & ${g.partner2}`, guestLink(g.slug, g.token)]);
      await pool.query(`UPDATE guests SET tags = array_append(tags, 'auto_reminded') WHERE id=$1`, [g.id]);
      perWedding.set(g.slug, n + 1);
      sent++;
    } catch (e) {
      console.error('auto reminder failed', g.id, e);
    }
  }
  return sent;
}

export const _config = config; // keep the import for future per-environment settings
