/**
 * La garde du libellé : le formulaire refuse un libellé qui ne décrit plus
 * le marché sélectionné.
 *
 * Le résultat se calcule sur le marché enregistré, jamais sur le texte. Le
 * 8 octobre 2026, 32 pronostics publiés portaient un libellé réécrit à la
 * main pour un autre pari (« Bellingham plus de 1,5 fautes subies » sur
 * « Angleterre gagne »), et sept avaient un résultat faux — réglé sur le pari
 * caché. Exécuté sur le vrai code du formulaire.
 *
 *   node _check_garde_libelle.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ejs = require('ejs');
const ts = require('../backend/node_modules/typescript');
const assert = require('node:assert/strict');
const { views, opts } = require('./test_all_views');

(async () => {
  const [, view, locals] = views.find(([label]) => label === 'pronostic_form (edit)');
  const match = { ...locals.match, homeTeam: 'Czechia', awayTeam: 'England' };
  const html = await ejs.renderFile(path.join(__dirname, 'views', view + '.ejs'), { ...locals, match }, opts);
  assert.ok(html.includes('id="libelle-ecart"'), 'encadré absent');
  assert.ok(html.includes('id="btn-marche-libre"'), 'bouton « marché libre » absent');

  const script = [...html.matchAll(/<script[^>]*>(.*?)<[/]script>/gs)].find(m => m[1].includes('function libelleCoherent'))[1];
  const source = ts.createSourceFile('form.js', script, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const voulues = new Set(['setLabel', 'updateRecap', 'translateMarketName', 'translateMarketValue', 'mpLibelles',
    'libelleAttendu', 'libelleNormalise', 'libelleCoherent', 'marcheLibre', 'retablirLibelle']);
  const fonctions = source.statements.filter(s => ts.isFunctionDeclaration(s) && voulues.has(s.name?.text))
    .map(s => s.getFullText(source)).join('\n');
  const constantes = source.statements.filter(s => ts.isVariableStatement(s)
    && /typeLabels|MP_TEXTES/.test(s.getText(source))).map(s => s.getFullText(source)).join('\n');

  const noeuds = new Map();
  const element = () => ({ value: '', textContent: '', hidden: false, checked: false, style: {}, dataset: {},
    classList: { add() {}, remove() {} }, setAttribute() {} });
  const noeud = id => { if (!noeuds.has(id)) noeuds.set(id, element()); return noeuds.get(id); };
  const context = vm.createContext({ document: { getElementById: noeud, querySelectorAll: () => [] } });
  vm.runInContext(fs.readFileSync('public/football-i18n.js', 'utf8'), context);
  vm.runInContext(fs.readFileSync('public/marches-complementaires.js', 'utf8'), context);
  vm.runInContext('const HOME_TEAM="Czechia", AWAY_TEAM="England";\n' + constantes + fonctions, context);

  const etat = (type, nom, valeur, libelle) => {
    noeud('type-input').value = type;
    noeud('market-name-input').value = nom;
    noeud('market-value-input').value = valeur;
    noeud('pred-label').value = libelle;
  };

  // Le cas réel : « Angleterre gagne » enregistré, autre chose annoncé.
  etat('win2', '', '', 'Total fautes sur jouer : jude Bellingham plus de 1,5');
  assert.equal(context.libelleCoherent(), false);
  assert.equal(context.libelleAttendu(), 'England gagne');

  // Le libellé du type, et ses formulations équivalentes.
  etat('win2', '', '', 'England gagne');
  assert.equal(context.libelleCoherent(), true);
  etat('over25', '', '', 'Plus de 2,5 buts');
  assert.equal(context.libelleCoherent(), true, '« +2.5 buts » et « Plus de 2,5 buts » se valent');

  // Un marché de l'API : virgule ou point, espaces autour de « / », casse.
  etat('other', 'Double Chance', 'Draw/Away', 'Double chance : nul/England');
  assert.equal(context.libelleCoherent(), true);
  etat('other', 'Total - Home', 'Over 0.5', 'Total buts domicile : Plus de 0.5');
  assert.equal(context.libelleCoherent(), true);
  etat('other', 'Goals Over/Under', 'Under 6.5', 'Total fautes sur jouer : John mcGims plus de 1,5');
  assert.equal(context.libelleCoherent(), false);

  // Un marché joueur : le libellé écrit par le formulaire.
  etat('other', 'Player Fouls Drawn', 'Jude Bellingham #129718 / Over 1.5', 'Fautes subies par le joueur : Jude Bellingham / Plus de 1,5');
  assert.equal(context.libelleCoherent(), true);

  // Rétablir : le libellé du marché revient.
  etat('win2', '', '', 'Bellingham buteur');
  context.retablirLibelle();
  assert.equal(noeud('pred-label').value, 'England gagne');
  assert.equal(noeud('libelle-ecart').hidden, true);

  // Marché libre : plus de marché caché, le texte fait foi, réglé à la main.
  etat('win2', '', '', 'Total tirs cadrés de England : Plus de 4,5');
  context.marcheLibre();
  assert.equal(noeud('type-input').value, 'other');
  assert.equal(noeud('market-name-input').value, '');
  assert.equal(context.libelleCoherent(), true);
  assert.match(noeud('custom-pick-text').textContent, /régler à la main/);

  console.log('OK : le formulaire refuse un libellé qui ne décrit pas le marché enregistré ; rétablir et marché libre fonctionnent.');
})().catch(e => { console.error(e); process.exitCode = 1; });
