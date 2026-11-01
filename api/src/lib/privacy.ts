// Sri Lanka PDPA (No. 9 of 2022): delete guests' contact details 12 months after the
// wedding. Names, RSVPs, album and guestbook stay as the couple's keepsake.
import { q } from '../db.ts';
import { pricing } from '../config.ts';

export async function purgeExpiredContacts(): Promise<number> {
  const rows = await q<{ id: string }>(
    `UPDATE weddings w SET contacts_purged_at = now()
     WHERE contacts_purged_at IS NULL
       AND (SELECT max(coalesce(ends_at, starts_at)) FROM events e WHERE e.wedding_id = w.id)
           < now() - make_interval(months => $1)
     RETURNING id`, [pricing.purgeContactsMonthsAfterLastEvent]);
  for (const r of rows) {
    await q('UPDATE guests SET phone = NULL, notes = NULL WHERE wedding_id=$1', [r.id]);
  }
  return rows.length;
}
