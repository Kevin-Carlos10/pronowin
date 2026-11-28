const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ejs = require('ejs');
const ts = require('../backend/node_modules/typescript');
const assert = require('node:assert/strict');
const { views, opts } = require('./test_all_views');

(async () => {
  const [, view, locals] = views.find(([label]) => label === 'pronostic_form (edit)');
  const match = { ...locals.match, homeTeam: 'Netherlands', awayTeam: 'Belgium' };
  const html = await ejs.renderFile(path.join(__dirname, 'views', view + '.ejs'), { ...locals, match }, opts);
  assert.ok(html.includes('/admin/assets/football-i18n.js'));
  const script = [...html.matchAll(/<script[^>]*>(.*?)<[/]script>/gs)].find(m => m[1].includes('function selectCustomMarket'))[1];
  const source = ts.createSourceFile('form.js', script, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const needed = new Set(['updateRecap', 'setLabel', 'translateMarketName', 'translateMarketValue', 'selectCustomMarket', 'renderMarketsAccordion']);
  const functions = source.statements.filter(s => ts.isFunctionDeclaration(s) && needed.has(s.name?.text)).map(s => s.getFullText(source)).join('\n');
  const nodes = new Map();
  function element() { return { value: '', textContent: '', innerHTML: '', hidden: false, checked: false, style: {}, children: [], classList: { add() {}, remove() {} }, appendChild(x) { this.children.push(x); } }; }
  const node = id => { if (!nodes.has(id)) nodes.set(id, element()); return nodes.get(id); };
  const context = vm.createContext({
    document: { getElementById: node, querySelectorAll: () => [], createElement: element },
    setRecommendedOdd: value => { node('odds-rec').value = value; },
  });
  vm.runInContext(fs.readFileSync('public/football-i18n.js', 'utf8'), context);
  vm.runInContext('const HOME_TEAM="Netherlands", AWAY_TEAM="Belgium";\n' + functions, context);
  context.selectCustomMarket('Goals Over/Under', 'over 2.5', 1.90, null);
  assert.equal(node('market-name-input').value, 'Goals Over/Under');
  assert.equal(node('market-value-input').value, 'over 2.5');
  assert.equal(node('odds-rec').value, '1.90');
  assert.equal(node('preview-fr').textContent, 'Plus / Moins de buts : Plus de 2,5');
  assert.equal(node('preview-en').textContent, 'Goals Over/Under : Over 2.5');
  context.selectCustomMarket('Double Chance', 'Home or Draw', 1.60, null);
  assert.equal(node('preview-fr').textContent, 'Double chance : Pays-Bas ou Nul');
  assert.equal(node('preview-en').textContent, 'Double Chance : Netherlands or Draw');
  context.renderMarketsAccordion([{ name: 'Unlisted Market', values: [{value:'Alien option', odd:2.1}] }]);
  assert.equal(node('translation-unknown').hidden, false);
  assert.match(node('translation-unknown').textContent, /Unlisted Market/);
  context.renderMarketsAccordion([{ name: 'Match Winner', values: [{value:'Home', odd:2.1}] }]);
  assert.equal(node('translation-unknown').hidden, true);
  context.setLabel('Analyse personnalisée : Jordan Henderson');
  assert.match(node('preview-state-en').textContent, /relire/);
  assert.equal(node('preview-en').textContent, 'Analyse personnalisée : Jordan Henderson');
  node('i18n-prediction_label_en').value = 'Custom analyst pick';
  context.updateRecap();
  assert.equal(node('preview-en').textContent, 'Custom analyst pick');
  assert.equal(node('pred-label').value, 'Analyse personnalisée : Jordan Henderson');
  context.selectCustomMarket('Double Chance', 'Home or Draw', 1.60, null);
  assert.equal(node('i18n-prediction_label_en').value, '');
  assert.equal(node('preview-en').textContent, 'Double Chance : Netherlands or Draw');
  console.log('OK : real admin form, FR/EN preview, untouched raw selection/odds, unknown terms and custom text.');
})().catch(e => { console.error(e); process.exitCode=1; });
