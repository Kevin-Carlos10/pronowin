/**
 * Les « autres marchés 1xBet » du formulaire de pronostic (hors API, cote
 * saisie) : le vrai code du formulaire, exécuté hors navigateur.
 *
 * Choisir un marché, ses options et sa cote doit produire la valeur que le
 * moteur de règlement du serveur sait lire, et un libellé public traduit
 * dans les deux langues — sans quoi le pronostic resterait à régler à la
 * main, sous un libellé bancal.
 *
 *   node _check_marches_complementaires.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ejs = require('ejs');
const ts = require('../backend/node_modules/typescript');
const assert = require('node:assert/strict');
const { views, opts } = require('./test_all_views');
const { translator } = require('./lib/ui-language');
const moteur = require('../backend/src/marches/complementaires');

(async () => {
  const [, view, locals] = views.find(([label]) => label === 'pronostic_form (edit)');
  const match = { ...locals.match, homeTeam: 'Aston Villa', awayTeam: 'Brentford' };

  // Le bloc existe dans les deux langues du panneau, et charge le module.
  for (const language of ['fr', 'en']) {
    const html = await ejs.renderFile(path.join(__dirname, 'views', view + '.ejs'),
      { ...locals, match, adminLanguage: language, tAdmin: translator(language) }, opts);
    assert.ok(html.includes('/admin/assets/marches-complementaires.js'), 'module non chargé');
    assert.ok(html.includes('id="marches-plus"'), 'bloc absent');
    assert.ok(html.includes(language === 'en' ? 'Other 1xBet markets' : 'Autres marchés 1xBet'), language);
  }

  // La copie du panneau est bien celle du serveur (sinon : régénérer).
  assert.ok(fs.readFileSync('public/marches-complementaires.js', 'utf8')
    .includes(fs.readFileSync('../backend/src/marches/complementaires.js', 'utf8').replace(/\r\n/g, '\n').split('\n')[1]));

  // ── Le code du formulaire, sur un DOM réduit au nécessaire ──
  const html = await ejs.renderFile(path.join(__dirname, 'views', view + '.ejs'), { ...locals, match }, opts);
  const script = [...html.matchAll(/<script[^>]*>(.*?)<[/]script>/gs)].find(m => m[1].includes('function utiliserMarchePlus'))[1];
  const source = ts.createSourceFile('form.js', script, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const voulues = new Set(['updateRecap', 'setLabel', 'translateMarketName', 'translateMarketValue', 'selectCustomMarket',
    'mpChoixPossibles', 'mpChoix', 'mpValeur', 'mpApercu', 'mpAfficherOptions', 'utiliserMarchePlus']);
  const fonctions = source.statements.filter(s => ts.isFunctionDeclaration(s) && voulues.has(s.name?.text))
    .map(s => s.getFullText(source)).join('\n');
  const textes = source.statements.find(s => ts.isVariableStatement(s) && s.getText(source).includes('MP_TEXTES')).getFullText(source);

  const noeuds = new Map();
  function element(tag) {
    return {
      tag, value: '', textContent: '', hidden: false, checked: false, style: {}, dataset: {},
      children: [], classList: { add() {}, remove() {} },
      // Comme dans un navigateur : vider le contenu retire les éléments.
      get innerHTML() { return ''; }, set innerHTML(v) { if (v === '') this.children = []; },
      appendChild(x) { this.children.push(x); if (tag === 'select' && this.children.length === 1) this.value = x.value; },
      addEventListener() {},
    };
  }
  const noeud = id => { if (!noeuds.has(id)) noeuds.set(id, element('div')); return noeuds.get(id); };
  const selects = () => noeud('mp-options').children.map(bloc => bloc.children[1]);
  const context = vm.createContext({
    document: {
      getElementById: noeud,
      createElement: element,
      querySelectorAll: q => q === '#mp-options select' ? selects() : [],
    },
    setRecommendedOdd: v => { noeud('odds-rec').value = v; },
  });
  vm.runInContext(fs.readFileSync('public/football-i18n.js', 'utf8'), context);
  vm.runInContext(fs.readFileSync('public/marches-complementaires.js', 'utf8'), context);
  vm.runInContext('const HOME_TEAM="Aston Villa", AWAY_TEAM="Brentford";\n' + textes + fonctions, context);
  const choisir = (option, valeur) => { selects().find(s => s.dataset.option === option).value = valeur; };

  // « Équipe 2 va gagner au moins une mi-temps – Oui » à 1,77.
  noeud('mp-marche').value = 'To Win Either Half';
  context.mpAfficherOptions();
  assert.deepEqual(selects().map(s => s.dataset.option), ['equipe', 'ouiNon']);
  assert.deepEqual(selects()[0].children.map(o => o.textContent), ['Aston Villa', 'Brentford']);
  choisir('equipe', 'Away');
  choisir('ouiNon', 'Yes');
  context.mpApercu();
  assert.equal(noeud('mp-apercu').textContent, 'Gagne au moins une mi-temps : Brentford / Oui');

  // Sans cote, rien n'est appliqué.
  noeud('mp-cote').value = '';
  context.utiliserMarchePlus();
  assert.equal(noeud('mp-erreur').hidden, false);
  assert.equal(noeud('market-name-input').value, '');

  noeud('mp-cote').value = '1,77';
  context.utiliserMarchePlus();
  assert.equal(noeud('mp-erreur').hidden, true);
  assert.equal(noeud('type-input').value, 'other');
  assert.equal(noeud('market-name-input').value, 'To Win Either Half');
  assert.equal(noeud('market-value-input').value, 'Away / Yes');
  assert.equal(noeud('odds-rec').value, '1.77');
  assert.equal(noeud('pred-label').value, 'Gagne au moins une mi-temps : Brentford / Oui');
  assert.equal(noeud('preview-en').textContent, 'To Win Either Half : Brentford / Yes');
  // 1-0 à la pause, 1-2 à la fin : Brentford gagne la 2e mi-temps.
  assert.equal(moteur.regler('To Win Either Half', 'Away / Yes', { home: 1, away: 2 }, { home: 1, away: 0 }), 'WIN');

  // Un marché de la phase 2 : minutes nommées, et une note sur son règlement.
  noeud('mp-marche').value = 'Result At Minute';
  context.mpAfficherOptions();
  assert.deepEqual(selects().map(s => s.dataset.option), ['minute', 'issue']);
  assert.equal(selects()[0].children[0].textContent, '10e minute');
  assert.equal(noeud('mp-note').hidden, false);
  assert.match(noeud('mp-note').textContent, /2 h 15/);
  noeud('mp-marche').value = 'To Win Either Half';
  context.mpAfficherOptions();
  assert.equal(noeud('mp-note').hidden, true);

  // Les données d'un match (2-1, 1-1 à la pause), telles que le serveur les
  // lit pour la phase 2 (services/donnees_reglement.ts).
  const but = (minute, equipe) => ({ minute, extra: null, equipe, type: 'Goal', detail: 'Normal Goal' });
  const donnees = {
    prolongation: false,
    evenements: [but(20, 'Home'), but(40, 'Away'), { minute: 55, extra: null, equipe: 'Away', type: 'Card', detail: 'Yellow Card' }, but(70, 'Home')],
    stats: { Home: { corners: 7, jaunes: 1, rouges: 0 }, Away: { corners: 3, jaunes: 2, rouges: 0 } },
  };

  // Chaque marché, avec les premiers choix proposés, donne une valeur réglable.
  for (const m of moteur.MARCHES) {
    noeud('mp-marche').value = m.nom;
    context.mpAfficherOptions();
    assert.equal(selects().length, m.options.length, m.nom);
    const valeur = context.mpValeur().valeur;
    assert.ok(valeur, m.nom + ' : aucune valeur');
    assert.notEqual(moteur.regler(m.nom, valeur, { home: 2, away: 1 }, { home: 1, away: 1 }, donnees), null, m.nom + ' : ' + valeur);
    assert.ok(context.PronoFootball.prediction(context.translateMarketName(m.nom) + ' : ' + context.translateMarketValue(valeur),
      'en', 'Aston Villa', 'Brentford').known, m.nom + ' : libellé anglais introuvable');
  }

  console.log('OK : autres marchés 1xBet — choix, cote, libellé FR/EN et valeur réglée par le serveur, pour les '
    + moteur.MARCHES.length + ' marchés.');
})().catch(e => { console.error(e); process.exitCode = 1; });
