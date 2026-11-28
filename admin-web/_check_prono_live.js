const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const handlers={},windowHandlers={},timers=new Map(); let next=0,requests=0;
const classes=new Set();
const score={textContent:'vs',style:{}};
const phase={textContent:''},result={textContent:''};
const classList={toggle(name,on){on?classes.add(name):classes.delete(name);},remove(name){classes.delete(name);}};
const when={classList};
const row={dataset:{matchId:'m1'},classList,querySelector:s=>({'[data-match-score]':score,'.match-phase':phase,'[data-match-result]':result,'.when':when}[s])};
const status={textContent:''};
let data={matches:[{id:'m1',status:'LIVE',homeScore:0,awayScore:0,elapsedMinutes:2}]},ok=true;
const document={hidden:false,querySelectorAll:()=>[row],getElementById:()=>status,addEventListener:(name,fn)=>handlers[name]=fn};
const ctx=vm.createContext({document,window:{addEventListener:(name,fn)=>windowHandlers[name]=fn},AbortController,
  setTimeout:(fn,delay)=>{const id=++next;timers.set(id,{fn,delay});return id;},clearTimeout:id=>timers.delete(id),
  fetch:async(url,options)=>{requests++; assert.equal(url,'/admin/api/pronostics/scores');assert.deepEqual(JSON.parse(options.body).ids,['m1']);return {status:ok?200:503,ok,json:async()=>data};},
});
const flush=()=>new Promise(resolve=>setImmediate(resolve));
async function tick(){const timer=[...timers.values()].find(t=>t.delay===15000);assert.ok(timer,'une prochaine actualisation doit être planifiée');timer.fn();await flush();}
(async()=>{
  vm.runInContext(fs.readFileSync('public/prono-live.js','utf8'),ctx);await flush();
  assert.equal(score.textContent,'0–0');assert.ok(classes.has('is-live'));assert.match(phase.textContent,/2′/);
  data={matches:[{id:'m1',status:'LIVE',homeScore:1,awayScore:0,elapsedMinutes:21}]};await tick();assert.equal(score.textContent,'1–0');
  data={matches:[{id:'m1',status:'FINISHED',homeScore:2,awayScore:1,pronostic:{result:'WIN'}}]};await tick();
  assert.equal(score.textContent,'2–1');assert.equal(phase.textContent,'Terminé');assert.equal(classes.has('is-live'),false);assert.match(result.textContent,/Gagné/);
  ok=false;await tick();assert.equal(score.textContent,'2–1');assert.match(status.textContent,/interrompue/);
  const before=requests;document.hidden=true;handlers.visibilitychange();await flush();assert.equal(requests,before);
  document.hidden=false;ok=true;handlers.visibilitychange();await flush();assert.equal(requests,before+1);
  windowHandlers.pagehide();assert.equal(timers.size,0);
  console.log('OK : score nul, but, fin de match, résultat, panne, reprise et arrêt hors écran.');
})().catch(e=>{console.error(e);process.exitCode=1;});
