// Database-backed job queue: no Redis needed on a 1 GB server.
// Jobs with the same key collapse while pending (e.g. many guest edits → one republish).
import { pool, q } from '../db.ts';
import { publishWedding } from './publisher.ts';
import { purgeExpiredContacts } from './privacy.ts';

type Handler = (payload: any) => Promise<void>;

export const handlers: Record<string, Handler> = {
  publish: async (p) => { await publishWedding(p.weddingId); },
  purge_contacts: async () => { await purgeExpiredContacts(); },
};

export async function enqueue(type: string, payload: Record<string, unknown> = {}, opts: { key?: string; delayMs?: number } = {}) {
  await pool.query(
    `INSERT INTO jobs (type, key, payload, run_at) VALUES ($1, $2, $3, now() + ($4 || ' milliseconds')::interval)
     ON CONFLICT (key) WHERE done_at IS NULL DO NOTHING`,
    [type, opts.key ?? null, JSON.stringify(payload), String(opts.delayMs ?? 0)],
  );
}

export function enqueuePublish(weddingId: string) {
  return enqueue('publish', { weddingId }, { key: `publish:${weddingId}`, delayMs: 2000 });
}

/** Runs due jobs one at a time. Returns how many ran. */
export async function runDueJobs(limit = 20): Promise<number> {
  let ran = 0;
  for (; ran < limit; ran++) {
    const [job] = await q(
      `UPDATE jobs SET locked_at = now(), attempts = attempts + 1
       WHERE id = (SELECT id FROM jobs WHERE done_at IS NULL AND run_at <= now()
                   AND (locked_at IS NULL OR locked_at < now() - interval '5 minutes') AND attempts < 5
                   ORDER BY run_at LIMIT 1 FOR UPDATE SKIP LOCKED)
       RETURNING *`);
    if (!job) break;
    try {
      const h = handlers[job.type];
      if (!h) throw new Error(`no handler for ${job.type}`);
      await h(job.payload);
      await pool.query('UPDATE jobs SET done_at = now(), error = NULL WHERE id=$1', [job.id]);
    } catch (e: any) {
      // Back off and retry; give up after 5 attempts (visible in admin).
      await pool.query(`UPDATE jobs SET locked_at = NULL, error = $2, run_at = now() + (attempts * interval '30 seconds') WHERE id=$1`, [job.id, String(e?.stack ?? e)]);
    }
  }
  return ran;
}

let timer: NodeJS.Timeout | null = null;
export function startWorker(intervalMs = 1000) {
  let busy = false;
  timer = setInterval(async () => {
    if (busy) return;
    busy = true;
    try { await runDueJobs(); } catch (e) { console.error('job worker', e); } finally { busy = false; }
  }, intervalMs);
  // Daily privacy purge.
  enqueue('purge_contacts', {}, { key: 'purge_contacts:' + new Date().toISOString().slice(0, 10) }).catch(() => {});
}
export function stopWorker() { if (timer) clearInterval(timer); }
