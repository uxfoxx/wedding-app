// Seeds launch templates and the wording library. Safe to run repeatedly.
// Admins can add more templates and wording later without an app update.
import { pool } from './db.ts';

type Layout = {
  palette: { bg: string; surface: string; ink: string; accent: string; muted: string };
  headingFont: 'serif' | 'sans' | 'script';
  ornament: 'none' | 'lotus' | 'kolam' | 'floral' | 'geometric' | 'cross' | 'arch' | 'lines';
  animation: 'none' | 'envelope' | 'curtain' | 'scroll';
  hero: 'photo' | 'monogram' | 'pattern';
};

const T = (id: string, name: string, category: string, premium: boolean, layout: Layout, sort: number) => ({ id, name, category, premium, layout, sort });

export const templates = [
  // Five free templates
  T('kandyan-gold', 'Kandyan Gold', 'traditional', false, { palette: { bg: '#fbf6ec', surface: '#ffffff', ink: '#3b2412', accent: '#a8742a', muted: '#7a6450' }, headingFont: 'serif', ornament: 'lotus', animation: 'none', hero: 'monogram' }, 1),
  T('simple-ivory', 'Simple Ivory', 'minimal', false, { palette: { bg: '#faf8f4', surface: '#ffffff', ink: '#222222', accent: '#6b5b4b', muted: '#6e6a65' }, headingFont: 'serif', ornament: 'lines', animation: 'none', hero: 'monogram' }, 2),
  T('modern-sage', 'Modern Sage', 'modern', false, { palette: { bg: '#f1f4ef', surface: '#ffffff', ink: '#1f2a22', accent: '#4f6f52', muted: '#5d6b60' }, headingFont: 'sans', ornament: 'none', animation: 'none', hero: 'photo' }, 3),
  T('church-white', 'Chapel White', 'church', false, { palette: { bg: '#f7f8fb', surface: '#ffffff', ink: '#1d2433', accent: '#54627e', muted: '#5f6778' }, headingFont: 'serif', ornament: 'cross', animation: 'none', hero: 'photo' }, 4),
  T('homecoming-rose', 'Homecoming Rose', 'homecoming', false, { palette: { bg: '#fdf3f3', surface: '#ffffff', ink: '#3a1d24', accent: '#a5465a', muted: '#76545b' }, headingFont: 'script', ornament: 'floral', animation: 'none', hero: 'photo' }, 5),
  // Premium (Wedding Pass)
  T('poruwa-royal', 'Poruwa Royal', 'traditional', true, { palette: { bg: '#3b0d11', surface: '#4a1419', ink: '#fbeed3', accent: '#e0b354', muted: '#d9c3a0' }, headingFont: 'serif', ornament: 'lotus', animation: 'envelope', hero: 'monogram' }, 10),
  T('kovil-kolam', 'Kovil Kolam', 'kovil', true, { palette: { bg: '#fff7e8', surface: '#ffffff', ink: '#4a1a07', accent: '#c2410c', muted: '#7c5a45' }, headingFont: 'serif', ornament: 'kolam', animation: 'curtain', hero: 'pattern' }, 11),
  T('nikah-emerald', 'Nikah Emerald', 'nikah', true, { palette: { bg: '#0f2e26', surface: '#143a30', ink: '#f3efe2', accent: '#d4b26a', muted: '#c8c2ab' }, headingFont: 'serif', ornament: 'geometric', animation: 'scroll', hero: 'pattern' }, 12),
  T('cathedral-arch', 'Cathedral Arch', 'church', true, { palette: { bg: '#f4f1ea', surface: '#ffffff', ink: '#232019', accent: '#8a6d3b', muted: '#6b665b' }, headingFont: 'serif', ornament: 'arch', animation: 'curtain', hero: 'photo' }, 13),
  T('galle-blue', 'Galle Fort Blue', 'modern', true, { palette: { bg: '#eef3f8', surface: '#ffffff', ink: '#13263b', accent: '#1f5f99', muted: '#4f6378' }, headingFont: 'sans', ornament: 'lines', animation: 'envelope', hero: 'photo' }, 14),
  T('frangipani', 'Araliya Blossom', 'modern', true, { palette: { bg: '#fffaf2', surface: '#ffffff', ink: '#2e2618', accent: '#c58b1c', muted: '#6f6553' }, headingFont: 'script', ornament: 'floral', animation: 'envelope', hero: 'photo' }, 15),
  T('midnight-minimal', 'Midnight Minimal', 'minimal', true, { palette: { bg: '#111318', surface: '#1a1d24', ink: '#eceae4', accent: '#c9a96e', muted: '#a6a39b' }, headingFont: 'sans', ornament: 'lines', animation: 'scroll', hero: 'monogram' }, 16),
  T('dumbara-weave', 'Dumbara Weave', 'traditional', true, { palette: { bg: '#f6efe3', surface: '#ffffff', ink: '#2f1a10', accent: '#9a3412', muted: '#6e5646' }, headingFont: 'serif', ornament: 'geometric', animation: 'curtain', hero: 'pattern' }, 17),
  T('marigold-mandapam', 'Marigold Mandapam', 'kovil', true, { palette: { bg: '#fff4dc', surface: '#ffffff', ink: '#3d1f05', accent: '#b45309', muted: '#73563a' }, headingFont: 'serif', ornament: 'kolam', animation: 'envelope', hero: 'photo' }, 18),
  T('crescent-ivory', 'Crescent Ivory', 'nikah', true, { palette: { bg: '#f8f5ee', surface: '#ffffff', ink: '#1c2a26', accent: '#2f6b5a', muted: '#5c6b66' }, headingFont: 'script', ornament: 'geometric', animation: 'envelope', hero: 'monogram' }, 19),
  T('peacock-homecoming', 'Peacock Homecoming', 'homecoming', true, { palette: { bg: '#0e2a33', surface: '#123540', ink: '#eef6f4', accent: '#d9b44a', muted: '#b7cbc8' }, headingFont: 'script', ornament: 'floral', animation: 'scroll', hero: 'photo' }, 20),
  T('hill-country', 'Hill Country Tea', 'modern', true, { palette: { bg: '#eef3ec', surface: '#ffffff', ink: '#16261b', accent: '#2f6b3a', muted: '#566a5b' }, headingFont: 'sans', ornament: 'lines', animation: 'envelope', hero: 'photo' }, 21),
];

const W = (language: string, tone: string, event_kind: string, faith: string | null, body: string) =>
  ({ key: `${language}.${event_kind}.${tone}.${faith ?? 'any'}`, language, tone, event_kind, faith, body });

// {couple}, {date}, {venue}, {parents} are filled in by the app. Native-speaker review needed for si/ta.
// faith null = suits any wedding; otherwise it is only offered to that wedding type (and mixed).
export const wordings = [
  W('en', 'formal', 'wedding', null, '{parents} request the pleasure of your company at the marriage of {couple} on {date} at {venue}.'),
  W('en', 'modern', 'wedding', null, "We're getting married! Join {couple} on {date} at {venue} for a day of love, laughter and good food."),
  W('en', 'religious', 'wedding', 'buddhist', 'With the blessings of the Triple Gem and our families, {couple} invite you to share the joy of their wedding on {date} at {venue}.'),
  W('en', 'religious', 'wedding', 'christian', 'Together with their families and by the grace of God, {couple} invite you to witness their holy matrimony on {date} at {venue}.'),
  W('en', 'religious', 'wedding', 'muslim', 'In the name of Allah, the Most Gracious, the Most Merciful, {parents} invite you to the Nikah of {couple} on {date} at {venue}.'),
  W('en', 'religious', 'wedding', 'hindu', 'With the divine blessings of the Lord, {parents} cordially invite you to the wedding of {couple} on {date} at {venue}.'),
  W('en', 'casual', 'wedding', null, "{couple} are tying the knot! It wouldn't be the same without you. See you on {date} at {venue}."),
  W('en', 'formal', 'homecoming', null, '{parents} warmly invite you to the homecoming of {couple} on {date} at {venue}.'),
  W('en', 'casual', 'homecoming', null, '{couple} are home! Come and celebrate the homecoming with us on {date} at {venue}.'),
  W('en', 'formal', 'engagement', null, '{parents} are delighted to invite you to the engagement of {couple} on {date} at {venue}.'),
  W('en', 'modern', 'engagement', null, 'We said yes! Celebrate the engagement of {couple} with us on {date} at {venue}.'),
  W('si', 'formal', 'wedding', null, '{parents} වන අප, {couple} ගේ විවාහ මංගල්‍යය {date} දින {venue} හිදී පැවැත්වෙන බැවින් ඔබගේ සහභාගීත්වය ගෞරවයෙන් ඉල්ලා සිටිමු.'),
  W('si', 'religious', 'wedding', 'buddhist', 'තෙරුවන් සරණයි! {couple} ගේ විවාහ මංගල්‍යය {date} දින {venue} හිදී පැවැත්වේ. ඔබට සාදරයෙන් ආරාධනා කරමු.'),
  W('si', 'religious', 'wedding', 'christian', 'දෙවියන් වහන්සේගේ ආශීර්වාදයෙන්, {couple} ගේ විවාහ මංගල්‍යය {date} දින {venue} හිදී පැවැත්වේ. ඔබට සාදරයෙන් ආරාධනා කරමු.'),
  W('si', 'modern', 'wedding', null, 'අපි විවාහ වෙනවා! {date} දින {venue} හිදී {couple} සමඟ මේ සුන්දර දවස සමරන්න එන්න.'),
  W('si', 'casual', 'wedding', null, '{couple} බැඳෙනවා! ඔයා නැතුව බෑ. {date} දින {venue} හිදී හමුවෙමු.'),
  W('si', 'formal', 'homecoming', null, '{couple} ගේ ගෙදර ඒමේ උත්සවය {date} දින {venue} හිදී පැවැත්වේ. ඔබට සාදරයෙන් ආරාධනා කරමු.'),
  W('si', 'formal', 'engagement', null, '{couple} ගේ විවාහ ගිවිස ගැනීමේ උත්සවය {date} දින {venue} හිදී පැවැත්වේ. ඔබට සාදරයෙන් ආරාධනා කරමු.'),
  W('ta', 'formal', 'wedding', null, '{parents} ஆகிய நாங்கள், {couple} அவர்களின் திருமணம் {date} அன்று {venue} இல் நடைபெறுவதால், தங்கள் வருகையை அன்புடன் வேண்டுகிறோம்.'),
  W('ta', 'religious', 'wedding', 'hindu', 'இறைவன் அருளால், {couple} அவர்களின் திருமணம் {date} அன்று {venue} இல் நடைபெறும். அனைவரையும் அன்புடன் அழைக்கிறோம்.'),
  W('ta', 'religious', 'wedding', 'muslim', 'அல்லாஹ்வின் திருப்பெயரால், {couple} அவர்களின் நிக்காஹ் {date} அன்று {venue} இல் நடைபெறும். தங்கள் வருகையை வேண்டுகிறோம்.'),
  W('ta', 'religious', 'wedding', 'christian', 'இறைவனின் கிருபையால், {couple} அவர்களின் திருமணம் {date} அன்று {venue} இல் நடைபெறும். தங்கள் வருகையை அன்புடன் வேண்டுகிறோம்.'),
  W('ta', 'modern', 'wedding', null, 'நாங்கள் திருமணம் செய்கிறோம்! {date} அன்று {venue} இல் {couple} உடன் கொண்டாட வாருங்கள்.'),
  W('ta', 'casual', 'wedding', null, '{couple} திருமணம் செய்கிறார்கள்! நீங்கள் இல்லாமல் கொண்டாட்டம் முழுமையாகாது. {date} அன்று {venue} இல் சந்திப்போம்.'),
  W('ta', 'formal', 'homecoming', null, '{couple} அவர்களின் மறுவீட்டு விழா {date} அன்று {venue} இல் நடைபெறும். தங்களை அன்புடன் அழைக்கிறோம்.'),
  W('ta', 'formal', 'engagement', null, '{couple} அவர்களின் நிச்சயதார்த்தம் {date} அன்று {venue} இல் நடைபெறும். தங்களை அன்புடன் அழைக்கிறோம்.'),
];

export const vendorCategories = [
  ['photographers', 'Photographers & videographers', true], ['venues', 'Venues & hotels', true], ['decorators', 'Decorators & florists', true],
  ['caterers', 'Caterers & cakes', true], ['makeup', 'Makeup & hair', true], ['bridal', 'Bridal designers & tailors', true],
  ['music', 'DJs & bands', true], ['planners', 'Wedding planners', true],
  // Later
  ['jewellery', 'Jewellery', false], ['cars', 'Wedding cars', false], ['printers', 'Invitation printers', false], ['travel', 'Honeymoon travel', false], ['ceremonial', 'Ceremonial support', false],
] as const;

export async function seed() {
  for (const [i, [id, name, active]] of vendorCategories.entries()) {
    await pool.query(`INSERT INTO vendor_categories (id, name, active, sort) VALUES ($1,$2,$3,$4) ON CONFLICT (id) DO NOTHING`, [id, name, active, i]);
  }
  for (const t of templates) {
    await pool.query(
      `INSERT INTO templates (id, name, category, premium, layout, sort) VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, category=EXCLUDED.category, premium=EXCLUDED.premium, layout=EXCLUDED.layout, sort=EXCLUDED.sort`,
      [t.id, t.name, t.category, t.premium, JSON.stringify(t.layout), t.sort],
    );
  }
  // Rows seeded before seed_key existed are claimed by their text; after that each launch
  // wording is added once and never overwritten, so admin edits and unpublishing stick.
  for (const w of wordings) {
    await pool.query('UPDATE wordings SET seed_key=$1 WHERE seed_key IS NULL AND body=$2', [w.key, w.body]);
    await pool.query(`INSERT INTO wordings (seed_key, language, tone, event_kind, faith, body) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (seed_key) DO NOTHING`,
      [w.key, w.language, w.tone, w.event_kind, w.faith, w.body]);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await seed();
  console.log(`seeded ${templates.length} templates`);
  await pool.end();
}
