// Smart guest import: turns a pasted WhatsApp message or list into guest rows using
// pattern rules only (no AI). Rows the rules can't read confidently are flagged.
//   "Uncle Sam – 2 people, veg / Nimal & wife / Dr. Perera 0771234567"

import { normalizePhone, PHONE_RE } from './phone.ts';

export interface ParsedGuest {
  name: string;
  title: string | null;
  phone: string | null;
  seats: number;
  dietary: string | null;
  flags: string[];          // reasons the couple should check this row
  raw: string;
}

const TITLES = [
  // English
  'mr', 'mrs', 'ms', 'miss', 'dr', 'prof', 'rev', 'ven', 'fr', 'sr', 'hon', 'eng', 'capt', 'col',
  // Family titles commonly used in Sri Lankan English / Singlish / Tanglish
  'uncle', 'aunty', 'auntie', 'aunt', 'mama', 'nanda', 'loku amma', 'punchi amma', 'loku thaththa',
  'bappa', 'achchi', 'seeya', 'aiya', 'akka', 'malli', 'nangi', 'anna', 'thambi', 'thangachi',
  'periyappa', 'periyamma', 'chithappa', 'chithi', 'maama', 'maami', 'athai',
];

// Companion phrases and how many extra people they add. null = "family", size unknown.
const COMPANIONS: [RegExp, number | null][] = [
  [/\s*(?:&|and|\+|with|saha)\s*(?:wife|husband|spouse|partner|hubby|mrs\.?|nona|mahaththaya|manaivi|kanavar)\b/i, 1],
  [/\s*(?:&|and|\+|with|saha)\s*(?:family|fam|kids|children|pawule|pawula|kudumbam)\b/i, null],
  [/\s*\bfamily\b/i, null],
  [/\s*\+\s*1\b/i, 1],
];

const COUNT_RES: RegExp[] = [
  /(\d{1,2})\s*(?:people|persons?|pax|ppl|guests?|members?|denek|dena|per|peyar)\b/i,
  /\bx\s*(\d{1,2})\b/i,
  /\((\d{1,2})\)/,
  /\b(\d{1,2})\s*(?:adults?)\b/i,
];

const DIETARY: [RegExp, string][] = [
  [/\b(?:vegan)\b/i, 'vegan'],
  [/\b(?:veg|vegetarian|vegi|veggie|elawalu|elavalu|pure\s*veg|saivam|saiva)\b/i, 'vegetarian'],
  [/\b(?:halal)\b/i, 'halal'],
  [/\b(?:no\s*beef|beef\s*free)\b/i, 'no beef'],
  [/\b(?:no\s*pork)\b/i, 'no pork'],
  [/\b(?:diabetic|sugar\s*free)\b/i, 'diabetic'],
  [/\b(?:nut\s*allergy|no\s*nuts)\b/i, 'nut allergy'],
];

/** Split a pasted block into one candidate per guest. */
export function splitEntries(text: string): string[] {
  return text
    .split(/\r?\n|;|\s\/\s|\s\|\s/)
    .map((s) => s.replace(/^\s*(?:\d{1,3}[.)]\s+|[-*•·]\s*)/, '').trim()) // list bullets / "1. "
    .filter((s) => s.length > 0);
}

export function parseEntry(raw: string): ParsedGuest | null {
  const flags: string[] = [];
  let s = raw;

  // Phone numbers (take the first usable one).
  let phone: string | null = null;
  const phones = s.match(PHONE_RE) ?? [];
  for (const p of phones) {
    const n = normalizePhone(p);
    if (n && !phone) phone = n;
    s = s.replace(p, ' ');
  }
  if (phones.length && !phone) flags.push('phone_unreadable');
  if (phones.length > 1) flags.push('several_phones');

  // Dietary words.
  const diets: string[] = [];
  for (const [re, label] of DIETARY) {
    if (re.test(s)) {
      if (!diets.includes(label)) diets.push(label);
      s = s.replace(new RegExp(re.source, 'gi'), ' ');
    }
  }
  if (diets.includes('vegan') && diets.includes('vegetarian')) diets.splice(diets.indexOf('vegetarian'), 1);

  // Explicit counts.
  let count: number | null = null;
  for (const re of COUNT_RES) {
    const m = s.match(re);
    if (m) {
      count = Number(m[1]);
      s = s.replace(m[0], ' ');
      break;
    }
  }

  // Companions.
  let companions = 0;
  let familyUnknown = false;
  for (const [re, add] of COMPANIONS) {
    if (re.test(s)) {
      if (add === null) familyUnknown = true;
      else companions += add;
      // Keep "& family"/"& wife" in the display name; they read naturally on the invitation.
    }
  }

  // Title.
  let title: string | null = null;
  const lower = s.trim().toLowerCase();
  for (const t of TITLES.sort((a, b) => b.length - a.length)) {
    const re = new RegExp(`^${t.replace(/ /g, '\\s+')}\\.?\\s+`, 'i');
    if (re.test(lower)) {
      const m = s.trim().match(re)!;
      title = m[0].trim().replace(/\.$/, '');
      title = title.charAt(0).toUpperCase() + title.slice(1);
      s = s.trim().slice(m[0].length);
      break;
    }
  }

  // Clean name: drop separators and leftover punctuation.
  let name = s
    .replace(/[–—-]\s*$/g, '')
    .replace(/\s+[–—-]\s+/g, ' ')
    .replace(/[,:]+/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .replace(/^[\s.&-]+|[\s.&-]+$/g, '')
    .trim();

  if (!name && title) {
    name = title;
    title = null;
  }
  if (!name) {
    if (!phone) return null;
    flags.push('no_name');
    name = phone;
  }
  if (/\d/.test(name)) flags.push('digits_in_name');
  if (name.length > 60) flags.push('too_long');

  let seats = count ?? 1 + companions;
  if (count === null && familyUnknown) {
    flags.push('family_size_unknown');
    seats = Math.max(seats, 2);
  }
  if (count !== null && companions > 0 && count < 1 + companions) flags.push('count_mismatch');
  if (seats < 1) seats = 1;
  if (seats > 30) {
    seats = 30;
    flags.push('count_too_high');
  }

  return { name, title, phone, seats, dietary: diets.length ? diets.join(', ') : null, flags, raw: raw.trim() };
}

export function parsePastedGuests(text: string): ParsedGuest[] {
  return splitEntries(text).map(parseEntry).filter((g): g is ParsedGuest => g !== null);
}

/** Minimal CSV parser (quoted fields, commas, CRLF). */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;
  text = text.replace(/^﻿/, '');
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',' || ch === '\t') { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.some((c) => c.trim())) rows.push(row);
      row = [];
    } else field += ch;
  }
  row.push(field);
  if (row.some((c) => c.trim())) rows.push(row);
  return rows;
}

const HEADER_MAP: Record<string, keyof ParsedGuest | 'side' | 'group' | 'notes'> = {
  name: 'name', 'full name': 'name', guest: 'name', 'guest name': 'name',
  title: 'title',
  phone: 'phone', mobile: 'phone', 'phone number': 'phone', whatsapp: 'phone', number: 'phone', tel: 'phone',
  seats: 'seats', count: 'seats', people: 'seats', pax: 'seats', guests: 'seats',
  dietary: 'dietary', diet: 'dietary', meal: 'dietary',
  side: 'side', group: 'group', notes: 'notes', note: 'notes',
};

export interface CsvGuest extends ParsedGuest { side?: string | null; group?: string | null; notes?: string | null }

/** CSV/Excel-export import. Uses headers when present, otherwise parses each line as free text. */
export function parseGuestCsv(text: string): CsvGuest[] {
  const rows = parseCsv(text);
  if (!rows.length) return [];
  const header = rows[0].map((h) => HEADER_MAP[h.trim().toLowerCase()]);
  if (!header.includes('name')) {
    return rows.map((r) => parseEntry(r.join(' '))).filter((g): g is ParsedGuest => !!g);
  }
  const out: CsvGuest[] = [];
  for (const r of rows.slice(1)) {
    const rec: Record<string, string> = {};
    header.forEach((k, i) => { if (k && r[i] != null) rec[k] = r[i].trim(); });
    if (!rec.name) continue;
    const flags: string[] = [];
    const phone = rec.phone ? normalizePhone(rec.phone) : null;
    if (rec.phone && !phone) flags.push('phone_unreadable');
    const seats = rec.seats ? Math.min(30, Math.max(1, parseInt(rec.seats, 10) || 1)) : 1;
    const side = (rec.side ?? '').toLowerCase();
    out.push({
      name: rec.name, title: rec.title || null, phone, seats, dietary: rec.dietary || null, flags,
      raw: r.join(','),
      side: side.startsWith('b') && side.includes('ride') ? 'bride' : side.startsWith('g') ? 'groom' : side ? 'both' : null,
      group: rec.group || null, notes: rec.notes || null,
    });
  }
  return out;
}
