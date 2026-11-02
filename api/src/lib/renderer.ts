// The one template renderer (architecture decision 2). It produces the guest page as
// plain HTML + CSS + a little JavaScript (decision 3). The same output is used for the
// published page on the CDN and for the in-app / web-panel preview.
//
// The page is a static shell shared by every guest of a wedding. The guest's personal
// data lives in a small JSON file next to it (g/<token>.json); the token travels in the
// URL fragment (#t=...), so it is never sent to the CDN or logged, and the shell caches.

import { escapeHtml } from './util.ts';
import { guestStrings, eventNames, LANGS, type Lang } from './i18n.ts';

export interface RenderEvent {
  id: string; kind: string; title: string | null; starts_at: string; ends_at: string | null;
  nekath: string | null; venue: string | null; address: string | null; maps_url: string | null;
  dress_code: string | null; programme: { time: string; item: string }[];
}

export interface RenderInput {
  wedding: {
    slug: string; kind: string; partner1: string; partner2: string; language: Lang;
    invitation: Record<string, any>; hasOpenLink: boolean;
  };
  updates?: { body: string; kind: string; created_at: string }[];
  features?: { uploads: boolean; seating: boolean };
  planner?: { name: string; logo_url: string | null } | null;   // white-label (Studio)
  template: { id: string; layout: any };
  events: RenderEvent[];
  showBranding: boolean;
  apiUrl: string;
  siteUrl: string;           // public URL of this page (for og:url)
  signupUrl: string;         // "Create your own invitation"
  preview?: { guest: GuestJson };  // embed a sample guest instead of fetching
}

export interface GuestJson {
  name: string;
  seats: number;
  events: string[];          // event ids this guest is invited to
  rsvps: Record<string, { status: string; headcount: number; meal: string | null; dietary: string | null; message: string | null }>;
  tables?: Record<string, string>;   // event id -> table name, once seating is published
}

const FONT_LINKS: Record<string, string> = {
  serif: 'family=Cormorant+Garamond:wght@500;700',
  sans: 'family=Inter:wght@400;600',
  script: 'family=Great+Vibes',
};

function ornamentSvg(kind: string, color: string): string {
  const c = escapeHtml(color);
  switch (kind) {
    case 'lotus':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><path d="M60 6c8 10 8 20 0 28-8-8-8-18 0-28zM60 34c-12-2-22-10-26-20 12 0 22 8 26 20zm0 0c12-2 22-10 26-20-12 0-22 8-26 20zM8 36h40M72 36h40" fill="none" stroke="${c}" stroke-width="1.6"/></svg>`;
    case 'kolam':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><g fill="none" stroke="${c}" stroke-width="1.4"><circle cx="60" cy="20" r="8"/><path d="M60 4l16 16-16 16-16-16z"/><path d="M20 20h20M80 20h20"/></g><g fill="${c}"><circle cx="30" cy="12" r="1.6"/><circle cx="30" cy="28" r="1.6"/><circle cx="90" cy="12" r="1.6"/><circle cx="90" cy="28" r="1.6"/></g></svg>`;
    case 'geometric':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><g fill="none" stroke="${c}" stroke-width="1.4"><path d="M60 4l6 10h12l-6 10 6 10H66l-6 10-6-10H42l6-10-6-10h12z" transform="scale(1 .8) translate(0 2)"/><path d="M10 20h28M82 20h28"/></g></svg>`;
    case 'floral':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><g fill="none" stroke="${c}" stroke-width="1.4"><circle cx="60" cy="20" r="4"/><path d="M60 16c-3-8 3-12 0-12M60 24c3 8-3 12 0 12M56 20c-8-3-12 3-12 0M64 20c8 3 12-3 12 0"/><path d="M14 22c10-8 20 4 30-2M76 20c10 6 20-6 30 2"/></g></svg>`;
    case 'cross':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><g fill="none" stroke="${c}" stroke-width="1.6"><path d="M60 6v28M52 14h16"/><path d="M12 22h34M74 22h34"/></g></svg>`;
    case 'arch':
      return `<svg viewBox="0 0 120 40" aria-hidden="true"><g fill="none" stroke="${c}" stroke-width="1.4"><path d="M44 38V22a16 16 0 0132 0v16"/><path d="M50 38V23a10 10 0 0120 0v15"/><path d="M8 38h30M82 38h30"/></g></svg>`;
    case 'lines':
      return `<svg viewBox="0 0 120 12" aria-hidden="true"><path d="M10 6h44M66 6h44" stroke="${c}" stroke-width="1"/><circle cx="60" cy="6" r="2" fill="${c}"/></svg>`;
    default:
      return '';
  }
}

/** Escape JSON for safe embedding inside a <script> element. */
function jsonForScript(v: unknown): string {
  return JSON.stringify(v).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

export function renderGuestPage(input: RenderInput): string {
  const { wedding, template, events, showBranding } = input;
  const L = template.layout;
  const p = L.palette;
  const inv = wedding.invitation ?? {};
  const lang = wedding.language;
  const s = guestStrings[lang];
  const couple = `${wedding.partner1} & ${wedding.partner2}`;
  const firstEvent = events[0];
  const title = `${couple} · ${eventNames.en[firstEvent?.kind ?? 'other'] ?? 'Invitation'}`;
  const dateText = firstEvent ? new Date(firstEvent.starts_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Colombo' }) : '';
  const desc = [dateText, firstEvent?.venue].filter(Boolean).join(' · ');
  const coverPhoto: string | undefined = inv.cover_photo_url;
  const photos: string[] = Array.isArray(inv.photos) ? inv.photos.slice(0, 12) : [];

  const fontFamilies = [FONT_LINKS[L.headingFont] ?? FONT_LINKS.serif, FONT_LINKS.sans, 'family=Noto+Sans+Sinhala:wght@400;600', 'family=Noto+Sans+Tamil:wght@400;600'];
  const fontsHref = `https://fonts.googleapis.com/css2?${[...new Set(fontFamilies)].join('&')}&display=swap`;
  const headingStack = L.headingFont === 'script' ? `'Great Vibes', 'Noto Sans Sinhala', 'Noto Sans Tamil', cursive`
    : L.headingFont === 'sans' ? `'Inter', 'Noto Sans Sinhala', 'Noto Sans Tamil', system-ui, sans-serif`
    : `'Cormorant Garamond', 'Noto Sans Sinhala', 'Noto Sans Tamil', Georgia, serif`;

  const pageData = {
    slug: wedding.slug,
    lang,
    api: input.apiUrl,
    couple,
    kind: wedding.kind,
    events: events.map((e) => ({ ...e, name: e.title })),
    strings: Object.fromEntries(LANGS.map((l) => [l, guestStrings[l]])),
    eventNames,
    hasOpenLink: wedding.hasOpenLink,
    animation: L.animation,
    music: inv.music_url ?? null,
    preview: input.preview?.guest ?? null,
    meals: inv.meal_options !== false,
    menu: Array.isArray(inv.menu) ? inv.menu : [],
    updates: (input.updates ?? []).slice(0, 10),
    features: input.features ?? { uploads: false, seating: false },
  };

  const ornament = ornamentSvg(L.ornament, p.accent);
  const heroBlock = L.hero === 'photo' && coverPhoto
    ? `<img class="cover" src="${escapeHtml(coverPhoto)}" alt="" width="800" height="600" decoding="async">`
    : `<div class="mono" aria-hidden="true">${escapeHtml(wedding.partner1.charAt(0))}<span>&amp;</span>${escapeHtml(wedding.partner2.charAt(0))}</div>`;

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(desc)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(desc)}">
<meta property="og:url" content="${escapeHtml(input.siteUrl)}">
${coverPhoto ? `<meta property="og:image" content="${escapeHtml(coverPhoto)}">` : ''}
<meta name="robots" content="noindex">
<meta name="theme-color" content="${escapeHtml(p.bg)}">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="${fontsHref}">
<style>
:root{--bg:${p.bg};--surface:${p.surface};--ink:${p.ink};--accent:${p.accent};--muted:${p.muted}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:1rem/1.6 'Inter','Noto Sans Sinhala','Noto Sans Tamil',system-ui,sans-serif}
main{max-width:640px;margin:0 auto;padding:24px 16px 48px}
h1,h2,.mono{font-family:${headingStack};font-weight:700;line-height:1.2}
h1{font-size:clamp(2rem,8vw,3rem);margin:.25em 0;text-align:center;overflow-wrap:anywhere}
h2{font-size:1.5rem;margin:0 0 .5em}
.center{text-align:center}
.orn{display:block;width:180px;max-width:60%;margin:12px auto}
.mono{font-size:4rem;text-align:center;color:var(--accent)}
.mono span{font-size:2rem;margin:0 .2em}
.cover{width:100%;height:auto;border-radius:12px;display:block}
.dear{font-size:1.25rem;text-align:center;margin:20px 0 4px}
.muted{color:var(--muted)}
.msg{font-size:1.125rem;text-align:center;white-space:pre-line}
.card{background:var(--surface);border-radius:14px;padding:18px;margin:16px 0;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.event h3{margin:0 0 4px;font-size:1.25rem}
.row{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:10px 18px;border-radius:24px;border:2px solid var(--accent);background:transparent;color:var(--ink);font:inherit;font-weight:600;text-decoration:none;cursor:pointer}
.btn.primary,.btn[aria-pressed=true]{background:var(--accent);color:var(--surface)}
.btn:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
label{display:block;font-weight:600;margin:14px 0 6px}
input,select,textarea{width:100%;min-height:48px;padding:10px 12px;border:1.5px solid var(--muted);border-radius:10px;background:var(--surface);color:var(--ink);font:inherit}
textarea{min-height:80px}
.cd{display:flex;justify-content:center;gap:16px;margin:12px 0}
.cd div{text-align:center}.cd b{display:block;font-size:1.75rem;color:var(--accent)}
.prog{list-style:none;padding:0;margin:8px 0 0}.prog li{display:flex;gap:12px;padding:4px 0}.prog b{min-width:72px}
.gal{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px}
.gal img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px}
.lang{display:flex;justify-content:center;gap:6px;margin-bottom:8px}
.lang button{min-height:40px;padding:4px 12px;border-radius:20px;border:1px solid var(--muted);background:transparent;color:var(--ink);font:inherit;cursor:pointer}
.lang button[aria-pressed=true]{border-color:var(--accent);background:var(--accent);color:var(--surface)}
.notice{padding:12px;border-radius:10px;background:var(--surface);border-left:4px solid var(--accent)}
footer{text-align:center;margin-top:32px;font-size:.9rem}
footer a{color:var(--muted)}
#cover{position:fixed;inset:0;z-index:10;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;background:var(--bg);cursor:pointer;transition:transform .9s ease,opacity .9s ease}
#cover .seal{width:96px;height:96px;border-radius:50%;background:var(--accent);color:var(--surface);display:flex;align-items:center;justify-content:center;font-family:${headingStack};font-size:2rem}
#cover.open.envelope{transform:translateY(-100%)}
#cover.open.curtain{transform:scaleX(0)}
#cover.open.scroll{transform:scaleY(0);transform-origin:top}
#cover.open{opacity:0;pointer-events:none}
#music{position:fixed;right:16px;bottom:16px;width:48px;height:48px;border-radius:50%;border:none;background:var(--accent);color:var(--surface);font-size:1.25rem;cursor:pointer}
[hidden]{display:none!important}
@media (prefers-reduced-motion:reduce){#cover{transition:none}}
</style>
</head>
<body>
${L.animation !== 'none' ? `<div id="cover" class="${escapeHtml(L.animation)}" role="button" tabindex="0"><div class="seal">${escapeHtml(wedding.partner1.charAt(0))}&amp;${escapeHtml(wedding.partner2.charAt(0))}</div><div class="muted" data-s="tapToOpen">${escapeHtml(s.tapToOpen)}</div></div>` : ''}
<main>
  <div class="lang" role="group" aria-label="${escapeHtml(s.language)}">
    <button data-lang="en">English</button><button data-lang="si">සිංහල</button><button data-lang="ta">தமிழ்</button>
  </div>
  ${heroBlock}
  ${ornament ? `<div class="orn">${ornament}</div>` : ''}
  <p class="dear" id="dear" hidden></p>
  <p class="center muted" data-s="invited">${escapeHtml(s.invited)}</p>
  <h1>${escapeHtml(wedding.partner1)}<br><span class="muted" style="font-size:.6em">&amp;</span><br>${escapeHtml(wedding.partner2)}</h1>
  ${inv.parents ? `<p class="center muted">${escapeHtml(inv.parents)}</p>` : ''}
  ${inv.message ? `<p class="msg">${escapeHtml(inv.message)}</p>` : ''}
  <div class="cd" id="cd" aria-live="off"></div>
  <div id="open" class="card" hidden>
    <h2 data-s="openTitle">${escapeHtml(s.openTitle)}</h2>
    <form id="openForm"><label for="openName" data-s="openName">${escapeHtml(s.openName)}</label><input id="openName" autocomplete="name" required maxlength="80">
    <label for="openPhone" data-s="openPhone">${escapeHtml(s.openPhone)}</label><input id="openPhone" type="tel" autocomplete="tel" inputmode="tel" maxlength="30">
    <div class="row"><button class="btn primary" data-s="openContinue">${escapeHtml(s.openContinue)}</button></div></form>
    <p id="openErr" class="notice" hidden></p>
  </div>
  <section id="updates" aria-live="polite"></section>
  <div id="invalid" class="notice" hidden data-s="invalid">${escapeHtml(s.invalid)}</div>
  <section id="events" aria-label="Events"></section>
  ${photos.length ? `<section class="card"><div class="gal">${photos.map((u) => `<img src="${escapeHtml(u)}" alt="" loading="lazy" decoding="async">`).join('')}</div></section>` : ''}
  <section id="rsvp" class="card" hidden></section>
  <section id="menu" class="card" hidden></section>
  <nav id="more" class="row" style="justify-content:center"></nav>
  ${input.planner ? `<footer>${input.planner.logo_url ? `<img src="${escapeHtml(input.planner.logo_url)}" alt="" style="height:40px;display:block;margin:0 auto 6px">` : ''}${escapeHtml(input.planner.name)}</footer>` : ''}
  ${showBranding && !input.planner ? `<footer><a href="${escapeHtml(input.signupUrl)}" data-s="madeWith">${escapeHtml(s.madeWith)}</a></footer>` : ''}
</main>
${inv.music_url ? `<button id="music" aria-label="Music" hidden>♪</button><audio id="audio" src="${escapeHtml(inv.music_url)}" loop preload="none"></audio>` : ''}
<script id="data" type="application/json">${jsonForScript(pageData)}</script>
<script>${GUEST_JS}</script>
</body>
</html>`;
}

// Client script. Kept dependency-free and small; it runs on cheap Android phones over 3G.
const GUEST_JS = String.raw`
(function(){
var D=JSON.parse(document.getElementById('data').textContent);
var lang=D.lang, S=D.strings[lang], G=null, token=null;
try{var saved=localStorage.getItem('lang:'+D.slug);if(saved&&D.strings[saved]){lang=saved;S=D.strings[lang];}}catch(e){}
var $=function(id){return document.getElementById(id)};
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function t(k,v){var s=S[k]||D.strings.en[k]||k;if(v)for(var x in v)s=s.split('{'+x+'}').join(v[x]);return s}
function evName(e){return e.name||D.eventNames[lang][e.kind]||D.eventNames.en[e.kind]}
function fmtDate(iso){var d=new Date(iso);var loc=lang==='si'?'si-LK':lang==='ta'?'ta-LK':'en-GB';
 try{return d.toLocaleString(loc,{weekday:'long',day:'numeric',month:'long',year:'numeric',hour:'numeric',minute:'2-digit',timeZone:'Asia/Colombo'})}catch(e){return d.toUTCString()}}
function ics(e){var f=function(d){return new Date(d).toISOString().replace(/[-:]/g,'').replace(/\.\d+/,'')};
 var end=e.ends_at||new Date(new Date(e.starts_at).getTime()+3*36e5).toISOString();
 var body=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//wedding//EN','BEGIN:VEVENT','UID:'+e.id+'@wedding','DTSTAMP:'+f(new Date()),'DTSTART:'+f(e.starts_at),'DTEND:'+f(end),'SUMMARY:'+(D.couple+' - '+evName(e)).replace(/[,;]/g,' '),'LOCATION:'+String(e.venue||'').replace(/[,;]/g,' '),'END:VEVENT','END:VCALENDAR'].join('\r\n');
 return 'data:text/calendar;charset=utf-8,'+encodeURIComponent(body)}
function maps(e){return e.maps_url||('https://www.google.com/maps/search/?api=1&query='+encodeURIComponent([e.venue,e.address].filter(Boolean).join(', ')))}
function myEvents(){return G?D.events.filter(function(e){return G.events.indexOf(e.id)>=0}):D.events}

function applyStatic(){document.documentElement.lang=lang;
 document.querySelectorAll('[data-s]').forEach(function(el){el.textContent=t(el.getAttribute('data-s'))});
 document.querySelectorAll('.lang button').forEach(function(b){b.setAttribute('aria-pressed',b.getAttribute('data-lang')===lang)})}

function renderEvents(){var h='';myEvents().forEach(function(e){
 h+='<article class="card event"><h3>'+esc(evName(e))+'</h3><div>'+esc(fmtDate(e.starts_at))+'</div>'+
 (e.nekath?'<div class="muted">'+esc(e.nekath)+'</div>':'')+
 (e.venue?'<div><b>'+esc(e.venue)+'</b>'+(e.address?'<br><span class="muted">'+esc(e.address)+'</span>':'')+'</div>':'')+
 (e.dress_code?'<div><span class="muted">'+esc(t('dressCode'))+':</span> '+esc(e.dress_code)+'</div>':'')+
 (G&&G.tables&&G.tables[e.id]?'<p class="notice"><b>'+esc(t('table'))+': '+esc(G.tables[e.id])+'</b></p>':'')+
 (e.programme&&e.programme.length?'<h4>'+esc(t('programme'))+'</h4><ul class="prog">'+e.programme.map(function(p){return '<li><b>'+esc(p.time)+'</b><span>'+esc(p.item)+'</span></li>'}).join('')+'</ul>':'')+
 '<div class="row">'+(e.venue||e.address||e.maps_url?'<a class="btn" target="_blank" rel="noopener" href="'+esc(maps(e))+'">'+esc(t('directions'))+'</a>':'')+
 '<a class="btn" download="invitation.ics" href="'+ics(e)+'">'+esc(t('calendar'))+'</a></div></article>'});
 $('events').innerHTML=h}

var timer;function countdown(){var evs=myEvents();if(!evs.length)return;var target=new Date(evs[0].starts_at).getTime();
 function tick(){var ms=target-Date.now();if(ms<=0){$('cd').innerHTML='';clearInterval(timer);return}
  var d=Math.floor(ms/864e5),h=Math.floor(ms%864e5/36e5),m=Math.floor(ms%36e5/6e4);
  $('cd').innerHTML='<div><b>'+d+'</b>'+esc(t('days'))+'</div><div><b>'+h+'</b>'+esc(t('hours'))+'</div><div><b>'+m+'</b>'+esc(t('minutes'))+'</div>'}
 clearInterval(timer);tick();timer=setInterval(tick,30000)}

var draft={};
function renderRsvp(sent){var box=$('rsvp');if(!G){box.hidden=true;return}box.hidden=false;
 if(sent){box.innerHTML='<p class="notice">'+esc(t('thanks'))+'</p><div class="row"><button class="btn" id="chg">'+esc(t('change'))+'</button></div>';$('chg').onclick=function(){renderRsvp(false)};return}
 var h='<h2>'+esc(t('rsvp'))+'</h2><p class="muted">'+esc(t('seatsFor',{n:G.seats}))+'</p><form id="rf">';
 myEvents().forEach(function(e){var r=draft[e.id]||G.rsvps[e.id]||{};draft[e.id]=r;
  h+='<fieldset style="border:0;padding:0;margin:16px 0"><legend><b>'+esc(evName(e))+'</b></legend><div class="row" role="group">';
  [['coming','coming'],['not_coming','notComing'],['maybe','maybe']].forEach(function(o){h+='<button type="button" class="btn" data-ev="'+e.id+'" data-st="'+o[0]+'" aria-pressed="'+(r.status===o[0])+'">'+esc(t(o[1]))+'</button>'});
  h+='</div><div data-more="'+e.id+'"'+(r.status==='coming'||r.status==='maybe'?'':' hidden')+'><label for="hc-'+e.id+'">'+esc(t('howMany'))+'</label><select id="hc-'+e.id+'" data-hc="'+e.id+'">';
  for(var i=1;i<=G.seats;i++)h+='<option'+((r.headcount||G.seats)===i?' selected':'')+'>'+i+'</option>';
  h+='</select>';
  if(D.meals){h+='<label for="ml-'+e.id+'">'+esc(t('meal'))+'</label><select id="ml-'+e.id+'" data-ml="'+e.id+'">';
   [['','mealAny'],['vegetarian','mealVeg'],['vegan','mealVegan'],['halal','mealHalal']].forEach(function(m){h+='<option value="'+m[0]+'"'+((r.meal||'')===m[0]?' selected':'')+'>'+esc(t(m[1]))+'</option>'});h+='</select>'}
  h+='</div></fieldset>'});
 var any=Object.keys(G.rsvps)[0]?G.rsvps[Object.keys(G.rsvps)[0]]:{};
 h+='<label for="diet">'+esc(t('dietary'))+'</label><input id="diet" maxlength="200" value="'+esc(any.dietary||'')+'">';
 h+='<label for="note">'+esc(t('message'))+'</label><textarea id="note" maxlength="1000">'+esc(any.message||'')+'</textarea>';
 h+='<div class="row"><button class="btn primary" id="send">'+esc(t('send'))+'</button></div><p id="rerr" class="notice" hidden></p></form>';
 box.innerHTML=h;
 box.querySelectorAll('[data-st]').forEach(function(b){b.onclick=function(){var id=b.getAttribute('data-ev');draft[id].status=b.getAttribute('data-st');
  box.querySelectorAll('[data-ev="'+id+'"]').forEach(function(x){x.setAttribute('aria-pressed',x===b)});
  box.querySelector('[data-more="'+id+'"]').hidden=draft[id].status==='not_coming'}});
 $('rf').onsubmit=function(ev){ev.preventDefault();var resp=[];myEvents().forEach(function(e){var r=draft[e.id];if(!r.status)return;
  var hc=box.querySelector('[data-hc="'+e.id+'"]'),ml=box.querySelector('[data-ml="'+e.id+'"]');
  resp.push({event_id:e.id,status:r.status,headcount:r.status==='not_coming'?0:Number(hc.value),meal:ml?ml.value||null:null})});
  if(!resp.length)return;
  var body={token:token,responses:resp,dietary:$('diet').value||null,message:$('note').value||null};
  if(D.preview){renderRsvp(true);return}
  $('send').disabled=true;
  fetch(D.api+'/public/rsvp',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}).then(function(r){if(!r.ok)throw 0;return r.json()}).then(function(j){G=j.guest;draft={};renderRsvp(true)}).catch(function(){var e=$('rerr');e.textContent=t('error');e.hidden=false;$('send').disabled=false})}}

function renderExtras(){
 var u=$('updates');u.innerHTML=D.updates.length?'<div class="card"><h2>'+esc(t('updatesTitle'))+'</h2>'+D.updates.map(function(x){return '<p class="notice"><b>'+esc(new Date(x.created_at).toLocaleString(lang==='si'?'si-LK':lang==='ta'?'ta-LK':'en-GB',{day:'numeric',month:'short',hour:'numeric',minute:'2-digit',timeZone:'Asia/Colombo'}))+'</b><br>'+esc(x.body)+'</p>'}).join('')+'</div>':'';
 var m=$('menu');if(D.menu.length){m.hidden=false;var h='<h2>'+esc(t('menuTitle'))+'</h2>',c=null;D.menu.forEach(function(i){if(i.course&&i.course!==c){c=i.course;h+='<h3>'+esc(c)+'</h3>'}h+='<p><b>'+esc(i.name)+'</b>'+(i.diet&&i.diet.length?' <span class="muted">('+esc(i.diet.join(', '))+')</span>':'')+(i.note?'<br>'+esc(i.note):'')+(i.allergens&&i.allergens.length?'<br><span class="muted">Contains: '+esc(i.allergens.join(', '))+'</span>':'')+'</p>'});m.innerHTML=h}
 var n=$('more'),l='';if(D.features.uploads)l+='<a class="btn" href="share.html'+(token&&token!=='preview'?'#t='+encodeURIComponent(token):'')+'">'+esc(t('sharePhotos'))+'</a>';
 if(D.features.seating&&!(G&&G.tables))l+='<a class="btn" href="seat.html">'+esc(t('findSeat'))+'</a>';n.innerHTML=l}
function renderAll(){applyStatic();renderExtras();if(G){var d=$('dear');d.textContent=t('dear',{name:G.name});d.hidden=false}renderEvents();countdown();renderRsvp(false)}

document.querySelectorAll('.lang button').forEach(function(b){b.onclick=function(){lang=b.getAttribute('data-lang');S=D.strings[lang];try{localStorage.setItem('lang:'+D.slug,lang)}catch(e){}renderAll()}});

var cover=$('cover'),audio=$('audio'),mbtn=$('music');
function openCover(){if(cover){cover.classList.add('open');setTimeout(function(){cover.hidden=true},950)}if(audio){audio.play().then(function(){mbtn.hidden=false}).catch(function(){mbtn.hidden=false})}}
if(cover){cover.onclick=openCover;cover.onkeydown=function(e){if(e.key==='Enter'||e.key===' ')openCover()}}
else if(audio){mbtn.hidden=false}
if(mbtn)mbtn.onclick=function(){if(audio.paused)audio.play();else audio.pause()};

function loadGuest(tok){token=tok;
 return fetch('g/'+encodeURIComponent(tok)+'.json',{cache:'no-cache'}).then(function(r){if(!r.ok)throw 0;return r.json()}).then(function(g){G=g;renderAll();
  // Count an "open" only from a real browser running this script, never from link-preview crawlers.
  try{if(!sessionStorage.getItem('o:'+tok)){sessionStorage.setItem('o:'+tok,'1');fetch(D.api+'/public/open',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token:tok}),keepalive:true})}}catch(e){}
 }).catch(function(){G=null;$('invalid').hidden=false;renderAll()})}

var hash=new URLSearchParams(location.hash.slice(1));
if(D.preview){G=D.preview;token='preview';renderAll()}
else if(hash.get('t')){loadGuest(hash.get('t'))}
else if(hash.get('o')&&D.hasOpenLink){renderAll();$('open').hidden=false;
 $('openForm').onsubmit=function(ev){ev.preventDefault();
  fetch(D.api+'/public/claim',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({slug:D.slug,open:hash.get('o'),name:$('openName').value,phone:$('openPhone').value})})
  .then(function(r){return r.json().then(function(j){if(!r.ok)throw j;return j})}).then(function(j){$('open').hidden=true;history.replaceState(null,'','#t='+j.token);loadGuest(j.token)})
  .catch(function(){var e=$('openErr');e.textContent=t('openNotFound');e.hidden=false})}}
else renderAll();
})();
`;
