const assert=require('node:assert/strict');
const ejs=require('ejs');
const {parse}=require('node-html-parser');
const {views,opts}=require('./test_all_views');
const {translator,normalizeLanguage}=require('./lib/ui-language');
(async()=>{
 for(const language of ['fr','en']) {
  for(const [label,view,locals] of views) {
   const html=await ejs.renderFile('views/'+view+'.ejs',{...locals,adminLanguage:language,tAdmin:translator(language)},opts);
   const dom=parse(html);
   if(dom.querySelector('#sidebar')) {
    assert.equal(dom.querySelector('html').getAttribute('lang'),language,label);
    assert.ok(dom.querySelector('#sidebar').textContent.includes(language==='en'?'Dashboard':'Tableau de bord'),label);
   }
   for(const [formId,field] of [['pro-form','prediction_label_en'],['af-form','title_en'],['tut-form','title_en'],['notif-form','title_en']]) {
    const form=dom.querySelector('#'+formId);
    if(form) assert.ok(form.querySelector('[name="'+field+'"]'),label+' '+field);
   }
  }
 }
 assert.equal(normalizeLanguage('<script>'),'fr');
 assert.equal(translator('en')('Nom privé inconnu'),'Nom privé inconnu');
 console.log('OK: all admin views render in FR/EN; navigation, language and editorial form ownership verified.');
})().catch(e=>{console.error(e);process.exitCode=1});
