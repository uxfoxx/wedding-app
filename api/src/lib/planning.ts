// Suggested checklist (by months before the wedding) and the wedding readiness score.

export interface ChecklistSeed { title: string; months_before: number }

const COMMON: ChecklistSeed[] = [
  { title: 'Agree the total budget with both families', months_before: 12 },
  { title: 'Fix the date and auspicious times (nekath) with the astrologer', months_before: 12 },
  { title: 'Book the venue / hotel', months_before: 12 },
  { title: 'Book the photographer and videographer', months_before: 10 },
  { title: 'Book the decorator', months_before: 9 },
  { title: 'Book the caterer or confirm the hotel menu', months_before: 9 },
  { title: 'Order or design the bridal dress and groom\'s attire', months_before: 8 },
  { title: 'Book makeup and hair (with a trial)', months_before: 6 },
  { title: 'Book the band or DJ', months_before: 6 },
  { title: 'Finish the guest list with both families', months_before: 4 },
  { title: 'Publish the invitation', months_before: 3 },
  { title: 'Send invitations on WhatsApp', months_before: 2 },
  { title: 'Book wedding cars', months_before: 2 },
  { title: 'Menu tasting', months_before: 2 },
  { title: 'Follow up guests who have not replied', months_before: 1 },
  { title: 'Give the final headcount and meal numbers to the caterer', months_before: 1 },
  { title: 'Make the seating plan', months_before: 1 },
  { title: 'Write the wedding-day run sheet and share it', months_before: 1 },
  { title: 'Final payments to suppliers', months_before: 0 },
  { title: 'Send thank-you messages', months_before: -1 },
];

const BY_TYPE: Record<string, ChecklistSeed[]> = {
  buddhist: [
    { title: 'Book the Poruwa and its decoration', months_before: 6 },
    { title: 'Arrange the Jayamangala Gatha singers', months_before: 3 },
    { title: 'Arrange the Ashtaka reciter', months_before: 3 },
    { title: 'Book the registrar for the Poruwa', months_before: 2 },
  ],
  hindu: [
    { title: 'Confirm the kovil and the priest (kurukkal)', months_before: 9 },
    { title: 'Buy the thali / thaali kodi', months_before: 3 },
    { title: 'Arrange the nadaswaram and thavil players', months_before: 3 },
  ],
  christian: [
    { title: 'Book the church and meet the priest / pastor', months_before: 10 },
    { title: 'Pre-marriage course', months_before: 6 },
    { title: 'Publish the banns', months_before: 2 },
    { title: 'Choose the choir and hymns', months_before: 2 },
  ],
  muslim: [
    { title: 'Confirm the mosque and the Nikah officiant', months_before: 6 },
    { title: 'Agree the mahr', months_before: 3 },
    { title: 'Book the Quazi / registrar', months_before: 2 },
  ],
  civil: [{ title: 'Book the registrar and give notice', months_before: 3 }],
  mixed: [],
};

export function suggestedChecklist(weddingType: string): ChecklistSeed[] {
  return [...COMMON, ...(BY_TYPE[weddingType] ?? [])].sort((a, b) => b.months_before - a.months_before);
}

export interface ReadinessInput {
  published: boolean;
  guests: number;
  expectedGuests: number | null;
  sent: number;
  replied: number;
  coming: number;
  seated: number;            // coming parties with a table
  tables: number;
  runSheetItems: number;
  checklistTotal: number;
  checklistDone: number;
  daysToGo: number | null;
}

export interface Readiness { score: number; parts: { key: string; label: string; done: number; weight: number }[]; next: { key: string; label: string }[] }

export function readiness(r: ReadinessInput): Readiness {
  const ratio = (a: number, b: number) => (b <= 0 ? 0 : Math.min(1, a / b));
  const guestTarget = Math.max(5, r.expectedGuests ? Math.round(r.expectedGuests * 0.8) : 5);
  const parts = [
    { key: 'publish', label: 'Publish your invitation', weight: 15, done: r.published ? 1 : 0 },
    { key: 'add_guests', label: 'Add your guest list', weight: 15, done: ratio(r.guests, guestTarget) },
    { key: 'send', label: 'Send invitations', weight: 15, done: ratio(r.sent, r.guests) },
    { key: 'follow_up', label: 'Collect replies', weight: 20, done: ratio(r.replied, r.guests) },
    { key: 'seating', label: 'Seat confirmed guests', weight: 15, done: r.tables === 0 ? 0 : ratio(r.seated, r.coming) },
    { key: 'run_sheet', label: 'Write the wedding-day run sheet', weight: 10, done: ratio(r.runSheetItems, 6) },
    { key: 'checklist', label: 'Work through the checklist', weight: 10, done: ratio(r.checklistDone, r.checklistTotal) },
  ];
  const score = Math.round(parts.reduce((n, p) => n + p.weight * p.done, 0));
  // Next steps in the order a wedding actually happens, skipping what is (nearly) done.
  const next = parts.filter((p) => p.done < 0.95).slice(0, 3).map((p) => ({ key: p.key, label: p.label }));
  return { score, parts, next };
}
