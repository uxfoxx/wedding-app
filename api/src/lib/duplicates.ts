// Duplicate guest detection: same phone number, or names that differ by a letter or two.

export interface DupCandidate { id: string; name: string; phone: string | null }
export interface DupPair { a: string; b: string; reason: 'same_phone' | 'similar_name' }

const STOP = new Set(['mr', 'mrs', 'ms', 'miss', 'dr', 'uncle', 'aunty', 'auntie', 'and', 'family', 'wife', 'husband']);

export function normName(n: string): string {
  return n
    .toLowerCase()
    .normalize('NFKC')
    .replace(/[&.,'’()-]/g, ' ')
    .split(/\s+/)
    .filter((w) => w && !STOP.has(w))
    .join(' ');
}

export function levenshtein(a: string, b: string, max = 3): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      rowMin = Math.min(rowMin, cur[j]);
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

export function similarNames(x: string, y: string): boolean {
  const a = normName(x);
  const b = normName(y);
  if (!a || !b) return false;
  if (a === b) return true;
  const short = Math.min(a.length, b.length);
  if (short < 5) return false; // "Ravi" vs "Ravu" is too risky to call a duplicate
  const allowed = short >= 10 ? 2 : 1;
  return levenshtein(a, b, allowed) <= allowed;
}

export function findDuplicates(guests: DupCandidate[]): DupPair[] {
  const out: DupPair[] = [];
  const byPhone = new Map<string, string>();
  const seen = new Set<string>();
  for (const g of guests) {
    if (g.phone) {
      const other = byPhone.get(g.phone);
      if (other) { out.push({ a: other, b: g.id, reason: 'same_phone' }); seen.add(other + g.id); }
      else byPhone.set(g.phone, g.id);
    }
  }
  // O(n²) name check is fine for a few hundred guests (1,000 guests ≈ 0.5M cheap comparisons).
  for (let i = 0; i < guests.length; i++) {
    for (let j = i + 1; j < guests.length; j++) {
      const a = guests[i], b = guests[j];
      if (seen.has(a.id + b.id) || seen.has(b.id + a.id)) continue;
      if (a.phone && b.phone && a.phone !== b.phone) continue; // different numbers: different people
      if (similarNames(a.name, b.name)) out.push({ a: a.id, b: b.id, reason: 'similar_name' });
    }
  }
  return out;
}

/** Matches a typed name against the guest list for the open group link. */
export function matchGuestName<T extends { name: string }>(typed: string, guests: T[]): T | null {
  const t = normName(typed);
  if (t.length < 3) return null;
  const exact = guests.filter((g) => normName(g.name) === t);
  if (exact.length === 1) return exact[0];
  if (exact.length > 1) return null; // ambiguous: don't guess
  const close = guests.filter((g) => similarNames(g.name, typed));
  return close.length === 1 ? close[0] : null;
}
