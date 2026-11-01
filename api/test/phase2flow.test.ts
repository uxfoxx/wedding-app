// Phase 2 end to end: planner account, team, client wedding, seating + Find your seat,
// guest experience (updates, menu, uploads, wall, guestbook, songs, keepsake), planning tools,
// reports, RSVP reading, Studio coverage, admin.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pool } from '../src/db.ts';
import { config } from '../src/config.ts';
import { migrate } from '../src/migrate.ts';
import { seed } from '../src/seed.ts';
import { buildApp } from '../src/app.ts';
import { runDueJobs } from '../src/lib/jobs.ts';
import type { FastifyInstance } from 'fastify';

let app: FastifyInstance;

async function call(method: string, url: string, token?: string, body?: unknown) {
  const r = await app.inject({ method: method as any, url: '/api' + url, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) }, payload: body !== undefined ? JSON.stringify(body) : undefined });
  return { status: r.statusCode, body: (r.headers['content-type']?.includes('json') ? r.json() : r.body) as any };
}
async function signIn(email: string) {
  const s = await call('POST', '/auth/email/start', undefined, { email });
  return (await call('POST', '/auth/email/verify', undefined, { email, code: s.body.devCode })).body.token as string;
}
async function flushJobs() {
  await pool.query('UPDATE jobs SET run_at = now() WHERE done_at IS NULL');
  await runDueJobs();
}

before(async () => {
  assert.match(config.databaseUrl, /wedding_test/);
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate();
  await seed();
  app = await buildApp();
  config.adminEmails.push('admin2@example.com');
});
after(async () => { await app.close(); await pool.end(); });

test('Phase 2: planners, seating, guest experience, planning tools', async () => {
  const admin = await signIn('admin2@example.com');
  const owner = await signIn('studio@example.com');
  const coord = await signIn('coord@example.com');

  // Planner business, pending approval.
  assert.equal((await call('GET', '/planner', owner)).status, 404);
  const pl = await call('POST', '/planners', owner, { business_name: 'Lotus Events', phone: '0771112222', district: 'Colombo' });
  assert.equal(pl.status, 200);
  const W1 = (await call('POST', '/planner/weddings', owner, { partner1: 'Ravi', partner2: 'Dilini', wedding_type: 'buddhist', client_name: 'Dilini', event: { starts_at: '2027-06-10T04:00:00Z', venue: 'Galle Face Hotel' } })).body;
  assert.equal(W1.wedding.mode, 'advanced', 'planners always get Advanced Mode');
  const W = W1.wedding.id;
  // Free planner: one unpaid active wedding, and unapproved planners are limited to one.
  assert.equal((await call('POST', '/planner/weddings', owner, { partner1: 'A', partner2: 'B' })).status, 403);
  assert.equal((await call('POST', `/admin/planners/${pl.body.planner.id}/approve`, admin)).status, 200);
  assert.equal((await call('POST', '/planner/weddings', owner, { partner1: 'A', partner2: 'B' })).status, 402);

  // Team: free planners can't add members until a wedding is paid.
  assert.equal((await call('POST', '/planner/team/invite', owner)).status, 402);
  await call('POST', `/admin/weddings/${W}/grant-pass`, admin, { reason: 'test' });
  const inv = await call('POST', '/planner/team/invite', owner);
  assert.equal(inv.status, 200);
  assert.equal((await call('POST', `/planner-invites/${inv.body.token}/accept`, coord)).status, 200);
  assert.equal((await call('GET', '/planner/dashboard', coord)).body.weddings.length, 0, 'coordinators only see assigned weddings');
  const coordId = (await call('GET', '/me', coord)).body.user.id;
  await call('POST', `/planner/weddings/${W}/assign`, owner, { user_id: coordId });
  const dash = await call('GET', '/planner/dashboard', coord);
  assert.equal(dash.body.weddings.length, 1);
  assert.ok(dash.body.weddings[0].days_to_go > 0);

  // Studio: covered weddings only while the subscription is paid.
  await call('POST', `/admin/planners/${pl.body.planner.id}/studio`, admin, { plan: 'studio10', months: 1 });
  const W2 = (await call('POST', '/planner/weddings', coord, { partner1: 'Kasun', partner2: 'Nethmi', event: { starts_at: '2027-07-01T04:00:00Z' } })).body;
  assert.equal(W2.plan.coveredBy, 'studio');
  await pool.query(`UPDATE planners SET studio_until = now() - interval '1 day'`);
  assert.equal((await call('GET', `/weddings/${W2.wedding.id}`, coord)).body.plan.plan, 'free', 'lapsed Studio no longer covers the wedding');
  await pool.query(`UPDATE planners SET studio_until = now() + interval '30 days'`);
  assert.ok((await call('GET', '/planner/dashboard', owner)).body.weddings.some((w: any) => w.id === W2.wedding.id), 'owner sees weddings a coordinator created');

  // Guests + RSVPs for seating.
  const evId = W1.events[0].id;
  const rows = [
    { name: 'Amma & Thaththa', seats: 2, vip: true, side: 'bride' },
    { name: 'Perera family', seats: 4, group_name: 'Perera', side: 'bride' },
    { name: 'Sunil Perera', seats: 3, group_name: 'Perera', side: 'bride' },
    { name: 'Office team', seats: 5, group_name: 'Office', side: 'groom' },
    { name: 'Kamal', seats: 1, side: 'groom' },
    { name: 'Nimal', seats: 1, side: 'groom' },
  ];
  await call('POST', `/weddings/${W}/guests/import`, owner, { rows });
  await call('PATCH', `/weddings/${W}`, owner, { template_id: 'poruwa-royal' });
  await call('POST', `/weddings/${W}/publish`, owner);
  const guests = (await call('GET', `/weddings/${W}/guests`, owner)).body.guests;
  const id = (n: string) => guests.find((g: any) => g.name === n).id;

  // RSVP reading: a pasted WhatsApp reply becomes a suggestion; the couple confirms it.
  const rr = await call('POST', `/weddings/${W}/read-reply`, owner, { text: 'api 3 denek enawa, elawalu' });
  assert.deepEqual([rr.body.status, rr.body.headcount, rr.body.meal], ['coming', 3, 'vegetarian']);
  assert.equal((await call('PUT', `/weddings/${W}/guests/${id('Sunil Perera')}/rsvp`, owner, { status: 'coming', headcount: 3, meal: 'vegetarian' })).status, 200);
  await call('PUT', `/weddings/${W}/guests/${id('Office team')}/rsvp`, owner, { status: 'coming', headcount: 4 });

  // Seating.
  await call('POST', `/weddings/${W}/events/${evId}/tables`, owner, { shape: 'head', seats: 4 });
  await call('POST', `/weddings/${W}/events/${evId}/tables`, owner, { count: 2, seats: 8 });
  await call('POST', `/weddings/${W}/conflicts`, owner, { a: id('Kamal'), b: id('Nimal') });
  const sug = await call('POST', `/weddings/${W}/events/${evId}/seating/suggest`, owner, {});
  assert.equal(sug.body.unplaced, 0, JSON.stringify(sug.body));
  const seating = (await call('GET', `/weddings/${W}/events/${evId}/seating`, owner)).body;
  const tableOf = (n: string) => seating.guests.find((g: any) => g.name === n).table_id;
  assert.equal(tableOf('Perera family'), tableOf('Sunil Perera'));
  assert.notEqual(tableOf('Kamal'), tableOf('Nimal'));
  assert.equal(seating.tables.find((t: any) => t.id === tableOf('Amma & Thaththa')).shape, 'head');
  assert.equal(seating.guests.find((g: any) => g.name === 'Office team').size, 4, 'confirmed headcount is used, not invited seats');
  // Capacity is enforced on manual moves.
  const head = seating.tables.find((t: any) => t.shape === 'head').id;
  assert.equal((await call('PUT', `/weddings/${W}/events/${evId}/seats/${id('Office team')}`, owner, { table_id: head })).status, 409);

  // Find your seat: only once the couple publishes seating.
  const slug = W1.wedding.slug;
  assert.equal((await call('POST', '/public/find-seat', undefined, { slug, name: 'sunil' })).status, 404);
  await call('POST', `/weddings/${W}/seating/publish`, owner, { published: true });
  await flushJobs();
  const fs = await call('POST', '/public/find-seat', undefined, { slug, name: 'sunil' });
  assert.equal(fs.body.matches[0].name, 'Sunil Perera');
  assert.match(fs.body.matches[0].table, /Table/);
  const tok = (await pool.query('SELECT token FROM guests WHERE id=$1', [id('Sunil Perera')])).rows[0].token;
  const gj = JSON.parse(await readFile(join(config.storageDir, 'site', slug, 'g', `${tok}.json`), 'utf8'));
  assert.match(gj.tables[evId], /Table/, 'guest page shows the table');
  for (const page of ['seat', 'share', 'wall', 'keepsake']) await readFile(join(config.storageDir, 'site', slug, `${page}.html`), 'utf8');

  // Live update + menu appear on the guest page; WhatsApp queue goes to confirmed guests.
  await call('POST', `/weddings/${W}/updates`, owner, { body: 'Parking is at the back entrance', kind: 'parking' });
  await call('PUT', `/weddings/${W}/menu`, owner, { items: [{ course: 'Mains', name: 'Yellow rice', diet: ['vegetarian'], allergens: ['cashew'] }] });
  await flushJobs();
  const html = await readFile(join(config.storageDir, 'site', slug, 'index.html'), 'utf8');
  assert.match(html, /Parking is at the back entrance/);
  assert.match(html, /Yellow rice/);
  const uq = await call('GET', `/weddings/${W}/send-queue?kind=update`, owner);
  assert.deepEqual(uq.body.guests.map((g: any) => g.name).sort(), ['Office team', 'Sunil Perera']);
  assert.match(uq.body.guests[0].text, /Parking is at the back entrance/);

  // Guest photo: ask → PUT bytes → complete → pending → couple approves → wall + keepsake.
  const png = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000', 'hex');
  const up = await call('POST', '/public/uploads', undefined, { slug, content_type: 'image/png', size: png.length, name: 'Sunil' });
  assert.equal(up.status, 200);
  assert.equal((await call('POST', `/public/uploads/${up.body.id}/complete`, undefined, { upload_token: up.body.upload_token })).status, 400, 'not uploaded yet');
  const put = await app.inject({ method: 'PUT', url: new URL(up.body.upload_url).pathname, headers: { 'content-type': 'image/png' }, payload: png });
  assert.equal(put.statusCode, 200);
  assert.equal((await call('POST', `/public/uploads/${up.body.id}/complete`, undefined, { upload_token: up.body.upload_token })).body.status, 'pending');
  assert.equal((await call('GET', `/public/wall?slug=${slug}`)).body.items.length, 0, 'not on the wall until approved');
  await call('POST', `/weddings/${W}/uploads/moderate`, owner, { ids: [up.body.id], status: 'approved' });
  const wall = await call('GET', `/public/wall?slug=${slug}`);
  assert.equal(wall.body.items.length, 1);
  const media = await app.inject({ method: 'GET', url: new URL(wall.body.items[0].url).pathname });
  assert.equal(media.statusCode, 200);
  assert.equal((await call('POST', '/public/uploads', undefined, { slug, content_type: 'text/html', size: 10 })).status, 400, 'only photos/videos/voice');
  assert.equal((await call('POST', '/public/uploads', undefined, { slug, content_type: 'image/jpeg', size: 50 * 1024 * 1024 })).status, 400, 'size limit');

  // Guestbook + report + songs + keepsake.
  const gb = await call('POST', '/public/guestbook', undefined, { slug, name: 'Sunil', message: 'Congratulations!' });
  assert.equal(gb.status, 200);
  await call('POST', '/public/songs', undefined, { slug, name: 'Sunil', song: 'Sanda Kumari' });
  let keep = await call('GET', `/public/keepsake?slug=${slug}`);
  assert.equal(keep.body.guestbook[0].message, 'Congratulations!');
  assert.equal(keep.body.photos.length, 1);
  await call('POST', '/public/report', undefined, { slug, kind: 'upload', id: up.body.id });
  keep = await call('GET', `/public/keepsake?slug=${slug}`);
  assert.equal(keep.body.photos.length, 0, 'a reported photo comes down until reviewed');
  assert.equal((await call('GET', '/admin/reports', admin)).body.uploads.length, 1);
  await call('POST', '/admin/reports/resolve', admin, { kind: 'upload', id: up.body.id, action: 'restore' });
  assert.equal((await call('GET', `/public/keepsake?slug=${slug}`)).body.photos.length, 1);
  assert.equal((await call('GET', `/weddings/${W}/songs`, owner)).body.songs[0].song, 'Sanda Kumari');

  // Free weddings don't get uploads.
  const couple = await signIn('freecouple@example.com');
  const fw = (await call('POST', '/weddings', couple, { partner1: 'X', partner2: 'Y', event: { starts_at: '2027-09-01T04:00:00Z' } })).body;
  await call('PATCH', `/weddings/${fw.wedding.id}`, couple, { template_id: 'simple-ivory' });
  await call('POST', `/weddings/${fw.wedding.id}/publish`, couple);
  assert.equal((await call('POST', '/public/uploads', undefined, { slug: fw.wedding.slug, content_type: 'image/png', size: 10 })).status, 404);
  assert.equal((await call('POST', `/weddings/${fw.wedding.id}/budget`, couple, { category: 'Venue', name: 'Hall' })).status, 402);

  // Planning tools: checklist, budget, run sheet, readiness, reports.
  const cl = await call('POST', `/weddings/${W}/checklist/suggest`, owner);
  assert.ok(cl.body.added > 15);
  const tasks = (await call('GET', `/weddings/${W}/tasks?kind=checklist`, owner)).body.tasks;
  assert.ok(tasks.some((t: any) => /Jayamangala/.test(t.title)));
  await call('PATCH', `/weddings/${W}/tasks/${tasks[0].id}`, owner, { done: true });
  const task = await call('POST', `/weddings/${W}/tasks`, owner, { title: 'Confirm florist', due_date: '2027-05-01', assignee_id: coordId });
  assert.equal(task.status, 200);
  assert.ok((await call('GET', '/planner/tasks?mine=true', coord)).body.tasks.some((t: any) => t.title === 'Confirm florist'));
  await call('POST', `/weddings/${W}/budget`, owner, { category: 'Venue', name: 'Galle Face Hotel', estimated_lkr: 1500000, total_lkr: 1650000, paid_lkr: 500000, due_date: new Date(Date.now() + 5 * 86400000).toISOString().slice(0, 10) });
  await call('POST', `/weddings/${W}/budget`, owner, { category: 'Photography', name: 'Photographer', estimated_lkr: 300000 });
  const bud = (await call('GET', `/weddings/${W}/budget`, owner)).body;
  assert.deepEqual([bud.totals.estimated, bud.totals.cost, bud.totals.paid, bud.totals.due], [1800000, 1950000, 500000, 1450000]);
  assert.equal(bud.reminders.length, 1);
  await call('POST', `/weddings/${W}/run-sheet`, owner, { event_id: evId, time: '10:24', item: 'Poruwa ceremony (nekath)', owner: 'Kapuwa' });
  const ready = (await call('GET', `/weddings/${W}/readiness`, owner)).body;
  assert.ok(ready.score > 20 && ready.score < 100, String(ready.score));
  assert.equal(ready.next.length, 3);
  for (const kind of ['guests', 'seating', 'run_sheet', 'qr_board']) {
    const link = await call('POST', `/weddings/${W}/report-link`, owner, { kind });
    const u = new URL(link.body.url);
    const rep = await app.inject({ method: 'GET', url: u.pathname + u.search });
    assert.equal(rep.statusCode, 200, kind);
    assert.match(rep.body, /Lotus Events/);
  }

  // Templates: save the checklist from this wedding and apply it to another.
  const tpl = await call('POST', '/planner/templates', owner, { kind: 'checklist', name: 'Buddhist standard', from_wedding_id: W });
  assert.ok(tpl.body.template.items.length > 15);
  assert.equal((await call('POST', `/weddings/${W2.wedding.id}/apply-template/${tpl.body.template.id}`, owner)).status, 200);

  // Hand ownership to the couple; the planner keeps edit access.
  const theCouple = await signIn('dilini@example.com');
  const ci = await call('POST', `/weddings/${W}/members/invite`, owner, { role: 'edit_all' });
  await call('POST', `/invites/${ci.body.token}/accept`, theCouple);
  const cid = (await call('GET', '/me', theCouple)).body.user.id;
  assert.equal((await call('POST', `/weddings/${W}/transfer-ownership`, owner, { user_id: cid })).status, 200);
  assert.equal((await call('GET', `/weddings/${W}`, theCouple)).body.role, 'owner');
  assert.equal((await call('GET', `/weddings/${W}`, owner)).body.role, 'edit_all');

  // Thank-you queue after the wedding links to the keepsake page.
  const ty = await call('GET', `/weddings/${W}/send-queue?kind=thanks`, theCouple);
  assert.match(ty.body.guests[0].text, /keepsake\.html/);

  const stats = await call('GET', '/admin/stats', admin);
  assert.equal(stats.body.phase2Gate.planners2plus.now, 1);
});
