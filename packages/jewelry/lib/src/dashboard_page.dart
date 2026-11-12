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
.accepted .dot{background:none;border-radius:0;width:12px;height:auto;font-weight:700;font-size:13px;line-height:1;text-align:center}
.accepted .dot::after{content:'✓';color:var(--rec)}
.accept{border:1px solid var(--bad);background:#fff;color:var(--bad);border-radius:6px;padding:6px 12px;font:inherit;font-size:13px;cursor:pointer;margin:2px 0 10px}
.accept:hover{background:var(--bad);color:#fff} .accept:disabled{opacity:.5;cursor:wait}
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
.player>div:first-child{min-width:260px}
.player ol.steps{width:250px;margin-top:20px;max-height:640px;overflow:auto}
ol.steps li{cursor:pointer;padding:3px 6px;border-radius:5px}
ol.steps li:hover{background:#ebe7dd}
ol.steps li.now{background:#f3ead6}
ol.steps li.bad{color:var(--bad)} ol.steps li.bad:before{content:"✗ ";color:var(--bad)}
ol.steps li.off:after{content:" ◷";color:#e8a33c}
.vwrap{position:relative}
.vload{position:absolute;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:#ddd8cd;font-size:12px;pointer-events:none}
.vwrap.loading .vload{display:flex}
.player video{width:300px;display:block;border-radius:8px 8px 0 0;border:1px solid var(--line);background:#111}
.screens{display:flex;gap:12px;align-items:flex-start}
.pv{width:260px;position:relative}
.player video,.pv img{width:260px}
.held{position:absolute;left:0;right:0;bottom:0;display:none;padding:8px;background:#1d1b19d9;color:#fff;font-size:12px;border-radius:0 0 8px 8px}
.pv.isheld .held{display:block} .pv.isheld video{filter:saturate(.4) brightness(.85)}
.diffpane{display:none} .atdiff .diffpane{display:block}
.atdiff .pv video,.diffpane img{outline:3px solid var(--bad);outline-offset:-1px}
.diffpane img{border-radius:8px;display:block}
.dlabel{font-size:12px;color:var(--bad);margin-top:6px}
.dmark{position:absolute;top:-4px;bottom:-4px;width:6px;margin-left:-3px;background:repeating-linear-gradient(0deg,#000 0 3px,#fff 3px 6px);outline:1px solid #000;cursor:pointer;z-index:2}
.hint{margin-left:6px;flex:1;min-width:0}
.ctrl{display:flex;align-items:center;gap:8px;margin:6px 0 4px;font-size:12px;color:var(--dim);font-variant-numeric:tabular-nums}
.ctrl button{border:0;background:var(--ink);color:#fff;border-radius:50%;width:26px;height:26px;cursor:pointer;font-size:11px}
.track{position:relative;height:18px;border-radius:4px;overflow:hidden;background:var(--line);cursor:pointer;touch-action:none}
.band{position:absolute;top:0;bottom:0;border-right:1px solid #fff8}
.band.a{background:#d9d4c8}.band.b{background:#cbc5b7}
.band.off{background:#e8a33c radial-gradient(#3a2600 1.3px,transparent 1.6px) 0 0/6px 6px}
.band.bad{background:repeating-linear-gradient(45deg,#000a 0 2px,transparent 2px 6px),repeating-linear-gradient(-45deg,#000a 0 2px,transparent 2px 6px),var(--bad)}
.band b{display:block;text-align:center;font-size:11px;line-height:18px;color:#fff;text-shadow:0 0 2px #000;overflow:hidden;white-space:nowrap}
.seg{position:absolute;bottom:0;height:5px}
.seg.device{background:repeating-linear-gradient(90deg,#3d6fb6 0 3px,#fff 3px 5px);height:7px;border-top:1px solid #000}.seg.wait{background:repeating-linear-gradient(45deg,#0003 0 3px,transparent 3px 6px);height:100%}
.tick{position:absolute;top:0;width:6px;height:6px;margin-left:-3px;background:#fff;border:1px solid #000;transform:rotate(45deg) translate(-1px,-1px)}
.head{position:absolute;top:-2px;bottom:-2px;width:3px;margin-left:-1px;background:var(--ink);border-radius:2px;pointer-events:none}
.nowstep{font-size:12px;margin-top:5px;min-height:1.4em}
/* Text under and beside the bar wraps within the videos' width, so the bar
   keeps one width while the step and its states change. */
.nowstep,.ctrl{width:0;min-width:100%}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--dim);margin:4px 0 10px}
.legend i{display:inline-block;position:relative;width:18px;height:12px;border-radius:2px;margin-right:5px;vertical-align:-2px}
.legend i.band b{line-height:12px;font-size:9px}
.legend i.tick{width:7px;height:7px;margin:0 7px 0 4px;transform:rotate(45deg)}
.legend i.dmark{width:6px;margin:0 6px 0 2px;position:relative;top:0;bottom:0}
.legend i.seg{position:relative;height:7px}
.legend i.mask{position:relative;display:inline-block}
.nowstep .state{color:var(--dim)}
.masks{position:absolute;left:1px;top:1px;right:1px;bottom:1px;pointer-events:none;overflow:hidden}
.mask{position:absolute;outline:2px dashed #000;outline-offset:-1px;background:repeating-linear-gradient(45deg,#ffd400aa 0 5px,#0000 5px 10px)}
.mask span,.masks.wait:after{position:absolute;left:0;top:0;background:#ffd400;color:#000;font-size:10px;font-weight:600;padding:1px 4px}
.masks.wait{background:repeating-linear-gradient(45deg,#0005 0 4px,#0000 4px 12px);outline:3px dashed #ffd400;outline-offset:-3px}
.masks.wait:after{content:'not compared: waiting'}
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
const stateTitle={queued:'Queued',running:'Running',judging:'Being compared',passed:'Passed: matches its golden',failed:'Failed',recorded:'Recorded: a new golden, nothing to compare against',accepted:'Accepted: this run is the new golden'};
function render(){
  const t=state.tests, done=t.filter(x=>['passed','failed','recorded','accepted'].includes(x.state));
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
    if(r.outcome==='failed'){html+=`<p class="reason">${esc(r.reason)}</p>${r.detail?`<pre>${esc(r.detail)}</pre>`:''}`;
      html+=r.acceptable?`<button class="accept" data-label="${esc(r.label)}">Accept this run as the new golden</button>`
        :'<p class="counts">This run cannot become the golden: it stopped before the end.</p>';}
    else html+=`<p>${esc(r.label)}: ${esc(r.outcome)}, ${r.frames} frames, ${clock(r.durationMs)}</p>`;
  }
  html+='<div class="media">';
  for(const s of slugs)html+=player(s,prof,x.results.find(r=>r.slug===s));
  html+='</div>';
  if(x.state==='queued'||x.state==='running')html+='<p class="empty">Not finished yet: the golden plays above when there is one.</p>';
  html+=`<div class="legend"><span><i class="band bad"><b>✗</b></i>step that failed</span>
    <span><i class="band off"><b>◷</b></i>step took a different time than in the golden</span>
    <span><i class="seg device"></i>phone screen (outside the app)</span>
    <span><i style="background:repeating-linear-gradient(45deg,#0004 0 3px,#d9d4c8 3px 6px)"></i>waiting, not compared</span>
    <span><i class="tick"></i>snapshot</span>
    <span><i class="dmark"></i>difference: playback stops here</span>
    <span><i class="mask"><span></span></i>on the video: left out of the comparison</span></div>`;
  html+='<p><a href="files/report.html" target="_blank">Full report</a></p></div>';
  $('#main').innerHTML=html;
  for(const b of document.querySelectorAll('button.accept'))b.onclick=async()=>{
    if(!confirm(`Make this run the new golden for "${b.dataset.label}" on ${x.profile}?\n\nThe current golden video and snapshots are overwritten.`))return;
    b.disabled=true;b.textContent='Accepting…';
    try{const res=await (await fetch('accept/'+encodeURIComponent(x.key),{method:'POST'})).json();
      if(!res.accepted)throw new Error('refused');
      state=await (await fetch('state.json')).json();$('#main').dataset.shown='';render();}
    catch(e){b.disabled=false;b.textContent='Accepting failed, try again';}
  };
  initPlayers();
  $('#back').onclick=()=>{selected=null;history.replaceState(null,'',location.pathname);$('#main').innerHTML='';$('#main').dataset.shown='';render();};
}
// One player per scenario: the golden and, for a failure, this run, side by
// side on one clock. Steps are lined up: a step lasts as long as the slower
// recording takes, and the faster one holds its last frame meanwhile.
// Playback stops at every difference, with the diff image beside both.
function player(s,prof,r){
  const name=encodeURIComponent(s);
  const vids=[['Golden','golden']]; if(r&&r.failureDir)vids.push(['This run','failure']);
  return `<figure class="player" data-name="${name}" data-prof="${prof}" data-dir="${r&&r.failureDir?esc(r.failureDir):''}" data-failed="${esc(r&&r.outcome==='failed'?r.step||'':'')}">
    <div class="pmain"><div class="screens">${vids.map(([c,k])=>`<div class="pv" data-kind="${k}"><figcaption>${c}</figcaption>
      <div class="vwrap loading"><video muted playsinline preload="auto" src="video/${k}/${name}/${prof}"></video>
      <div class="masks"></div><div class="vload"><div class="spin"></div><span>Loading the video…</span></div><div class="held"></div></div></div>`).join('')}
      <div class="pv diffpane"><figcaption>Difference, in red</figcaption><img alt=""><div class="dlabel"></div></div></div>
    <div class="ctrl"><button>▶</button><span class="time">00:00</span><span class="hint"></span></div>
    <div class="track"><div class="head"></div></div><div class="nowstep"></div></div>
    <ol class="steps"></ol></figure>`;
}
async function initPlayers(){
  for(const f of [...document.querySelectorAll('.player')]){
    const pvs=[...f.querySelectorAll('.pv[data-kind]')];
    const tls=await Promise.all(pvs.map(p=>fetch(`timeline/${p.dataset.kind}/${f.dataset.name}/${f.dataset.prof}`).then(r=>r.ok?r.json():null).catch(()=>null)));
    const recs=pvs.map((p,i)=>({el:p,v:p.querySelector('video'),tl:tls[i]})).filter(r=>{if(r.tl&&r.tl.length)return true;r.el.remove();return false;});
    if(!recs.length){f.remove();continue;}
    let diffs=[];
    if(f.dataset.dir&&recs.length===2&&recs[0].el.dataset.kind==='golden'){
      try{diffs=await (await fetch(`files/${f.dataset.dir}/differences.json`)).json();}catch(e){}
    }
    setupPlayer(f,recs,diffs,f.dataset.failed);
  }
}
const bandsOf=tl=>{const b=[];for(const r of tl){const l=b[b.length-1];if(l&&l.step===r.step)l.end=r.end;else b.push({step:r.step,start:r.start,end:r.end});}return b;};
function setupPlayer(f,recs,diffs,failed){
  const track=f.querySelector('.track'), head=f.querySelector('.head'), btn=f.querySelector('button');
  const time=f.querySelector('.time'), hint=f.querySelector('.hint'), now=f.querySelector('.nowstep');
  const pane=f.querySelector('.diffpane');
  // Line the steps up: each golden step with the next step of the same name in this run.
  const B=recs.map(r=>bandsOf(r.tl)), segs=[];
  let j=0;
  for(const g of B[0]){
    let a=null;
    if(B[1]){const k=B[1].findIndex((x,i)=>i>=j&&x.step===g.step);if(k>=0){a=B[1][k];j=k+1;}}
    const parts=B[1]?[g,a]:[g];
    segs.push({step:g.step,parts,len:Math.max(...parts.filter(Boolean).map(p=>p.end-p.start))});
  }
  let total=0; for(const s of segs){s.at=total;total+=s.len;}
  const segAt=T=>{let i=0;while(i+1<segs.length&&segs[i+1].at<=T)i++;return i;};
  // Master time of second t in recording i.
  const masterOf=(i,t)=>{for(const s of segs){const p=s.parts[i];if(p&&t>=p.start&&t<p.end)return s.at+t-p.start;}return total;};
  // Where recording i is at master time T, and whether it is holding.
  const pos=(i,T)=>{
    const si=segAt(T), s=segs[si], p=s.parts[i];
    if(!p){let k=si;while(k>=0&&!segs[k].parts[i])k--;
      return {t:k<0?0:segs[k].parts[i].end-0.02,held:true,note:'This run has no such step'};}
    const local=T-s.at, d=p.end-p.start;
    if(local>=d)return {t:Math.max(p.start,p.end-0.02),held:true,note:`Holding: this step took ${(s.len-d).toFixed(1)} s less here`};
    return {t:p.start+local,held:false};
  };
  // The MP4 keeps the timeline's times; it only runs a little longer at the end.
  const toVideo=(r,t)=>t;
  for(const d of diffs)d.T=masterOf(0,d.golden);
  // A widget can be ignored twice (scenario and step); draw and count it once.
  for(const r of recs)for(const x of r.tl)if(x.ignore)x.ignore=[...new Map(x.ignore.filter(g=>g[2]>0&&g[3]>0).map(g=>[g.slice(0,4).join(),g])).values()];
  // The bar: one band per step, coloured when it failed or took a different time.
  let html='', list='';
  segs.forEach((s,i)=>{
    const [g,a]=s.parts, dg=g.end-g.start, da=a?a.end-a.start:null;
    const off=recs.length>1&&(a===null||Math.abs(dg-da)>Math.max(0.5,0.25*Math.max(dg,da)));
    const cls=s.step===failed?'bad':off?'off':(i%2?'b':'a');
    const why=recs.length>1?`${dg.toFixed(1)} s in the golden, ${a?da.toFixed(1)+' s':'missing'} in this run`:`${dg.toFixed(1)} s`;
    const glyph=cls==='bad'?'✗':cls==='off'?'◷':'';
    html+=`<div class="band ${cls}" style="left:${100*s.at/total}%;width:${100*s.len/total}%" title="${esc(s.step+' · '+why)}"><b>${glyph}</b></div>`;
    list+=`<li data-i="${i}" class="${cls==='bad'||cls==='off'?cls:''}" title="${esc(why)}">${esc(s.step)}</li>`;
  });
  for(const r of recs[0].tl){
    const a=masterOf(0,r.start), b=masterOf(0,r.end-1e-6);
    if(r.kind!=='app')html+=`<div class="seg ${r.kind}" style="left:${100*a/total}%;width:${100*(b-a)/total}%"></div>`;
    if(r.snapshot)html+=`<div class="tick" style="left:${100*a/total}%" title="snapshot: ${esc(r.snapshot)}"></div>`;
  }
  diffs.forEach((d,i)=>html+=`<div class="dmark" data-d="${i}" style="left:${100*d.T/total}%" title="${esc(d.label)}"></div>`);
  track.insertAdjacentHTML('afterbegin',html);
  const steps=f.querySelector('ol.steps'); steps.innerHTML=list; const items=[...steps.children];
  let T=0, playing=false, last=0, atDiff=null;
  const sync=()=>recs.forEach((r,i)=>{
    const q=atDiff?{t:i===0?atDiff.golden:atDiff.actual,held:false}:pos(i,T), target=toVideo(r,q.t);
    r.el.classList.toggle('isheld',q.held); r.el.querySelector('.held').textContent=q.held?'⏸ '+q.note:'';
    if(playing&&!q.held){
      if(r.v.paused){r.v.currentTime=target;r.v.play().catch(()=>{});}
      else if(Math.abs(r.v.currentTime-target)>0.25)r.v.currentTime=target;
    }else{
      if(!r.v.paused)r.v.pause();
      if(Math.abs(r.v.currentTime-target)>0.03)r.v.currentTime=target;
    }
  });
  const show=()=>{
    head.style.left=(100*T/total)+'%';
    time.textContent=`${clock(T*1000)} / ${clock(total*1000)}`;
    const si=segAt(T);
    items.forEach((li,i)=>{li.classList.toggle('done',i<si);li.classList.toggle('now',i===si);li.classList.toggle('next',i>si);});
    if(playing&&items[si])items[si].scrollIntoView({block:'nearest'});
    const g=recs[0].tl.find(r=>{const t=pos(0,T).t;return t>=r.start&&t<r.end;});
    // The same facts as the bar's patterns, in words.
    const states=[];
    if(segs[si].step===failed)states.push('✗ this step failed');
    const [sg,sa]=segs[si].parts;
    if(recs.length>1&&sa&&Math.abs((sg.end-sg.start)-(sa.end-sa.start))>Math.max(0.5,0.25*Math.max(sg.end-sg.start,sa.end-sa.start)))
      states.push(`◷ ${(sg.end-sg.start).toFixed(1)} s in the golden, ${(sa.end-sa.start).toFixed(1)} s in this run`);
    if(g&&g.kind==='device')states.push('phone screen');
    if(g&&g.kind==='wait')states.push('waiting, not compared');
    if(g&&g.ignore&&g.ignore.length)states.push(`${g.ignore.length} area${g.ignore.length>1?'s':''} ignored`);
    now.innerHTML=`${esc(segs[si].step)}${states.length?` <span class="state">· ${states.map(esc).join(' · ')}</span>`:''}`;
    recs.forEach((r,i)=>drawMasks(r,atDiff?(i===0?atDiff.golden:atDiff.actual):pos(i,T).t));
    btn.textContent=playing?'❚❚':'▶';
    hint.textContent=atDiff?'Stopped at a difference; play to go on':diffs.length?`${diffs.length} difference${diffs.length>1?'s':''}: playback stops at each red mark`:'';
    f.classList.toggle('atdiff',!!atDiff);
  };
  // What the comparison leaves out at second t of a recording: the ignored
  // areas of that frame, or all of it while waiting.
  const drawMasks=(r,t)=>{
    const box=r.el.querySelector('.masks'), run=r.tl.find(x=>t>=x.start&&t<x.end);
    box.classList.toggle('wait',!!run&&run.kind==='wait');
    const k=r.v.videoWidth?r.v.clientWidth/r.v.videoWidth:0;
    box.innerHTML=!k||!run||!run.ignore||run.kind==='wait'?'':run.ignore.map(([x,y,w,h])=>
      `<div class="mask" style="left:${x*k}px;top:${y*k}px;width:${w*k}px;height:${h*k}px"><span>ignored</span></div>`).join('');
  };
  const showDiff=d=>{atDiff=d;pane.querySelector('img').src=`files/${f.dataset.dir}/${d.diff}`;pane.querySelector('.dlabel').textContent=d.label;sync();show();};
  const pause=()=>{playing=false;sync();show();};
  const tick=t=>{
    if(!playing)return;
    const dt=Math.min(0.1,(t-last)/1000); last=t;
    // Wait for a video that is still loading, so both stay on the same step.
    const buffering=recs.some((r,i)=>!pos(i,T).held&&r.v.readyState<3);
    if(!buffering){
      const prev=T; T=Math.min(total,T+dt);
      const d=diffs.find(d=>d.T>prev&&d.T<=T);
      if(d){T=d.T;playing=false;showDiff(d);return;}
      if(T>=total){pause();return;}
    }
    sync();show();requestAnimationFrame(tick);
  };
  const play=()=>{if(T>=total)T=0;atDiff=null;playing=true;last=performance.now();sync();show();requestAnimationFrame(tick);};
  btn.onclick=()=>playing?pause():play();
  recs.forEach(r=>{
    r.v.onclick=btn.onclick;
    const wrap=r.el.querySelector('.vwrap'), loading=on=>wrap.classList.toggle('loading',on);
    if(r.v.readyState>=3)loading(false);
    r.v.onwaiting=()=>loading(true); r.v.oncanplay=r.v.onplaying=()=>loading(false);
    r.v.onloadedmetadata=()=>{sync();show();};
    r.v.onerror=()=>r.el.remove();
  });
  steps.onclick=e=>{const li=e.target.closest('li');if(!li)return;T=segs[+li.dataset.i].at+0.01;atDiff=null;sync();show();};
  const seek=e=>{const box=track.getBoundingClientRect();T=total*Math.min(1,Math.max(0,(e.clientX-box.left)/box.width));atDiff=null;sync();show();};
  track.onpointerdown=e=>{
    if(e.target.classList.contains('dmark')){const d=diffs[+e.target.dataset.d];playing=false;T=d.T;showDiff(d);return;}
    track.setPointerCapture(e.pointerId);seek(e);track.onpointermove=seek;};
  track.onpointerup=()=>{track.onpointermove=null;};
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
