// Companion guest pages, plain HTML + a little JavaScript, in the wedding's design:
//   share.html     guests upload photos/videos, write or record a guestbook message, request a song
//   wall.html      live photo wall for a screen at the reception
//   seat.html      "Find your seat" (from the QR board at the entrance)
//   keepsake.html  after the wedding: album + guestbook
import { escapeHtml } from './util.ts';
import type { RenderInput } from './renderer.ts';

type Page = 'share' | 'wall' | 'seat' | 'keepsake';

const T: Record<string, Record<string, string>> = {
  en: {
    share: 'Share the day', name: 'Your name', photos: 'Photos & videos', choose: 'Choose photos or videos', uploading: 'Uploading', done: 'Thank you! Uploaded.',
    pending: 'The couple will add them to the photo wall soon.', guestbook: 'Guestbook', message: 'Your message to the couple', record: 'Record a voice note', stop: 'Stop recording',
    send: 'Send', sent: 'Thank you! Your message was sent.', song: 'Request a song', songName: 'Song and artist', failed: 'Something went wrong. Please try again.',
    seat: 'Find your seat', typeName: 'Type your name', search: 'Search', notFound: 'We could not find that name. Please ask at the entrance.', table: 'Table',
    keepsake: 'Our wedding album', wishes: 'Your wishes', scan: 'Scan to share your photos', report: 'Report', back: 'Back to the invitation',
    big: 'That file is too large.', closed: 'Uploads are closed.',
  },
  si: {
    share: 'දවස බෙදාගන්න', name: 'ඔබේ නම', photos: 'ඡායාරූප සහ වීඩියෝ', choose: 'ඡායාරූප හෝ වීඩියෝ තෝරන්න', uploading: 'උඩුගත වෙමින්', done: 'ස්තූතියි! උඩුගත කළා.',
    pending: 'යුවළ ඉක්මනින් ඒවා ඡායාරූප බිත්තියට එක් කරයි.', guestbook: 'සුබපැතුම් පොත', message: 'යුවළට ඔබේ පණිවිඩය', record: 'හඬ පණිවිඩයක් පටිගත කරන්න', stop: 'නවත්වන්න',
    send: 'යවන්න', sent: 'ස්තූතියි! ඔබේ පණිවිඩය යැව්වා.', song: 'ගීතයක් ඉල්ලන්න', songName: 'ගීතය සහ ගායකයා', failed: 'දෝෂයක්. නැවත උත්සාහ කරන්න.',
    seat: 'ඔබේ ආසනය සොයන්න', typeName: 'ඔබේ නම ටයිප් කරන්න', search: 'සොයන්න', notFound: 'එම නම හමු නොවීය. ඇතුල්වීමේදී විමසන්න.', table: 'මේසය',
    keepsake: 'අපේ විවාහ ඇල්බමය', wishes: 'ඔබේ සුබපැතුම්', scan: 'ඡායාරූප බෙදාගැනීමට ස්කෑන් කරන්න', report: 'වාර්තා කරන්න', back: 'ආරාධනාවට ආපසු',
    big: 'ගොනුව විශාල වැඩියි.', closed: 'උඩුගත කිරීම වසා ඇත.',
  },
  ta: {
    share: 'நாளைப் பகிருங்கள்', name: 'உங்கள் பெயர்', photos: 'புகைப்படங்கள் & வீடியோக்கள்', choose: 'புகைப்படங்கள் அல்லது வீடியோக்களைத் தேர்ந்தெடுக்கவும்', uploading: 'பதிவேற்றுகிறது', done: 'நன்றி! பதிவேற்றப்பட்டது.',
    pending: 'தம்பதியினர் விரைவில் அவற்றைப் புகைப்படச் சுவரில் சேர்ப்பார்கள்.', guestbook: 'வாழ்த்துப் புத்தகம்', message: 'தம்பதியினருக்கு உங்கள் வாழ்த்து', record: 'குரல் செய்தியைப் பதிவு செய்', stop: 'நிறுத்து',
    send: 'அனுப்பு', sent: 'நன்றி! உங்கள் வாழ்த்து அனுப்பப்பட்டது.', song: 'பாடலைக் கோருங்கள்', songName: 'பாடல் மற்றும் பாடகர்', failed: 'பிழை. மீண்டும் முயற்சிக்கவும்.',
    seat: 'உங்கள் இருக்கையைக் காண்க', typeName: 'உங்கள் பெயரைத் தட்டச்சு செய்யவும்', search: 'தேடு', notFound: 'அந்தப் பெயர் கிடைக்கவில்லை. நுழைவாயிலில் கேளுங்கள்.', table: 'மேசை',
    keepsake: 'எங்கள் திருமண ஆல்பம்', wishes: 'உங்கள் வாழ்த்துகள்', scan: 'புகைப்படங்களைப் பகிர ஸ்கேன் செய்யவும்', report: 'புகார்', back: 'அழைப்பிதழுக்குத் திரும்பு',
    big: 'கோப்பு மிகப் பெரியது.', closed: 'பதிவேற்றம் மூடப்பட்டது.',
  },
};

function shell(input: RenderInput, title: string, body: string, script: string, dark = false) {
  const p = input.template.layout.palette;
  const lang = input.wedding.language;
  const bg = dark ? '#111' : p.bg, ink = dark ? '#f4f1ea' : p.ink, surface = dark ? '#1c1c1c' : p.surface;
  const data = JSON.stringify({ slug: input.wedding.slug, api: input.apiUrl, s: T[lang] ?? T.en, en: T.en }).replace(/</g, '\\u003c');
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · ${escapeHtml(input.wedding.partner1)} & ${escapeHtml(input.wedding.partner2)}</title><meta name="robots" content="noindex">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@600&family=Inter:wght@400;600&family=Noto+Sans+Sinhala:wght@400;600&family=Noto+Sans+Tamil:wght@400;600&display=swap">
<style>:root{--bg:${bg};--ink:${ink};--accent:${p.accent};--surface:${surface};--muted:${dark ? '#bbb' : p.muted}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:1rem/1.6 Inter,'Noto Sans Sinhala','Noto Sans Tamil',system-ui,sans-serif}
main{max-width:640px;margin:0 auto;padding:24px 16px 48px}h1,h2{font-family:'Cormorant Garamond','Noto Sans Sinhala','Noto Sans Tamil',serif;line-height:1.2}h1{text-align:center;font-size:2.2rem;margin:.2em 0}
.card{background:var(--surface);border-radius:14px;padding:18px;margin:16px 0;box-shadow:0 1px 3px rgba(0,0,0,.08)}
label{display:block;font-weight:600;margin:12px 0 6px}input,textarea{width:100%;min-height:48px;padding:10px 12px;border:1.5px solid var(--muted);border-radius:10px;font:inherit;background:var(--surface);color:var(--ink)}textarea{min-height:90px}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:10px 18px;border-radius:24px;border:2px solid var(--accent);background:transparent;color:var(--ink);font:inherit;font-weight:600;cursor:pointer;text-decoration:none}
.btn.primary{background:var(--accent);color:var(--surface)}.btn:disabled{opacity:.5}.row{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.muted{color:var(--muted)}.notice{padding:12px;border-radius:10px;border-left:4px solid var(--accent);background:var(--surface)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}.grid img,.grid video{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px;display:block}
[hidden]{display:none!important}.center{text-align:center}</style></head><body>${body}
<script id="d" type="application/json">${data}</script><script>var D=JSON.parse(document.getElementById('d').textContent),S=D.s;function t(k){return S[k]||D.en[k]}
function $(i){return document.getElementById(i)}function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function api(p,b){return fetch(D.api+p,{method:b?'POST':'GET',headers:b?{'content-type':'application/json'}:{},body:b?JSON.stringify(b):undefined}).then(function(r){return r.json().then(function(j){if(!r.ok)throw j;return j})})}
document.querySelectorAll('[data-t]').forEach(function(e){e.textContent=t(e.getAttribute('data-t'))});document.querySelectorAll('[data-ph]').forEach(function(e){e.placeholder=t(e.getAttribute('data-ph'))});
${script}</script></body></html>`;
}

export function renderExtraPage(page: Page, input: RenderInput): string {
  const couple = `${escapeHtml(input.wedding.partner1)} &amp; ${escapeHtml(input.wedding.partner2)}`;
  const s = T[input.wedding.language] ?? T.en;
  if (page === 'share') {
    return shell(input, s.share, `<main><h1>${couple}</h1><p class="center muted" data-t="share"></p>
<div class="card"><label for="nm" data-t="name"></label><input id="nm" maxlength="60" autocomplete="name"></div>
<div class="card"><h2 data-t="photos"></h2><input id="files" type="file" accept="image/*,video/*" multiple hidden>
<button class="btn primary" id="pick" data-t="choose"></button><p id="up" class="muted" aria-live="polite"></p></div>
<div class="card"><h2 data-t="guestbook"></h2><label for="msg" data-t="message"></label><textarea id="msg" maxlength="1500"></textarea>
<div class="row"><button class="btn" id="rec" data-t="record"></button><audio id="play" controls hidden></audio></div>
<div class="row"><button class="btn primary" id="sendMsg" data-t="send"></button></div><p id="gb" class="notice" hidden aria-live="polite"></p></div>
<div class="card"><h2 data-t="song"></h2><label for="sg" data-t="songName"></label><input id="sg" maxlength="150"><div class="row"><button class="btn primary" id="sendSong" data-t="send"></button></div><p id="sn" class="notice" hidden></p></div>
<p class="center"><a class="btn" href="./" data-t="back"></a></p></main>`, String.raw`
var tok=new URLSearchParams(location.hash.slice(1)).get('t');if(tok)document.querySelector('a[href="./"]').href='./#t='+encodeURIComponent(tok);
try{$('nm').value=localStorage.getItem('nm:'+D.slug)||''}catch(e){}
$('nm').onchange=function(){try{localStorage.setItem('nm:'+D.slug,$('nm').value)}catch(e){}};
// Phones shrink photos before upload (max 2000px, JPEG): faster on weak connections and cheaper to store.
function shrink(f){return new Promise(function(res){if(!/^image\/(jpeg|png|webp)$/.test(f.type))return res(f);var img=new Image();img.onload=function(){var k=Math.min(1,2000/Math.max(img.width,img.height));if(k===1&&f.size<2e6){URL.revokeObjectURL(img.src);return res(f)}
var c=document.createElement('canvas');c.width=Math.round(img.width*k);c.height=Math.round(img.height*k);c.getContext('2d').drawImage(img,0,0,c.width,c.height);URL.revokeObjectURL(img.src);c.toBlob(function(b){res(b?new File([b],'photo.jpg',{type:'image/jpeg'}):f)},'image/jpeg',.85)};img.onerror=function(){res(f)};img.src=URL.createObjectURL(f)})}
function upload(f){return api('/public/uploads',{slug:D.slug,content_type:f.type,size:f.size,name:$('nm').value,token:tok}).then(function(u){
 return fetch(u.upload_url,{method:'PUT',headers:{'content-type':f.type},body:f}).then(function(r){if(!r.ok)throw 0;return api('/public/uploads/'+u.id+'/complete',{upload_token:u.upload_token})}).then(function(c){c.id=u.id;return c})})}
$('pick').onclick=function(){$('files').click()};
$('files').onchange=async function(){var fs=[].slice.call(this.files),ok=0,pend=false;for(var i=0;i<fs.length;i++){$('up').textContent=t('uploading')+' '+(i+1)+' / '+fs.length+'…';
 try{var c=await upload(await shrink(fs[i]));ok++;if(c.status==='pending')pend=true}catch(e){$('up').textContent=(e&&e.error==='too_large')?t('big'):(e&&e.error==='uploads_closed')?t('closed'):t('failed');return}}
 $('up').textContent=t('done')+(pend?' '+t('pending'):'');this.value=''};
var rec=null,chunks=[],voice=null;
if(!window.MediaRecorder)$('rec').hidden=true;
$('rec').onclick=async function(){if(rec){rec.stop();return}try{var st=await navigator.mediaDevices.getUserMedia({audio:true});chunks=[];
 var type=['audio/webm','audio/mp4','audio/ogg'].filter(function(x){return MediaRecorder.isTypeSupported(x)})[0];rec=new MediaRecorder(st,type?{mimeType:type}:{});
 rec.ondataavailable=function(e){chunks.push(e.data)};rec.onstop=function(){st.getTracks().forEach(function(x){x.stop()});var mt=(rec.mimeType||'audio/webm').split(';')[0];voice=new File(chunks,'voice',{type:mt});$('play').src=URL.createObjectURL(voice);$('play').hidden=false;rec=null;$('rec').textContent=t('record')};
 rec.start();$('rec').textContent=t('stop');setTimeout(function(){if(rec)rec.stop()},120000)}catch(e){$('rec').hidden=true}};
$('sendMsg').onclick=async function(){if(!$('nm').value.trim()){$('nm').focus();return}var b=this;b.disabled=true;try{var id=null;if(voice){id=(await upload(voice)).id}
 await api('/public/guestbook',{slug:D.slug,name:$('nm').value,message:$('msg').value||null,upload_id:id});$('gb').textContent=t('sent');$('msg').value='';voice=null;$('play').hidden=true}catch(e){$('gb').textContent=t('failed')}$('gb').hidden=false;b.disabled=false};
$('sendSong').onclick=function(){if(!$('sg').value.trim())return;api('/public/songs',{slug:D.slug,name:$('nm').value,song:$('sg').value}).then(function(){$('sn').textContent=t('sent');$('sg').value=''}).catch(function(){$('sn').textContent=t('failed')}).then(function(){$('sn').hidden=false})};
`);
  }
  if (page === 'wall') {
    return shell(input, 'Photo wall', `<style>main{max-width:none;padding:16px}.grid{grid-template-columns:repeat(auto-fill,minmax(220px,1fr))}#hero{max-height:70vh;width:100%;object-fit:contain;display:block;margin:0 auto 16px;border-radius:12px}
.top{display:flex;align-items:center;justify-content:space-between;gap:16px}.qr{background:#fff;padding:8px;border-radius:8px;text-align:center;color:#222;font-size:.85rem}.qr svg{width:140px;height:140px;display:block}</style>
<main><div class="top"><h1>${couple}</h1><div class="qr"><div id="qr"></div><span data-t="scan"></span></div></div><img id="hero" alt="" hidden><div class="grid" id="g"></div></main>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcode-generator/1.4.4/qrcode.min.js"></script>`, String.raw`
try{var q=qrcode(0,'M');q.addData(location.href.replace(/wall\.html.*$/,'share.html'));q.make();$('qr').innerHTML=q.createSvgTag({cellSize:4,margin:1})}catch(e){}
var items=[],i=0;function draw(){$('g').innerHTML=items.slice(0,24).map(function(x){return x.kind==='video'?'<video src="'+esc(x.url)+'" muted autoplay loop playsinline></video>':'<img src="'+esc(x.url)+'" alt="" loading="lazy">'}).join('')}
function poll(){api('/public/wall?slug='+encodeURIComponent(D.slug)).then(function(r){items=r.items;draw()}).catch(function(){})}
setInterval(function(){var ph=items.filter(function(x){return x.kind==='photo'});if(!ph.length)return;var h=$('hero');h.src=ph[i++%ph.length].url;h.hidden=false},6000);
poll();setInterval(poll,10000);`, true);
  }
  if (page === 'seat') {
    return shell(input, s.seat, `<main><h1>${couple}</h1><div class="card"><h2 data-t="seat"></h2><form id="f"><label for="n" data-t="typeName"></label><input id="n" autocomplete="name" required minlength="3" maxlength="80">
<div class="row"><button class="btn primary" data-t="search"></button></div></form><div id="r" aria-live="polite"></div></div></main>`, String.raw`
$('f').onsubmit=function(e){e.preventDefault();api('/public/find-seat',{slug:D.slug,name:$('n').value}).then(function(j){
 $('r').innerHTML=j.matches.length?j.matches.map(function(m){return '<p class="notice"><b>'+esc(m.name)+'</b><br><span style="font-size:1.6rem">'+esc(t('table'))+': '+esc(m.table)+'</span></p>'}).join(''):'<p class="notice">'+esc(t('notFound'))+'</p>'})
 .catch(function(){$('r').innerHTML='<p class="notice">'+esc(t('failed'))+'</p>'})};`);
  }
  return shell(input, s.keepsake, `<main><h1>${couple}</h1><p class="center muted" data-t="keepsake"></p><div class="grid" id="g"></div>
<h2 data-t="wishes"></h2><div id="b"></div></main>`, String.raw`
api('/public/keepsake?slug='+encodeURIComponent(D.slug)).then(function(r){
 $('g').innerHTML=r.photos.map(function(x){return x.kind==='video'?'<video src="'+esc(x.url)+'" controls preload="none"></video>':'<a href="'+esc(x.url)+'" target="_blank" rel="noopener"><img src="'+esc(x.url)+'" alt="" loading="lazy"></a>'}).join('');
 $('b').innerHTML=r.guestbook.map(function(e){return '<div class="card"><b>'+esc(e.name)+'</b>'+(e.message?'<p>'+esc(e.message)+'</p>':'')+(e.voice_url?'<audio controls preload="none" src="'+esc(e.voice_url)+'"></audio>':'')+'</div>'}).join('')}).catch(function(){$('g').innerHTML='<p>'+esc(t('failed'))+'</p>'});`);
}
