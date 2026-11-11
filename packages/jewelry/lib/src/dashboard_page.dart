/// The dashboard's single page: no build step, no dependencies. It polls
/// `state.json` every second and each emulator's screen as fast as the
/// screenshots come.
const dashboardPage = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>jewelry</title>
<link rel="icon" type="image/svg+xml" href="logo.svg">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#f6f5f2;--panel:#fff;--ink:#1d1b19;--dim:#7a756d;--line:#e4e0d8;
--ok:#1f8a4c;--bad:#c4372f;--run:#c98a0c;--rec:#3d6fb6}
*{box-sizing:border-box}
body{margin:0;font:14px/1.4 -apple-system,system-ui,sans-serif;color:var(--ink);background:var(--bg);
display:grid;grid-template-columns:320px 1fr;height:100vh}
aside{border-right:1px solid var(--line);background:var(--panel);overflow:auto}
header{padding:14px 16px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--panel)}
header h1{font-size:15px;margin:0 0 4px;display:flex;align-items:center;gap:8px}
header h1 img{width:24px;height:24px}
.counts{color:var(--dim);font-size:12px}
.bar{height:4px;background:var(--line);border-radius:2px;margin-top:8px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--ok)}
ul{list-style:none;margin:0;padding:6px 0}
li{display:flex;gap:8px;align-items:center;padding:7px 16px;cursor:pointer}
li:hover{background:#f1efe9} li.sel{background:#ebe7dd}
li .name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
li .t{color:var(--dim);font-size:12px;font-variant-numeric:tabular-nums}
.dot{width:10px;height:10px;border-radius:50%;flex:none;background:var(--line)}
.passed .dot,.failed .dot{background:none;border-radius:0;width:12px;height:auto;font-weight:700;font-size:13px;line-height:1;text-align:center}
.passed .dot::after{content:'✓';color:var(--ok)} .failed .dot::after{content:'✗';color:var(--bad)}
.recorded .dot{background:var(--rec)}
.running .dot,.judging .dot{background:var(--run);animation:p 1s infinite alternate}
@keyframes p{to{opacity:.3}}
main{overflow:auto;padding:18px 22px}
main h2{font-size:16px;margin:0 0 14px;display:flex;gap:12px;align-items:baseline}
main h2 a{font-size:13px;font-weight:normal;color:var(--rec);cursor:pointer}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;display:flex;gap:14px;align-items:flex-start}
.screen{position:relative;width:180px;aspect-ratio:1344/2992;flex:none}
.screen img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;border-radius:10px;opacity:0;transition:opacity .4s}
.screen.on img{opacity:1}
.loader{position:absolute;inset:0;border-radius:18px;border:2px solid #d9d4c8;padding:14px;display:flex;flex-direction:column;
align-items:center;justify-content:center;gap:10px;text-align:center;color:var(--dim);font-size:12px;
background:linear-gradient(110deg,#efece5 35%,#faf8f4 50%,#efece5 65%);background-size:250% 100%;animation:shimmer 1.8s linear infinite}
.loader:before{content:"";position:absolute;top:9px;left:50%;width:34px;height:6px;margin-left:-17px;border-radius:3px;background:#d9d4c8}
.loader b{color:var(--ink);font-size:13px}
.spin{width:30px;height:30px;border-radius:50%;border:3px solid #ddd8cd;border-top-color:var(--run);animation:spin .9s linear infinite}
.screen.on .loader{display:none}
.card.stopped .loader{animation:none;background:#efece5}
.card.failed .loader b{color:var(--bad)} .card.failed .loader span{white-space:pre-wrap;word-break:break-word;text-align:left;font-size:11px}.card.stopped .spin{border-top-color:#ddd8cd;animation:none}
@keyframes shimmer{to{background-position:-250% 0}}@keyframes spin{to{transform:rotate(360deg)}}
.card .info{flex:1;min-width:0}
.card .who{color:var(--dim);font-size:12px}
.card .test{font-weight:600;margin:2px 0 8px}
ol{margin:0;padding:0;list-style:none;font-size:13px}
ol li{padding:2px 0;cursor:default;display:block}
ol li.done{color:var(--dim)} ol li.done:before{content:"✓ ";color:var(--ok)}
ol li.now{font-weight:600} ol li.now:before{content:"▶ ";color:var(--run)}
ol li.next:before{content:"○ ";color:var(--line)}
.detail .reason{color:var(--bad);font-weight:600;margin:0 0 6px}
.detail pre{white-space:pre-wrap;background:var(--panel);border:1px solid var(--line);padding:10px;border-radius:8px;font-size:12px}
.media{display:flex;gap:16px;flex-wrap:wrap;margin:14px 0}
.media figure{margin:0} .media figcaption{color:var(--dim);font-size:12px;margin-bottom:4px}
.media video,.media img{width:260px;border-radius:8px;border:1px solid var(--line);background:#111}
.empty{color:var(--dim)}
.player{display:flex;gap:16px;align-items:flex-start}
.player>div:first-child{width:300px}
.player ol.steps{width:250px;margin-top:20px;max-height:640px;overflow:auto}
ol.steps li{cursor:pointer;padding:3px 6px;border-radius:5px}
ol.steps li:hover{background:#ebe7dd}
ol.steps li.now{background:#f3ead6}
ol.steps li.bad{color:var(--bad)} ol.steps li.bad:before{content:"✗ ";color:var(--bad)}
ol.steps li.off:after{content:" ◷";color:#e8a33c}
.player video{width:300px;display:block;border-radius:8px 8px 0 0;border:1px solid var(--line);background:#111}
.ctrl{display:flex;align-items:center;gap:8px;margin:6px 0 4px;font-size:12px;color:var(--dim);font-variant-numeric:tabular-nums}
.ctrl button{border:0;background:var(--ink);color:#fff;border-radius:50%;width:26px;height:26px;cursor:pointer;font-size:11px}
.track{position:relative;height:18px;border-radius:4px;overflow:hidden;background:var(--line);cursor:pointer;touch-action:none}
.band{position:absolute;top:0;bottom:0;border-right:1px solid #fff8}
.band.a{background:#d9d4c8}.band.b{background:#cbc5b7}
.band.off{background:#e8a33c}.band.bad{background:var(--bad)}
.seg{position:absolute;bottom:0;height:5px}
.seg.device{background:#3d6fb6}.seg.wait{background:repeating-linear-gradient(45deg,#0003 0 3px,transparent 3px 6px);height:100%}
.tick{position:absolute;top:0;width:2px;height:7px;background:#fff}
.head{position:absolute;top:-2px;bottom:-2px;width:3px;margin-left:-1px;background:var(--ink);border-radius:2px;pointer-events:none}
.nowstep{font-size:12px;margin-top:5px;min-height:1.4em}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--dim);margin:4px 0 10px}
.legend i{display:inline-block;width:12px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
</style></head><body>
<aside><header><h1><img src="logo.svg" alt="">jewelry</h1><div class="counts" id="counts"></div><div class="bar"><i id="bar"></i></div></header>
<ul id="tests"></ul></aside>
<main id="main"></main>
<script>
let state=null, selected=null;
const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const clock=ms=>{const s=Math.floor(ms/1000);return String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0')};
const screens={};

async function poll(){
  try{state=await (await fetch('state.json')).json();render();}catch(e){$('#counts').textContent='run finished or stopped';}
  setTimeout(poll,1000);
}
// The expected end as a wall-clock time; once past the estimate, it moves with now.
function endTime(){
  const end=new Date(Date.now()+Math.max(0,state.estimateMs-state.elapsedMs));
  return end.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
}
const stateTitle={queued:'Queued',running:'Running',judging:'Being compared',passed:'Passed: matches its golden',failed:'Failed',recorded:'Recorded: a new golden, nothing to compare against'};
function render(){
  const t=state.tests, done=t.filter(x=>['passed','failed','recorded'].includes(x.state));
  const failed=t.filter(x=>x.state==='failed').length;
  $('#counts').textContent=`${done.length}/${t.length} done · ${done.length-failed} ok · ${failed} failed · ${clock(state.elapsedMs)}${state.estimateMs&&done.length<t.length?` · ends ~${endTime()}`:''}`;
  $('#bar').style.width=(t.length?100*done.length/t.length:0)+'%';
  $('#tests').innerHTML=t.map(x=>{
    const ms=x.results[0]?.durationMs; const label=x.labels[0]||x.name;
    return `<li class="${x.state}${selected===x.key?' sel':''}" data-key="${esc(x.key)}"><span class="dot" title="${stateTitle[x.state]||x.state}"></span>
      <span class="name" title="${esc(x.file)}">${esc(label)}</span><span class="t">${ms?clock(ms):x.state==='queued'?'':x.state}</span></li>`;
  }).join('');
  selected?renderDetail():renderLive();
}
$('#tests').onclick=e=>{const li=e.target.closest('li');if(!li)return;selected=li.dataset.key;location.hash=encodeURIComponent(selected);render();};
if(location.hash.length>1)selected=decodeURIComponent(location.hash.slice(1));

function renderLive(){
  const ws=state.workers;
  if(!$('#live')){$('#main').innerHTML='<h2>Live</h2><div class="grid" id="live"></div>';}
  const grid=$('#live');
  for(const w of ws){
    let card=grid.querySelector(`[data-w="${CSS.escape(w.key)}"]`);
    if(!card){card=document.createElement('div');card.className='card';card.dataset.w=w.key;
      card.innerHTML='<div class="screen"><img alt=""><div class="loader"><div class="spin"></div><b></b><span></span></div></div>'
        +'<div class="info"><div class="who"></div><div class="test"></div><ol></ol></div>';
      grid.appendChild(card);}
    const test=state.tests.find(x=>x.key===w.test);
    if(w.live)startScreen(w.key,card.querySelector('img'));
    const [title,sub]=phase(w, test);
    card.querySelector('.loader b').textContent=title;
    card.querySelector('.loader span').textContent=sub;
    card.classList.toggle('stopped',!!w.error||/shutting down|stopped/.test(w.status));
    card.classList.toggle('failed',!!w.error);
    card.querySelector('.who').textContent=`${w.profile} · emulator ${w.worker+1} · ${test?'running':title.toLowerCase()}`;
    card.querySelector('.test').textContent=test?(test.labels[0]||test.name):'';
    const at=w.steps.indexOf(w.step);
    card.querySelector('ol').innerHTML=w.steps.map((s,i)=>`<li class="${i<at?'done':i===at?'now':'next'}">${esc(s)}</li>`).join('');
  }
  if(!ws.length)grid.innerHTML='<p class="empty">No emulator yet.</p>';
}
// What an emulator without a screen yet is doing, as a title and a detail.
function phase(w,test){
  if(w.error)return ['Stopped',w.error];
  const s=w.status||'';
  if(/shutting down/.test(s))return ['Shutting down','Out of scenarios, or stopped early (the run says why at the end)'];
  if(/building/.test(s))return ['Building the app','Once for the whole run'];
  if(/firebase/.test(s))return ['Starting Firebase','Auth and Firestore emulators'];
  if(/booting/.test(s))return ['Booting the emulator','A wiped Android, about a minute'];
  if(/booted/.test(s)&&!test)return ['Waiting','For the build or the next scenario'];
  if(test)return ['Starting the app',test.labels[0]||test.name];
  return ['Starting','']; 
}
function startScreen(key,img){
  if(screens[key])return; screens[key]=true;
  const box=img.parentNode;
  const next=()=>setTimeout(()=>{if(!document.body.contains(img)){delete screens[key];return;}img.src=`screen/${encodeURIComponent(key)}?t=${Date.now()}`},400);
  img.onload=()=>{box.classList.add('on');next();};
  img.onerror=()=>{box.classList.remove('on');setTimeout(next,1500);};
  next();
}

function renderDetail(){
  for(const k in screens)delete screens[k];
  const x=state.tests.find(t=>t.key===selected); if(!x){selected=null;return renderLive();}
  if($('#main').dataset.shown===selected+x.state)return; $('#main').dataset.shown=selected+x.state;
  const prof=encodeURIComponent(x.profile);
  let html=`<h2>${esc(x.labels[0]||x.name)} <a id="back">← live</a></h2><div class="detail">
    <p class="counts">${esc(x.file)} · ${esc(x.profile)} · ${esc(x.state)}</p>`;
  const slugs=x.results.length?x.results.map(r=>r.slug):x.slugs;
  for(const r of x.results){
    if(r.outcome==='failed'){html+=`<p class="reason">${esc(r.reason)}</p>${r.detail?`<pre>${esc(r.detail)}</pre>`:''}`;}
    else html+=`<p>${esc(r.label)}: ${esc(r.outcome)}, ${r.frames} frames, ${clock(r.durationMs)}</p>`;
  }
  html+='<div class="media">';
  for(const s of slugs){
    const name=encodeURIComponent(s);
    const r=x.results.find(r=>r.slug===s);
    html+=player('Golden','golden',name,prof,r);
    if(r&&r.failureDir){
      html+=player('This run','failure',name,prof,r);
      for(const [f,c] of [['expected_frame.png','Expected'],['actual_frame.png','Actual'],['diff.png','Difference']])
        html+=`<figure><figcaption>${c}</figcaption><img src="files/${r.failureDir}/${f}" onerror="this.parentNode.remove()"></figure>`;
    }
  }
  html+='</div>';
  if(x.state==='queued'||x.state==='running')html+='<p class="empty">Not finished yet: the golden plays above when there is one.</p>';
  html+=`<div class="legend"><span><i style="background:var(--bad)"></i>step that failed</span>
    <span><i style="background:#e8a33c"></i>step took a different time than in the golden</span>
    <span><i style="background:#3d6fb6"></i>phone screen (outside the app)</span>
    <span><i style="background:repeating-linear-gradient(45deg,#0004 0 3px,#d9d4c8 3px 6px)"></i>waiting, not compared</span>
    <span><i style="background:#fff;border:1px solid var(--line)"></i>snapshot</span></div>`;
  html+='<p><a href="files/report.html" target="_blank">Full report</a></p></div>';
  $('#main').innerHTML=html;
  initPlayers(x);
  $('#back').onclick=()=>{selected=null;history.replaceState(null,'',location.pathname);$('#main').innerHTML='';$('#main').dataset.shown='';render();};
}
function player(caption,kind,name,prof,r){
  return `<figure class="player" data-kind="${kind}" data-path="${kind}/${name}/${prof}" data-failed="${esc(r&&r.outcome==='failed'?r.step||'':'')}">
    <div><figcaption>${caption}</figcaption><video muted playsinline preload="auto" src="video/${kind}/${name}/${prof}"></video>
    <div class="ctrl"><button>▶</button><span class="time">00:00</span></div>
    <div class="track"><div class="head"></div></div><div class="nowstep"></div></div>
    <ol class="steps"></ol></figure>`;
}
// Seconds per step in a timeline.
const perStep=tl=>tl.reduce((m,r)=>(m[r.step]=(m[r.step]||0)+r.end-r.start,m),{});
async function initPlayers(x){
  const figs=[...document.querySelectorAll('.player')];
  const tls={};
  await Promise.all(figs.map(async f=>{
    try{tls[f.dataset.path]=await (await fetch('timeline/'+f.dataset.path)).json();}
    catch(e){f.remove();}
  }));
  for(const f of figs){
    const tl=tls[f.dataset.path]; if(!tl||!tl.length)continue;
    // The other recording of the same scenario, to see which steps took longer.
    const other=Object.entries(tls).find(([k])=>k!==f.dataset.path&&k.split('/')[1]===f.dataset.path.split('/')[1]);
    const mine=perStep(tl), theirs=other?perStep(other[1]):null;
    setupPlayer(f,tl,mine,theirs,f.dataset.failed);
  }
}
function setupPlayer(f,tl,mine,theirs,failed){
  const v=f.querySelector('video'), track=f.querySelector('.track'), head=f.querySelector('.head');
  const btn=f.querySelector('button'), time=f.querySelector('.time'), now=f.querySelector('.nowstep');
  v.onerror=()=>f.remove();
  const total=tl[tl.length-1].end;
  // Step bands: consecutive runs of one step.
  const bands=[];
  for(const r of tl){const b=bands[bands.length-1]; if(b&&b.step===r.step)b.end=r.end; else bands.push({step:r.step,start:r.start,end:r.end});}
  let html='', list='';
  bands.forEach((b,i)=>{
    const a=mine[b.step], t=theirs?theirs[b.step]:null;
    const off=theirs&&(t===undefined||Math.abs(a-t)>Math.max(0.5,0.25*Math.max(a,t)));
    const cls=b.step===failed?'bad':off?'off':(i%2?'b':'a');
    const why=theirs?` · ${a.toFixed(1)} s here, ${t===undefined?'missing':t.toFixed(1)+' s'} in the other`:` · ${(b.end-b.start).toFixed(1)} s`;
    html+=`<div class="band ${cls}" style="left:${100*b.start/total}%;width:${100*(b.end-b.start)/total}%" title="${esc(b.step+why)}"></div>`;
    list+=`<li data-i="${i}" class="${cls==='bad'||cls==='off'?cls:''}" title="${esc(why.slice(3))}">${esc(b.step)}</li>`;
  });
  // The same steps beside the video, following it; a click jumps there.
  const steps=f.querySelector('ol.steps'); steps.innerHTML=list;
  const items=[...steps.children];
  steps.onclick=e=>{const li=e.target.closest('li');if(!li)return;v.currentTime=toVideo(bands[+li.dataset.i].start)+0.01;show();};
  for(const r of tl){
    if(r.kind!=='app')html+=`<div class="seg ${r.kind}" style="left:${100*r.start/total}%;width:${100*(r.end-r.start)/total}%"></div>`;
    if(r.snapshot)html+=`<div class="tick" style="left:${100*r.start/total}%" title="snapshot: ${esc(r.snapshot)}"></div>`;
  }
  track.insertAdjacentHTML('afterbegin',html);
  // The video's own length can differ from the timeline by a frame or two.
  const toVideo=s=>v.duration?s*v.duration/total:s, toTimeline=s=>v.duration?s*total/v.duration:s;
  const show=()=>{const s=toTimeline(v.currentTime);head.style.left=(100*s/total)+'%';
    time.textContent=`${clock(v.currentTime*1000)} / ${clock((v.duration||total)*1000)}`;
    const r=tl.find(r=>s>=r.start&&s<r.end)||tl[tl.length-1];
    const at=Math.max(0,bands.findIndex(b=>s>=b.start&&s<b.end));
    items.forEach((li,i)=>{li.classList.toggle('done',i<at);li.classList.toggle('now',i===at);li.classList.toggle('next',i>at);});
    if(!v.paused&&items[at])items[at].scrollIntoView({block:'nearest'});
    now.innerHTML=`${esc(r.step)}${r.kind==='device'?' <span class="counts">(phone screen)</span>':''}`;
    btn.textContent=v.paused?'▶':'❚❚';};
  const loop=()=>{show();if(!v.paused)requestAnimationFrame(loop);};
  v.onplay=loop; v.onpause=show; v.onseeked=show; v.onloadedmetadata=show; v.onended=show;
  btn.onclick=()=>v.paused?v.play():v.pause();
  v.onclick=btn.onclick;
  const seek=e=>{const box=track.getBoundingClientRect();const frac=Math.min(1,Math.max(0,(e.clientX-box.left)/box.width));
    v.currentTime=toVideo(frac*total);show();};
  track.onpointerdown=e=>{track.setPointerCapture(e.pointerId);seek(e);track.onpointermove=seek;};
  track.onpointerup=e=>{track.onpointermove=null;};
  show();
}
poll();
</script></body></html>''';

/// The jewelry ring, served as the page's logo and favicon.
const jewelryLogo = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <defs>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFE9A3"/>
      <stop offset="0.45" stop-color="#E8B93C"/>
      <stop offset="1" stop-color="#9C6A12"/>
    </linearGradient>
    <linearGradient id="ice" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#EAF8FF"/>
      <stop offset="1" stop-color="#7CC7EE"/>
    </linearGradient>
  </defs>
  <!-- gold band -->
  <circle cx="64" cy="76" r="38" fill="none" stroke="url(#gold)" stroke-width="10"/>
  <!-- gold setting -->
  <path d="M46 40 h36 l-6 8 h-24 z" fill="url(#gold)"/>
  <!-- diamond -->
  <g stroke="#2E6E91" stroke-width="1.5" stroke-linejoin="round">
    <path d="M40 22 L52 8 H76 L88 22 L64 48 Z" fill="url(#ice)"/>
    <path d="M40 22 H88 M52 8 L58 22 L64 48 L70 22 L76 8 M58 22 L64 8 L70 22" fill="none"/>
  </g>
  <path d="M55 12 L60 12 L56 19 Z" fill="#fff" opacity="0.9"/>
</svg>''';
