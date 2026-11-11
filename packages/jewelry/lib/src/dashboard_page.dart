/// The dashboard's single page: no build step, no dependencies. It polls
/// `state.json` every second and each emulator's screen as fast as the
/// screenshots come.
const dashboardPage = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>jewelry</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#f6f5f2;--panel:#fff;--ink:#1d1b19;--dim:#7a756d;--line:#e4e0d8;
--ok:#1f8a4c;--bad:#c4372f;--run:#c98a0c;--rec:#3d6fb6}
*{box-sizing:border-box}
body{margin:0;font:14px/1.4 -apple-system,system-ui,sans-serif;color:var(--ink);background:var(--bg);
display:grid;grid-template-columns:320px 1fr;height:100vh}
aside{border-right:1px solid var(--line);background:var(--panel);overflow:auto}
header{padding:14px 16px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--panel)}
header h1{font-size:15px;margin:0 0 4px}
.counts{color:var(--dim);font-size:12px}
.bar{height:4px;background:var(--line);border-radius:2px;margin-top:8px;overflow:hidden}
.bar i{display:block;height:100%;background:var(--ok)}
ul{list-style:none;margin:0;padding:6px 0}
li{display:flex;gap:8px;align-items:center;padding:7px 16px;cursor:pointer}
li:hover{background:#f1efe9} li.sel{background:#ebe7dd}
li .name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
li .t{color:var(--dim);font-size:12px;font-variant-numeric:tabular-nums}
.dot{width:10px;height:10px;border-radius:50%;flex:none;background:var(--line)}
.passed .dot{background:var(--ok)} .failed .dot{background:var(--bad)}
.recorded .dot{background:var(--rec)}
.running .dot,.judging .dot{background:var(--run);animation:p 1s infinite alternate}
@keyframes p{to{opacity:.3}}
main{overflow:auto;padding:18px 22px}
main h2{font-size:16px;margin:0 0 14px;display:flex;gap:12px;align-items:baseline}
main h2 a{font-size:13px;font-weight:normal;color:var(--rec);cursor:pointer}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;display:flex;gap:14px}
.card img{width:180px;aspect-ratio:1344/2992;object-fit:cover;border-radius:8px;background:#111;flex:none}
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
</style></head><body>
<aside><header><h1>jewelry</h1><div class="counts" id="counts"></div><div class="bar"><i id="bar"></i></div></header>
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
function render(){
  const t=state.tests, done=t.filter(x=>['passed','failed','recorded'].includes(x.state));
  const failed=t.filter(x=>x.state==='failed').length;
  $('#counts').textContent=`${done.length}/${t.length} done · ${done.length-failed} ok · ${failed} failed · ${clock(state.elapsedMs)}`;
  $('#bar').style.width=(t.length?100*done.length/t.length:0)+'%';
  $('#tests').innerHTML=t.map(x=>{
    const ms=x.results[0]?.durationMs; const label=x.labels[0]||x.name;
    return `<li class="${x.state}${selected===x.key?' sel':''}" data-key="${esc(x.key)}"><span class="dot"></span>
      <span class="name" title="${esc(x.file)}">${esc(label)}</span><span class="t">${ms?clock(ms):x.state==='queued'?'':x.state}</span></li>`;
  }).join('');
  selected?renderDetail():renderLive();
}
$('#tests').onclick=e=>{const li=e.target.closest('li');if(!li)return;selected=li.dataset.key;render();};

function renderLive(){
  const ws=state.workers;
  if(!$('#live')){$('#main').innerHTML='<h2>Live</h2><div class="grid" id="live"></div>';}
  const grid=$('#live');
  for(const w of ws){
    let card=grid.querySelector(`[data-w="${CSS.escape(w.key)}"]`);
    if(!card){card=document.createElement('div');card.className='card';card.dataset.w=w.key;
      card.innerHTML='<img alt=""><div class="info"><div class="who"></div><div class="test"></div><ol></ol></div>';
      grid.appendChild(card);startScreen(w.key,card.querySelector('img'));}
    const test=state.tests.find(x=>x.key===w.test);
    card.querySelector('.who').textContent=`${w.profile} · emulator ${w.worker+1} · ${test?'running':w.status}`;
    card.querySelector('.test').textContent=test?(test.labels[0]||test.name):'';
    const at=w.steps.indexOf(w.step);
    card.querySelector('ol').innerHTML=w.steps.map((s,i)=>`<li class="${i<at?'done':i===at?'now':'next'}">${esc(s)}</li>`).join('');
  }
  if(!ws.length)grid.innerHTML='<p class="empty">No emulator yet.</p>';
}
function startScreen(key,img){
  if(screens[key])return; screens[key]=true;
  const next=()=>setTimeout(()=>{if(!document.body.contains(img)){delete screens[key];return;}img.src=`screen/${encodeURIComponent(key)}?t=${Date.now()}`},400);
  img.onload=next; img.onerror=()=>setTimeout(next,1500); next();
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
    html+=`<figure><figcaption>Golden</figcaption><video controls muted playsinline src="video/golden/${name}/${prof}" onerror="this.parentNode.remove()"></video></figure>`;
    if(r&&r.failureDir){
      html+=`<figure><figcaption>This run</figcaption><video controls muted playsinline src="video/failure/${name}/${prof}" onerror="this.parentNode.remove()"></video></figure>`;
      for(const [f,c] of [['expected_frame.png','Expected'],['actual_frame.png','Actual'],['diff.png','Difference']])
        html+=`<figure><figcaption>${c}</figcaption><img src="files/${r.failureDir}/${f}" onerror="this.parentNode.remove()"></figure>`;
    }
  }
  html+='</div>';
  if(x.state==='queued'||x.state==='running')html+='<p class="empty">Not finished yet: the golden plays above when there is one.</p>';
  html+='<p><a href="files/report.html" target="_blank">Full report</a></p></div>';
  $('#main').innerHTML=html;
  $('#back').onclick=()=>{selected=null;$('#main').innerHTML='';$('#main').dataset.shown='';render();};
}
poll();
</script></body></html>''';
