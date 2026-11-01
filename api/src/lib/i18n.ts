// Strings for guest pages and outgoing messages in English, Sinhala and Tamil.
// NOTE: Sinhala and Tamil text must be reviewed by a native speaker before launch.

export type Lang = 'en' | 'si' | 'ta';
export const LANGS: readonly Lang[] = ['en', 'si', 'ta'];

export const guestStrings: Record<Lang, Record<string, string>> = {
  en: {
    dear: 'Dear {name},',
    invited: 'You are warmly invited',
    together: 'together with their families',
    countdown: 'Counting down',
    days: 'days', hours: 'hours', minutes: 'minutes',
    directions: 'Directions',
    calendar: 'Add to calendar',
    programme: 'Programme',
    dressCode: 'Dress code',
    rsvp: 'Will you join us?',
    rsvpBy: 'Please reply',
    coming: 'Coming', notComing: 'Not coming', maybe: 'Maybe',
    howMany: 'How many people (including you)?',
    seatsFor: 'We have reserved {n} seat(s) for you.',
    meal: 'Meal preference', mealAny: 'No preference', mealVeg: 'Vegetarian', mealVegan: 'Vegan', mealHalal: 'Halal',
    dietary: 'Allergies or dietary needs',
    message: 'A message for the couple (optional)',
    send: 'Send reply',
    thanks: 'Thank you! Your reply has been sent.',
    change: 'Change my reply',
    error: 'Something went wrong. Please try again.',
    openTitle: 'Please tell us who you are',
    openName: 'Your name as the couple knows you',
    openContinue: 'Continue',
    openNotFound: 'We could not find that name. Please ask the couple for your personal link.',
    invalid: 'This invitation link is not valid any more. Please ask the couple for a new one.',
    tapToOpen: 'Tap to open',
    madeWith: 'Create your own invitation',
    language: 'Language',
    updatesTitle: 'Latest from the couple', menuTitle: 'Menu', table: 'Your table', sharePhotos: 'Share photos & wishes', findSeat: 'Find your seat', keepsake: 'Photos & guestbook',
  },
  si: {
    dear: 'ගරු {name},',
    invited: 'ඔබට සාදරයෙන් ආරාධනා කරමු',
    together: 'දෙපාර්ශ්වයේ පවුල් සමඟ',
    countdown: 'තව',
    days: 'දින', hours: 'පැය', minutes: 'මිනිත්තු',
    directions: 'මාර්ගය',
    calendar: 'දින දර්ශනයට එක් කරන්න',
    programme: 'වැඩසටහන',
    dressCode: 'ඇඳුම් විලාසය',
    rsvp: 'ඔබ සහභාගී වන්නේද?',
    rsvpBy: 'කරුණාකර පිළිතුරු දෙන්න',
    coming: 'පැමිණෙමි', notComing: 'පැමිණිය නොහැක', maybe: 'සමහරවිට',
    howMany: 'පැමිණෙන ගණන (ඔබද ඇතුළුව)?',
    seatsFor: 'ඔබ වෙනුවෙන් ආසන {n}ක් වෙන් කර ඇත.',
    meal: 'ආහාර කැමැත්ත', mealAny: 'විශේෂ කැමැත්තක් නැත', mealVeg: 'නිර්මාංශ', mealVegan: 'වීගන්', mealHalal: 'හලාල්',
    dietary: 'ආසාත්මිකතා හෝ ආහාර අවශ්‍යතා',
    message: 'යුවළට පණිවිඩයක් (අවශ්‍ය නම්)',
    send: 'පිළිතුර යවන්න',
    thanks: 'ස්තූතියි! ඔබේ පිළිතුර ලැබුණා.',
    change: 'පිළිතුර වෙනස් කරන්න',
    error: 'දෝෂයක් සිදු විය. නැවත උත්සාහ කරන්න.',
    openTitle: 'කරුණාකර ඔබ කවුදැයි කියන්න',
    openName: 'ඔබේ නම',
    openContinue: 'ඉදිරියට',
    openNotFound: 'එම නම හමු නොවීය. ඔබේ පුද්ගලික සබැඳිය යුවළගෙන් ඉල්ලන්න.',
    invalid: 'මෙම ආරාධනා සබැඳිය තවදුරටත් වලංගු නැත.',
    tapToOpen: 'විවෘත කිරීමට තට්ටු කරන්න',
    madeWith: 'ඔබේම ආරාධනාවක් සාදන්න',
    language: 'භාෂාව',
    updatesTitle: 'යුවළගෙන් නවතම පුවත', menuTitle: 'ආහාර වට්ටෝරුව', table: 'ඔබේ මේසය', sharePhotos: 'ඡායාරූප සහ සුබපැතුම් එවන්න', findSeat: 'ඔබේ ආසනය සොයන්න', keepsake: 'ඡායාරූප සහ සුබපැතුම්',
  },
  ta: {
    dear: 'அன்புள்ள {name},',
    invited: 'உங்களை அன்புடன் அழைக்கிறோம்',
    together: 'இரு குடும்பத்தினருடன்',
    countdown: 'இன்னும்',
    days: 'நாட்கள்', hours: 'மணி', minutes: 'நிமிடங்கள்',
    directions: 'வழி',
    calendar: 'நாட்காட்டியில் சேர்',
    programme: 'நிகழ்ச்சி நிரல்',
    dressCode: 'உடை',
    rsvp: 'நீங்கள் வருவீர்களா?',
    rsvpBy: 'தயவுசெய்து பதிலளிக்கவும்',
    coming: 'வருகிறேன்', notComing: 'வர முடியாது', maybe: 'ஒருவேளை',
    howMany: 'எத்தனை பேர் (உங்களையும் சேர்த்து)?',
    seatsFor: 'உங்களுக்காக {n} இருக்கைகள் ஒதுக்கப்பட்டுள்ளன.',
    meal: 'உணவு விருப்பம்', mealAny: 'விருப்பம் இல்லை', mealVeg: 'சைவம்', mealVegan: 'வீகன்', mealHalal: 'ஹலால்',
    dietary: 'ஒவ்வாமை அல்லது உணவு தேவைகள்',
    message: 'தம்பதியினருக்கு ஒரு செய்தி (விரும்பினால்)',
    send: 'பதிலை அனுப்பு',
    thanks: 'நன்றி! உங்கள் பதில் அனுப்பப்பட்டது.',
    change: 'பதிலை மாற்று',
    error: 'பிழை ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.',
    openTitle: 'நீங்கள் யார் என்று சொல்லுங்கள்',
    openName: 'உங்கள் பெயர்',
    openContinue: 'தொடர்க',
    openNotFound: 'அந்தப் பெயர் கிடைக்கவில்லை. உங்கள் தனிப்பட்ட இணைப்பை தம்பதியினரிடம் கேளுங்கள்.',
    invalid: 'இந்த அழைப்பு இணைப்பு இனி செல்லாது.',
    tapToOpen: 'திறக்க தொடவும்',
    madeWith: 'உங்கள் சொந்த அழைப்பை உருவாக்குங்கள்',
    language: 'மொழி',
    updatesTitle: 'தம்பதியினரின் புதிய தகவல்', menuTitle: 'உணவு பட்டியல்', table: 'உங்கள் மேசை', sharePhotos: 'புகைப்படங்கள் & வாழ்த்துகள் பகிர்க', findSeat: 'உங்கள் இருக்கையைக் காண்க', keepsake: 'புகைப்படங்கள் & வாழ்த்துகள்',
  },
};

export const eventNames: Record<Lang, Record<string, string>> = {
  en: { poruwa: 'Poruwa Ceremony', church: 'Church Ceremony', nikah: 'Nikah', kovil: 'Kovil Ceremony', registration: 'Registration', reception: 'Reception', homecoming: 'Homecoming', engagement: 'Engagement', other: 'Celebration' },
  si: { poruwa: 'පෝරුව චාරිත්‍රය', church: 'දේවස්ථාන උත්සවය', nikah: 'නිකාහ්', kovil: 'කෝවිල් උත්සවය', registration: 'ලියාපදිංචිය', reception: 'පිළිගැනීම', homecoming: 'ගෙදර ඒම', engagement: 'විවාහ ගිවිස ගැනීම', other: 'උත්සවය' },
  ta: { poruwa: 'பொருவ சடங்கு', church: 'தேவாலய திருமணம்', nikah: 'நிக்காஹ்', kovil: 'கோவில் திருமணம்', registration: 'பதிவு', reception: 'வரவேற்பு', homecoming: 'வீட்டுக்கு வருகை', engagement: 'நிச்சயதார்த்தம்', other: 'கொண்டாட்டம்' },
};

/** WhatsApp invitation message. {link} is replaced last so it is never translated. */
export const inviteMessage: Record<Lang, string> = {
  en: 'Dear {name}, with great joy {couple} invite you to celebrate their {kind}. Please open your personal invitation and let us know if you can join us:\n{link}',
  si: 'ගරු {name}, {couple} ගේ {kind} උත්සවයට ඔබට සාදරයෙන් ආරාධනා කරමු. කරුණාකර ඔබේ ආරාධනාව විවෘත කර පිළිතුරු දෙන්න:\n{link}',
  ta: 'அன்புள்ள {name}, {couple} அவர்களின் {kind} விழாவிற்கு உங்களை அன்புடன் அழைக்கிறோம். உங்கள் அழைப்பைத் திறந்து பதிலளிக்கவும்:\n{link}',
};

export const reminderMessage: Record<Lang, string> = {
  en: 'Dear {name}, a gentle reminder from {couple}: please let us know if you can join us. It only takes a minute:\n{link}',
  si: 'ගරු {name}, {couple} වෙතින් මතක් කිරීමක්: ඔබ පැමිණෙන්නේදැයි කරුණාකර දන්වන්න:\n{link}',
  ta: 'அன்புள்ள {name}, {couple} அவர்களிடமிருந்து ஒரு நினைவூட்டல்: நீங்கள் வருவீர்களா என்று தெரிவிக்கவும்:\n{link}',
};

export const updateMessage: Record<Lang, string> = {
  en: 'Dear {name}, an update from {couple}: {update}\nDetails: {link}',
  si: 'ගරු {name}, {couple} වෙතින් දැනුම්දීමක්: {update}\nවිස්තර: {link}',
  ta: 'அன்புள்ள {name}, {couple} அவர்களிடமிருந்து ஒரு அறிவிப்பு: {update}\nவிவரங்கள்: {link}',
};

export const thanksMessage: Record<Lang, string> = {
  en: 'Dear {name}, thank you for celebrating with us! Our photos and your messages are here: {link}\nWith love, {couple}',
  si: 'ගරු {name}, අප සමඟ සතුට බෙදාගත්තාට ස්තූතියි! ඡායාරූප සහ පණිවිඩ මෙතැනින්: {link}\nආදරයෙන්, {couple}',
  ta: 'அன்புள்ள {name}, எங்களுடன் கொண்டாடியதற்கு நன்றி! புகைப்படங்களும் வாழ்த்துகளும் இங்கே: {link}\nஅன்புடன், {couple}',
};

export const kindWords: Record<Lang, Record<string, string>> = {
  en: { wedding: 'wedding', engagement: 'engagement', homecoming: 'homecoming', other: 'celebration' },
  si: { wedding: 'විවාහ මංගල්‍ය', engagement: 'විවාහ ගිවිස ගැනීමේ', homecoming: 'ගෙදර ඒමේ', other: 'උත්සව' },
  ta: { wedding: 'திருமண', engagement: 'நிச்சயதார்த்த', homecoming: 'வீட்டுக்கு வருகை', other: 'கொண்டாட்ட' },
};

export function fill(tpl: string, vars: Record<string, string | number>): string {
  return tpl.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
}
