// RSVP message reading: a guest's free-text WhatsApp reply becomes "2 coming, vegetarian".
// Keyword and phrase lists in English, Sinhala, Tamil and romanised (Singlish / Tanglish) forms,
// with light fuzzy matching. No AI. The couple always confirms before it is saved.

export interface ReadReply {
  status: 'coming' | 'not_coming' | 'maybe' | null;
  headcount: number | null;
  meal: 'vegetarian' | 'vegan' | 'halal' | null;
  confidence: 'high' | 'low';
  summary: string;
}

const NUM_WORDS: Record<string, number> = {
  one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  // Singlish
  ekak: 1, dennek: 2, denek: 2, dennai: 2, thun: 3, thundenek: 3, hathar: 4, hatharadenek: 4, paha: 5, haya: 6,
  // Sinhala
  'එක්කෙනෙක්': 1, 'දෙන්නෙක්': 2, 'දෙන්නා': 2, 'තුන්දෙනෙක්': 3, 'තුන්': 3, 'හතරදෙනෙක්': 4, 'හතර': 4, 'පස්දෙනෙක්': 5,
  // Tamil / Tanglish
  'ஒருவர்': 1, 'இருவர்': 2, 'இரண்டு': 2, 'மூன்று': 3, 'நான்கு': 4, 'ஐந்து': 5,
  rendu: 2, moonu: 3, naalu: 4, anju: 5,
};

const NOT = [
  /\b(can'?t|cannot|can not|unable|won'?t|will not|not (be )?(able|coming|attending)|sorry,? (we|i) (can'?t|won'?t)|regret|decline|miss it)\b/i,
  /\b(enna\s*ba|ena\s*ba|enna\s*bae|enna\s*be|baha|ba\s*wage|enna\s*widihak\s*na)\b/i,  // Singlish "can't come"
  /(එන්න\s*බෑ|එන්න\s*බැහැ|පැමිණිය\s*නොහැක|එන්න\s*වෙන්නේ\s*නෑ)/,
  /\b(vara\s*mudiyathu|vara\s*mudiyadhu|vara\s*mudiyaadhu)\b/i,
  /(வர\s*முடியாது|வர\s*இயலாது)/,
];
const MAYBE = [
  /\b(maybe|might|not sure|perhaps|will try|try to come|let you know|tentative|hopefully)\b/i,
  /\b(sometimes|samaharawita|balamu|try\s*karannam)\b/i,
  /(සමහරවිට|බලමු|උත්සාහ\s*කරන්නම්)/,
  /\b(paarkalam|parkalam|try\s*panren)\b/i,
  /(ஒருவேளை|பார்க்கலாம்)/,
];
const YES = [
  /\b(yes|yeah|yep|sure|definitely|of course|count (us|me) in|we('| wi)ll (be there|come|attend)|i('| wi)ll (be there|come|attend)|coming|attending|will come|see you|congrat)/i,
  /\b(enawa|ennam|enna\s*puluwan|api\s*enawa|mama\s*enawa|niyatha(yenma)?|hari)\b/i,
  /(එනවා|එන්නම්|පැමිණෙනවා|පැමිණෙමු|ඔව්)/,
  /\b(varuvom|varuven|varom|vaarom|kandippa|aama)\b/i,
  /(வருவோம்|வருகிறோம்|வருவேன்|கண்டிப்பாக|ஆம்)/,
];
const MEALS: [RegExp, ReadReply['meal']][] = [
  [/\b(vegan)\b/i, 'vegan'],
  [/\b(veg|vegetarian|veggie|elawalu|elavalu|saivam|no meat)\b|(නිර්මාංශ|එළවළු|சைவம்)/i, 'vegetarian'],
  [/\b(halal)\b|(හලාල්|ஹலால்)/i, 'halal'],
];

function countPeople(t: string): number | null {
  const lower = t.toLowerCase();
  const m = lower.match(/(\d{1,2})\s*(?:of us|people|persons?|pax|ppl|adults?|members?|denek|dena|dennek|peyar|per|guests?)/)
    ?? lower.match(/(?:we are|we're|us|party of|total)\s*(\d{1,2})\b/)
    ?? lower.match(/\b(\d{1,2})\s*(?:will|are)\s*(?:come|coming|attend)/);
  if (m) return Number(m[1]);
  for (const [w, n] of Object.entries(NUM_WORDS)) {
    const re = /^[a-z]+$/.test(w) ? new RegExp(`\\b${w}\\b`, 'i') : new RegExp(w);
    if (re.test(t)) return n;
  }
  if (/\b(both of us|the two of us|with (my )?(wife|husband|spouse|partner)|& (wife|husband))\b/i.test(t)) return 2;
  if (/\b(just me|only me|alone|myself)\b/i.test(t)) return 1;
  if (/\b(whole family|with (the )?family|with kids|family)\b/i.test(t)) return null; // size unknown
  return null;
}

export function readReply(text: string): ReadReply {
  const t = text.trim();
  let status: ReadReply['status'] = null;
  // Order matters: "sorry we can't come" contains "come"; "not sure" contains "sure".
  if (NOT.some((r) => r.test(t))) status = 'not_coming';
  else if (MAYBE.some((r) => r.test(t))) status = 'maybe';
  else if (YES.some((r) => r.test(t))) status = 'coming';
  let meal: ReadReply['meal'] = null;
  for (const [re, m] of MEALS) if (re.test(t)) { meal = m; break; }
  const headcount = status === 'not_coming' ? 0 : countPeople(t);
  const confidence: ReadReply['confidence'] = status && (status === 'not_coming' || headcount !== null) ? 'high' : 'low';
  const parts: string[] = [];
  if (status === 'coming') parts.push(headcount ? `${headcount} coming` : 'Coming');
  else if (status === 'maybe') parts.push(headcount ? `Maybe, ${headcount} people` : 'Maybe');
  else if (status === 'not_coming') parts.push('Not coming');
  else parts.push('Could not tell');
  if (meal) parts.push(meal);
  return { status, headcount, meal, confidence, summary: parts.join(', ') };
}
