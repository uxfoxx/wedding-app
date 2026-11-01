// "Suggest a plan": a small greedy constraint solver (no AI), fast enough for 1,000 guests.
// Rules, in priority order:
//   1. Never exceed a table's seats.
//   2. A party (one invitation) is never split.
//   3. Known conflicts never share a table.
//   4. Families/groups sit together; sides are kept together.
//   5. VIPs and elders go to the head table / front tables first.

export interface SeatGuest {
  id: string;
  name: string;
  size: number;               // people in this party (confirmed headcount, else seats)
  side: string | null;
  group: string | null;
  vip: boolean;
  elder: boolean;             // e.g. titles like Ven., Rev., Uncle, Aunty, Mr/Mrs with "senior" tag
  fixedTable?: string | null; // already placed by the couple: kept as is
}

export interface SeatTable { id: string; name: string; seats: number; shape: string; sort: number }

export interface SeatPlan {
  assignments: Record<string, string>;   // guestId -> tableId
  unplaced: string[];                    // guests that could not be placed
  warnings: string[];
}

const ELDER_TITLES = /^(ven|rev|fr|dr|prof|hon|uncle|aunty|auntie|achchi|seeya|appachchi|amma|periyappa|periyamma|mama|nanda)\b/i;
export function looksElder(title: string | null, tags: string[] = []): boolean {
  return tags.includes('elder') || (!!title && ELDER_TITLES.test(title));
}

export function suggestSeating(guests: SeatGuest[], tables: SeatTable[], conflicts: [string, string][]): SeatPlan {
  const free = new Map(tables.map((t) => [t.id, t.seats]));
  const at = new Map<string, Set<string>>(tables.map((t) => [t.id, new Set()]));
  const tableGroups = new Map<string, Map<string, number>>(tables.map((t) => [t.id, new Map()]));
  const tableSides = new Map<string, Map<string, number>>(tables.map((t) => [t.id, new Map()]));
  const enemies = new Map<string, Set<string>>();
  for (const [a, b] of conflicts) {
    if (!enemies.has(a)) enemies.set(a, new Set());
    if (!enemies.has(b)) enemies.set(b, new Set());
    enemies.get(a)!.add(b);
    enemies.get(b)!.add(a);
  }
  const assignments: Record<string, string> = {};
  const unplaced: string[] = [];
  const warnings: string[] = [];

  const place = (g: SeatGuest, tableId: string) => {
    assignments[g.id] = tableId;
    free.set(tableId, free.get(tableId)! - g.size);
    at.get(tableId)!.add(g.id);
    if (g.group) tableGroups.get(tableId)!.set(g.group, (tableGroups.get(tableId)!.get(g.group) ?? 0) + g.size);
    if (g.side) tableSides.get(tableId)!.set(g.side, (tableSides.get(tableId)!.get(g.side) ?? 0) + g.size);
  };

  // Keep what the couple already placed (if it still fits).
  for (const g of guests) {
    if (g.fixedTable && free.has(g.fixedTable) && free.get(g.fixedTable)! >= g.size) place(g, g.fixedTable);
  }

  // Front tables first: head table, then by sort order.
  const ordered = [...tables].sort((a, b) => (a.shape === 'head' ? -1 : 0) - (b.shape === 'head' ? -1 : 0) || a.sort - b.sort);
  const rank = new Map(ordered.map((t, i) => [t.id, i]));

  // Place big groups as blocks first, VIPs/elders first within that, then larger parties.
  const groupSize = new Map<string, number>();
  for (const g of guests) if (g.group) groupSize.set(g.group, (groupSize.get(g.group) ?? 0) + g.size);
  // People in each group still waiting for a seat: the first member of a group looks for a
  // table with room for the whole group, so families are not split across tables.
  const groupLeft = new Map<string, number>();
  for (const g of guests) if (g.group && !assignments[g.id]) groupLeft.set(g.group, (groupLeft.get(g.group) ?? 0) + g.size);
  const todo = guests
    .filter((g) => !assignments[g.id])
    .sort((a, b) =>
      Number(b.vip) - Number(a.vip) ||
      Number(b.elder) - Number(a.elder) ||
      (groupSize.get(b.group ?? '') ?? 0) - (groupSize.get(a.group ?? '') ?? 0) ||
      (a.group ?? '').localeCompare(b.group ?? '') ||
      b.size - a.size);

  for (const g of todo) {
    let best: string | null = null;
    let bestScore = -Infinity;
    for (const t of ordered) {
      const left = free.get(t.id)!;
      if (left < g.size) continue;
      const bad = enemies.get(g.id);
      if (bad && [...at.get(t.id)!].some((x) => bad.has(x))) continue;
      if (t.shape === 'head' && !g.vip) continue; // head table is for VIPs / the couple's party
      let score = 0;
      if (g.group) {
        const here = tableGroups.get(t.id)!.get(g.group) ?? 0;
        score += 10 * here;
        const placedElsewhere = [...tableGroups.values()].some((m) => (m.get(g.group!) ?? 0) > 0);
        if (!placedElsewhere) score += left >= (groupLeft.get(g.group) ?? g.size) ? 15 : -15;
      }
      if (g.side) score += 2 * (tableSides.get(t.id)!.get(g.side) ?? 0);
      const otherSide = [...tableSides.get(t.id)!.entries()].filter(([s]) => s !== g.side && s !== 'both').reduce((n, [, c]) => n + c, 0);
      if (g.side && g.side !== 'both') score -= 1.5 * otherSide;
      if (g.vip || g.elder) score -= 3 * rank.get(t.id)!;      // pull to the front
      else score -= 0.2 * rank.get(t.id)!;
      if (at.get(t.id)!.size === 0 && g.group && !(tableGroups.get(t.id)!.size)) score += 1; // start a fresh table for a new group
      score -= 0.05 * (left - g.size);                          // prefer tighter fits
      if (score > bestScore) { bestScore = score; best = t.id; }
    }
    if (g.group) groupLeft.set(g.group, (groupLeft.get(g.group) ?? g.size) - g.size);
    if (best) place(g, best);
    else unplaced.push(g.id);
  }

  const totalSeats = tables.reduce((n, t) => n + t.seats, 0);
  const totalPeople = guests.reduce((n, g) => n + g.size, 0);
  if (totalPeople > totalSeats) warnings.push(`${totalPeople} people but only ${totalSeats} seats. Add ${totalPeople - totalSeats} more seats.`);
  if (unplaced.length && totalPeople <= totalSeats) warnings.push('Some parties did not fit without splitting them or seating known conflicts together. Add a table or move people by hand.');
  return { assignments, unplaced, warnings };
}
