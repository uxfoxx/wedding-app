import { test } from 'node:test';
import assert from 'node:assert/strict';
import { suggestSeating, type SeatGuest } from '../src/lib/seating.ts';
import { readReply } from '../src/lib/rsvpReader.ts';
import { readiness, suggestedChecklist } from '../src/lib/planning.ts';

const G = (id: string, size: number, o: Partial<SeatGuest> = {}): SeatGuest => ({ id, name: id, size, side: null, group: null, vip: false, elder: false, ...o });

test('seating: capacity, parties never split, conflicts apart, groups together, VIPs at the front', () => {
  const tables = [
    { id: 'H', name: 'Head', seats: 6, shape: 'head', sort: 0 },
    { id: 'T1', name: 'Table 1', seats: 8, shape: 'round', sort: 1 },
    { id: 'T2', name: 'Table 2', seats: 8, shape: 'round', sort: 2 },
    { id: 'T3', name: 'Table 3', seats: 8, shape: 'round', sort: 3 },
  ];
  const guests = [
    G('parents', 4, { vip: true, side: 'bride' }),
    G('perera1', 3, { group: 'Perera family', side: 'bride' }),
    G('perera2', 4, { group: 'Perera family', side: 'bride' }),
    G('office1', 2, { group: 'Office', side: 'groom' }),
    G('office2', 2, { group: 'Office', side: 'groom' }),
    G('office3', 3, { group: 'Office', side: 'groom' }),
    G('uncle', 2, { elder: true, side: 'groom' }),
    G('ex1', 1, { side: 'groom' }),
    G('ex2', 1, { side: 'groom' }),
  ];
  const plan = suggestSeating(guests, tables, [['ex1', 'ex2']]);
  assert.deepEqual(plan.unplaced, []);
  assert.equal(plan.assignments.parents, 'H');
  assert.equal(plan.assignments.perera1, plan.assignments.perera2, 'family together');
  assert.equal(plan.assignments.office1, plan.assignments.office2);
  assert.notEqual(plan.assignments.ex1, plan.assignments.ex2, 'conflicts apart');
  const used: Record<string, number> = {};
  for (const g of guests) used[plan.assignments[g.id]] = (used[plan.assignments[g.id]] ?? 0) + g.size;
  for (const t of tables) assert.ok((used[t.id] ?? 0) <= t.seats, `${t.id} over capacity`);
  assert.equal(plan.assignments.uncle, 'T1', 'elders to the front');
});

test('seating: too many people gives a clear warning', () => {
  const plan = suggestSeating([G('a', 5), G('b', 5)], [{ id: 'T', name: 'T', seats: 8, shape: 'round', sort: 0 }], []);
  assert.equal(plan.unplaced.length, 1);
  assert.match(plan.warnings[0], /10 people but only 8 seats/);
});

test('RSVP reader: English, Singlish, Sinhala, Tamil', () => {
  const cases: [string, string | null, number | null, string | null][] = [
    ['Yes! 2 of us will come, vegetarian please', 'coming', 2, 'vegetarian'],
    ['Sorry we cannot come, congratulations!', 'not_coming', 0, null],
    ['Not sure yet, will let you know', 'maybe', null, null],
    ['api 3 denek enawa', 'coming', 3, null],
    ['enna ba sorry', 'not_coming', 0, null],
    ['අපි දෙන්නා එනවා', 'coming', 2, null],
    ['වර முடியாது', null, null, null],
    ['நாங்கள் இருவர் வருவோம், சைவம்', 'coming', 2, 'vegetarian'],
    ['வர முடியாது மன்னிக்கவும்', 'not_coming', 0, null],
    ['Coming with my wife', 'coming', 2, null],
  ];
  for (const [text, status, n, meal] of cases) {
    const r = readReply(text);
    assert.equal(r.status, status, text);
    if (status) assert.equal(r.headcount, n, text);
    assert.equal(r.meal, meal, text);
  }
  assert.equal(readReply('Yes! 2 of us will come, vegetarian please').summary, '2 coming, vegetarian');
});

test('readiness score and next steps', () => {
  const r = readiness({ published: true, guests: 100, expectedGuests: 120, sent: 100, replied: 50, coming: 40, seated: 0, tables: 0, runSheetItems: 0, checklistTotal: 20, checklistDone: 5, daysToGo: 30 });
  assert.ok(r.score > 40 && r.score < 70, String(r.score));
  assert.deepEqual(r.next.map((x) => x.key), ['follow_up', 'seating', 'run_sheet']);
  assert.ok(suggestedChecklist('buddhist').some((t) => /Poruwa/.test(t.title)));
  assert.ok(!suggestedChecklist('christian').some((t) => /Poruwa/.test(t.title)));
});
