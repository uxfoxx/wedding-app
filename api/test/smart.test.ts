import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizePhone } from '../src/lib/phone.ts';
import { parsePastedGuests, parseGuestCsv } from '../src/lib/guestImport.ts';
import { findDuplicates, matchGuestName, similarNames } from '../src/lib/duplicates.ts';

test('phone numbers: Sri Lankan and diaspora forms', () => {
  assert.equal(normalizePhone('077 123 4567'), '+94771234567');
  assert.equal(normalizePhone('0771234567'), '+94771234567');
  assert.equal(normalizePhone('771234567'), '+94771234567');
  assert.equal(normalizePhone('+94 77 123 4567'), '+94771234567');
  assert.equal(normalizePhone('94771234567'), '+94771234567');
  assert.equal(normalizePhone('+94 077 123 4567'), '+94771234567');
  assert.equal(normalizePhone('+61 412 345 678'), '+61412345678');
  assert.equal(normalizePhone('0044 7700 900123'), '+447700900123');
  assert.equal(normalizePhone('12345'), null);
  assert.equal(normalizePhone(''), null);
});

test('smart import: the feature document example', () => {
  const rows = parsePastedGuests('Uncle Sam – 2 people, veg / Nimal & wife / Dr. Perera 0771234567');
  assert.equal(rows.length, 3);
  assert.deepEqual([rows[0].title, rows[0].name, rows[0].seats, rows[0].dietary], ['Uncle', 'Sam', 2, 'vegetarian']);
  assert.deepEqual([rows[1].name, rows[1].seats], ['Nimal & wife', 2]);
  assert.deepEqual([rows[2].title, rows[2].name, rows[2].phone, rows[2].seats], ['Dr', 'Perera', '+94771234567', 1]);
  assert.deepEqual(rows.map((r) => r.flags), [[], [], []]);
});

test('smart import: WhatsApp list with bullets, Singlish and family', () => {
  const rows = parsePastedGuests(`1. Kamal aiya + family 0712345678
2. Nadeesha akka - 3 denek, elawalu
- Ravi & Priya halal
* 0777654321`);
  assert.equal(rows.length, 4);
  assert.equal(rows[0].name, 'Kamal aiya + family');
  assert.ok(rows[0].flags.includes('family_size_unknown'));
  assert.equal(rows[0].phone, '+94712345678');
  assert.deepEqual([rows[1].name, rows[1].seats, rows[1].dietary], ['Nadeesha akka', 3, 'vegetarian']);
  assert.equal(rows[2].dietary, 'halal');
  assert.ok(rows[3].flags.includes('no_name'));
});

test('csv import with headers', () => {
  const rows = parseGuestCsv('Name,Phone,Seats,Side\n"Perera, Sunil",0771112223,3,Bride\nAmali,,1,groom\n');
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].name, rows[0].phone, rows[0].seats, rows[0].side], ['Perera, Sunil', '+94771112223', 3, 'bride']);
  assert.equal(rows[1].side, 'groom');
});

test('duplicates: same phone or near-identical name', () => {
  const pairs = findDuplicates([
    { id: '1', name: 'Mr. Sunil Perera', phone: '+94771234567' },
    { id: '2', name: 'Sunil Pereira', phone: null },
    { id: '3', name: 'Kamala', phone: '+94771234567' },
    { id: '4', name: 'Ravi', phone: null },
    { id: '5', name: 'Ravu', phone: null },
  ]);
  assert.ok(pairs.some((p) => p.a === '1' && p.b === '3' && p.reason === 'same_phone'));
  assert.ok(pairs.some((p) => p.a === '1' && p.b === '2' && p.reason === 'similar_name'));
  assert.ok(!pairs.some((p) => p.a === '4' && p.b === '5'), 'short names are not guessed');
  assert.ok(similarNames('Nimal Fernando', 'Nimal Fernado'));
  assert.ok(!similarNames('Nimal Fernando', 'Kamal Fernando Silva'));
});

test('open link name matching refuses to guess between two similar guests', () => {
  const list = [{ name: 'Nimal Perera' }, { name: 'Nimal Pereira' }, { name: 'Amara Silva' }];
  assert.equal(matchGuestName('amara silva', list)?.name, 'Amara Silva');
  assert.equal(matchGuestName('Nimal Perera', list)?.name, 'Nimal Perera');
  assert.equal(matchGuestName('Nimal Perer', list), null);
  assert.equal(matchGuestName('Al', list), null);
});
