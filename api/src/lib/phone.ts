// Phone number normalisation. Sri Lankan numbers are the default; diaspora numbers
// must be written with a + or 00 country code.

/** Returns an E.164 number (e.g. +94771234567) or null if it isn't a usable number. */
export function normalizePhone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let s = String(raw).trim();
  const plus = s.startsWith('+');
  s = s.replace(/[^\d]/g, '');
  if (!s) return null;
  if (!plus && s.startsWith('00')) return finishIntl(s.slice(2));
  if (plus) return finishIntl(s);
  // Sri Lankan forms: 0771234567, 771234567, 94771234567
  if (s.length === 10 && s.startsWith('0')) return '+94' + s.slice(1);
  if (s.length === 9 && /^[1-9]/.test(s)) return '+94' + s;
  if (s.length === 11 && s.startsWith('94')) return '+' + s;
  return null;
}

function finishIntl(digits: string): string | null {
  if (digits.length < 8 || digits.length > 15) return null;
  if (digits.startsWith('940')) digits = '94' + digits.slice(3); // +94 077... typo
  return '+' + digits;
}

/** Digits only, the form wa.me links need. */
export function waDigits(e164: string): string {
  return e164.replace(/^\+/, '');
}

/** Finds phone-like substrings in free text. */
export const PHONE_RE = /(?:\+|00)?\d[\d\s\-()]{7,16}\d/g;
