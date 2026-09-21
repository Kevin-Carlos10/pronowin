/* Exécute les vrais gestionnaires avec un DOM minimal et des services simulés. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ejs = require('ejs');
const {views, opts} = require('./test_all_views');

async function notifications() {
  const fixture = views.find(v => v[1] === 'notifications');
  const html = await ejs.renderFile('views/notifications.ejs', fixture[2], opts);
  const script = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].find(m => m[1].includes('const SEGMENTS_DATA'))[1];
  let segment = 'all', confirmations = [], submissions = 0;
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {value:'', textContent:'', hidden:false, style:{}, focus(){}, classList:{add(){},remove(){},toggle(){}}});
    return elements.get(id);
  };
  element('notif-title').value='Test local'; element('notif-body').value='Message de test';
  Object.assign(element('notif-form'), {reportValidity:()=>true, submit:()=>submissions++});
  const ctx = vm.createContext({document:{getElementById:element, querySelector:()=>({value:segment}), querySelectorAll:()=>[], addEventListener(){}}, apiFetch:async()=>{throw Error('503');}, showToast(){}, askConfirm:c=>confirmations.push(c), setTimeout(){}});
  vm.runInContext(script, ctx);
  await ctx.loadCount('all');
  assert.equal(element('total-count').textContent, 'Décompte indisponible');
  assert.equal(element('retry-count').hidden,false);
  ctx.confirmSend(); assert.equal(confirmations.length,0);
  for (const count of [undefined, -1, '15', 1.5, 0]) {
    ctx.apiFetch=async()=>({count}); await ctx.loadCount('all'); ctx.confirmSend();
    assert.equal(confirmations.length,0, 'Une audience invalide ou vide ne doit pas permettre l’envoi');
  }
  const pending=[];
  ctx.apiFetch=()=>new Promise(resolve=>pending.push(resolve));
  const old=ctx.loadCount('all'); const recent=ctx.loadCount('premium');
  pending[1]({count:12}); await recent;
  pending[0]({count:999}); await old;
  segment='premium'; ctx.confirmSend();
  assert.equal(confirmations.length,1); assert.match(confirmations[0].msg,/12 utilisateurs/);
  assert.equal(submissions,0); confirmations.pop().onConfirm(); assert.equal(submissions,1);
  segment='all'; ctx.confirmSend(); assert.equal(confirmations.length,0, 'Un ancien segment ne doit pas réutiliser le nouveau décompte');
  segment='user'; ctx.onSegChange('user'); ctx.confirmSend(); assert.equal(confirmations.length,0);
  element('inp-target-user').value='test-local'; ctx.confirmSend(); assert.equal(confirmations.length,1);
}

function proofsAndEdits() {
  const handlers={}, editHandlers={}, windowHandlers={};
  let confirmation, submissions=0;
  const error={hidden:true}; const note={value:'',focus(){}}; const reason={value:''};
  const buttons=[{},{}]; const fields=[];
  const form={dataset:{user:'Utilisateur test',type:'payment_screenshot'}, elements:{admin_note:note,duration_days:{value:'30'},xbet_id:{value:'',focus(){}}}, querySelector:s=>s==='.proof-error'?error:reason, querySelectorAll:()=>buttons, addEventListener:(name,fn)=>handlers[name]=fn, appendChild:e=>fields.push(e), reportValidity:()=>true};
  const editor={addEventListener:(name,fn)=>editHandlers[name]=fn, prepend(){}};
  const ctx=vm.createContext({document:{getElementById:()=>null,querySelectorAll:s=>s==='.proof-review'?[form]:[editor],createElement:()=>({setAttribute(){}})},window:{addEventListener:(name,fn)=>windowHandlers[name]=fn},askConfirm:c=>confirmation=c,HTMLFormElement:{prototype:{submit(){submissions++;}}}});
  vm.runInContext(fs.readFileSync('public/admin-ux.js','utf8'),ctx);
  const submit=value=>handlers.submit({preventDefault(){},submitter:{value}});
  submit('reject'); assert.equal(error.hidden,false); assert.equal(confirmation,undefined);
  reason.value='Capture illisible.'; submit('reject');
  assert.match(confirmation.msg,/Capture illisible/); assert.equal(submissions,0);
  confirmation.onConfirm(); confirmation.onConfirm();
  assert.equal(submissions,1); assert.equal(fields[0].value,'reject'); assert.equal(note.value,'Capture illisible.');
  assert.ok(buttons.every(b=>b.disabled));
  delete form.dataset.sending; confirmation=undefined; form.dataset.type='xbet_account_screenshot';
  submit('approve'); assert.equal(confirmation,undefined); assert.match(error.textContent,/identifiant/);
  form.elements.xbet_id.value='TEST123'; submit('approve'); assert.ok(confirmation);
  let warned=false;
  windowHandlers.beforeunload({preventDefault(){warned=true;}}); assert.equal(warned,false);
  editHandlers.input(); windowHandlers.beforeunload({preventDefault(){warned=true;}}); assert.equal(warned,true);
  editHandlers.submit({defaultPrevented:false}); warned=false;
  windowHandlers.beforeunload({preventDefault(){warned=true;}}); assert.equal(warned,false);
}
(async()=>{ await notifications(); proofsAndEdits(); console.log('OK : audience invalide/vide, réponses concurrentes, confirmation, rejet motivé, double clic et travail non enregistré.'); })().catch(e=>{console.error(e);process.exit(1);});
