/**
 * Quatre corrections d'interface, et la régression qu'une d'elles a causée.
 *
 * ── Ce qui est tenu ici ───────────────────────────────────────────────────
 *
 *   1. Le mode maintenance n'est qu'un bandeau : il ne bloque ni le panneau ni
 *      l'application. Le bandeau disait « Le panel est en maintenance » à qui
 *      s'en servait, et le tableau de bord le recomptait en tâche urgente —
 *      « 2 urgents » pour une seule vraie urgence, et l'état affiché deux fois.
 *      L'ancien message d'usine, encore stocké en production, est neutralisé à
 *      la lecture plutôt qu'en réécrivant une donnée d'exploitation.
 *
 *   2. Le repli des graphiques était écrit sans accents.
 *
 *   3. Sur mobile, les onglets de la page des preuves se repliaient — « Toutes »
 *      seul sur une seconde ligne. Ils deviennent un ruban défilant, et
 *      l'onglet actif est ramené à l'écran, y compris quand la largeur change.
 *
 *   4. Sur mobile, la barre d'actions du formulaire de pronostic masquait 26 %
 *      de l'écran. Elle tient désormais sur une rangée.
 *
 * ── La régression, tenue en premier ───────────────────────────────────────
 *
 * Mettre la barre sur une rangée (`nowrap`) a d'abord cassé le cas « match
 * terminé » : la barre y porte une note et « Dépublier », et forcés côte à
 * côte, le bouton était écrasé en un filet dont le libellé débordait. Vu dans
 * un navigateur réel. Le `nowrap` ne doit viser que les barres de boutons.
 *
 * Le même test a révélé un défaut plus ancien : la réserve de place était posée
 * sur le formulaire alors que les boutons de résultat viennent après lui, si
 * bien que « Retirer du bilan » restait sous la barre fixe même en défilant
 * jusqu'au bout. La réserve est maintenant en bas de page, à la hauteur mesurée.
 *
 * Les CSS sont lus sans leurs commentaires : ceux-ci citent `nowrap`, `150px`
 * et le reste pour expliquer ce qui a été retiré.
 */
const fs     = require('fs');
const path   = require('path');
const vm     = require('vm');
const ejs    = require('ejs');
const assert = require('node:assert/strict');
const { views, opts } = require('./test_all_views.js');

const lire      = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8');
const sansComms = (t) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<%#[\s\S]*?%>/g, '');
const styles    = (ejsSrc) => [...ejsSrc.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');

function rendre(label, surcharge = {}) {
  const cas = views.find(([l]) => l === label);
  assert.ok(cas, 'jeu d’essai introuvable : ' + label);
  const [, vue, locals] = cas;
  return new Promise((ok, ko) =>
    ejs.renderFile(path.join(__dirname, 'views', vue + '.ejs'), { ...locals, ...surcharge }, opts,
      (e, h) => (e ? ko(e) : ok(h))));
}

(async () => {
  // ══ 4. La barre d'actions — la régression d'abord ═════════════════════════
  const formSrc = lire('views/pronostic_form.ejs');
  const formCss = sansComms(styles(formSrc));

  assert.doesNotMatch(formCss, /\.prono-actions\s*\{[^}]*flex-wrap:\s*nowrap/,
    'RÉGRESSION : `nowrap` appliqué à toute barre — sur un match terminé, « Dépublier » est écrasé');
  assert.match(formCss, /\.prono-actions:not\(\.termine\)\s*\{[^}]*flex-wrap:\s*nowrap/,
    'la barre de boutons doit tenir sur une rangée sur mobile');

  const termine = await rendre('pronostic_form (match termine, publie)');
  assert.match(termine, /class="prono-actions termine"/,
    'sur un match terminé, la barre doit porter la classe `termine`');
  assert.match(termine, /class="note-termine"/, 'la note du match terminé doit être ciblable');
  const enCours = await rendre('pronostic_form (edit)');
  assert.match(enCours, /class="prono-actions"/, 'hors match terminé, la barre n’est pas marquée');
  assert.doesNotMatch(enCours, /prono-actions termine/, 'hors match terminé, pas de classe `termine`');

  // La réserve : plus sous le formulaire, en bas de page, à la hauteur mesurée.
  assert.doesNotMatch(formCss, /#pro-form\s*\{[^}]*padding-bottom:\s*150px/,
    'la réserve sous le formulaire creuse un vide et laisse les boutons de résultat sous la barre');
  assert.match(formCss, /\.main\s*\{[^}]*padding-bottom:\s*calc\(\s*var\(--barre-actions/,
    'la réserve doit être en bas de page, calée sur la hauteur de la barre');
  assert.match(sansComms(formSrc), /setProperty\(\s*'--barre-actions'/,
    'la hauteur de la barre doit être mesurée — elle varie selon l’état du match');

  // Libellés courts sur mobile, longs ailleurs.
  assert.match(enCours, /<span class="lbl-long">Enregistrer les modifications<\/span><span class="lbl-court">Enregistrer<\/span>/);
  assert.match(enCours, /<span class="lbl-long">Sauvegarder brouillon<\/span><span class="lbl-court">Brouillon<\/span>/);
  assert.match(formCss, /\.lbl-court\s*\{\s*display:\s*none/, 'le libellé court est masqué par défaut');

  // ══ 1. Maintenance ════════════════════════════════════════════════════════
  const dash = await rendre('dashboard (file chargée)');     // maintenanceMode: true
  const mentions = (dash.match(/Mode maintenance actif/g) || []).length;
  assert.equal(mentions, 1, 'l’état de maintenance doit figurer une fois — dans le bandeau commun, pas aussi dans la file');
  assert.match(dash, /l'application et le panneau restent accessibles/,
    'le bandeau doit dire ce que le mode fait réellement : il ne bloque rien');
  assert.doesNotMatch(dash, /Le panel est en maintenance\./, 'l’ancien repli affirmait un blocage qui n’existe pas');
  const titres = [...dash.matchAll(/class="file-titre">([^<]*)</g)].map((m) => m[1].trim());
  assert.ok(!titres.some((t) => /maintenance/i.test(t)),
    'la maintenance n’est pas une tâche : la compter en urgence gonfle le compteur');

  const avecNote = await rendre('dashboard (file chargée)',
    { settings: { maintenanceMode: true, maintenanceMessage: 'Migration ce soir' } });
  assert.match(avecNote, /Note : « Migration ce soir »/, 'le message saisi doit apparaître comme la note d’un administrateur');

  // loadSettings neutralise l'ancien message d'usine — exécuté, pas lu.
  const serveur = lire('server.js');
  const mMsg = /const MESSAGE_MAINTENANCE_HERITE\s*=\s*\n?\s*('[^']*');/.exec(serveur);
  const mFn  = /function loadSettings\(\)\s*\{[\s\S]*?\n\}/.exec(serveur);
  assert.ok(mMsg && mFn, 'MESSAGE_MAINTENANCE_HERITE ou loadSettings introuvable dans server.js');
  const essayer = (stocke) => {
    const ctx = vm.createContext({
      DEFAULT_SETTINGS: { maintenanceMode: false, maintenanceMessage: '' },
      SETTINGS_FILE: 'x',
      fs: { readFileSync: () => JSON.stringify(stocke) },
    });
    vm.runInContext('const MESSAGE_MAINTENANCE_HERITE = ' + mMsg[1] + ';\n' + mFn[0], ctx);
    return vm.runInContext('loadSettings()', ctx);
  };
  assert.equal(essayer({ maintenanceMessage: 'Le panel est en cours de maintenance. Revenez dans quelques instants.' }).maintenanceMessage, '',
    'l’ancien message d’usine, encore stocké en production, doit être neutralisé à la lecture');
  assert.equal(essayer({ maintenanceMessage: 'Migration ce soir' }).maintenanceMessage, 'Migration ce soir',
    'un message réellement saisi ne doit pas être touché');

  // ══ 2. Repli des graphiques accentué ══════════════════════════════════════
  assert.match(dash, /La bibliothèque de graphiques n’a pas pu être chargée/,
    'le message de repli des graphiques doit être correctement écrit');
  assert.doesNotMatch(sansComms(lire('views/dashboard.ejs')), /bibliotheque n\\?'a pas pu etre/,
    'l’ancienne formulation sans accents est revenue');

  // ══ 3. Onglets en ruban ═══════════════════════════════════════════════════
  const abo = lire('views/abonnements.ejs');
  assert.match(sansComms(styles(abo)), /@media\s*\(max-width:\s*640px\)\s*\{[\s\S]*?\.pf-tabs\s*\{[^}]*flex-wrap:\s*nowrap[^}]*overflow-x:\s*auto/,
    'sur mobile, les onglets doivent former un ruban défilant, pas se replier');

  const code = /\(function \(\) \{\s*function centrer\(\)[\s\S]*?\n\}\)\(\);/.exec(abo);
  assert.ok(code, 'script de centrage du ruban introuvable');

  function monter({ scrollWidth, clientWidth, largeur }) {
    const ecouteurs = {};
    const ruban = { scrollWidth, clientWidth, offsetLeft: 12, scrollLeft: 0, querySelector: () => actif };
    const actif = { offsetLeft: 413, offsetWidth: 88 };
    const win = { innerWidth: largeur, addEventListener: (n, f) => { ecouteurs[n] = f; } };
    const ctx = vm.createContext({ window: win, document: { querySelector: () => ruban, fonts: null } });
    vm.runInContext(code[0], ctx);
    return { ruban, win, ecouteurs };
  }
  const attendu = (413 - 12) - (366 - 88) / 2;

  let m = monter({ scrollWidth: 509, clientWidth: 366, largeur: 390 });
  assert.equal(m.ruban.scrollLeft, attendu, 'le ruban qui déborde doit centrer l’onglet actif dès le chargement');

  m = monter({ scrollWidth: 300, clientWidth: 366, largeur: 800 });
  assert.equal(m.ruban.scrollLeft, 0, 'sans débordement, le ruban ne bouge pas');

  // Changement de largeur (téléphone tourné) : recentrer. Hauteur seule : non.
  m = monter({ scrollWidth: 300, clientWidth: 366, largeur: 702 });
  assert.ok(typeof m.ecouteurs.resize === 'function', 'le ruban doit suivre les changements de largeur');
  m.ruban.scrollWidth = 509; m.ruban.scrollLeft = 5;
  m.ecouteurs.resize();                              // même largeur : barre d'adresse
  assert.equal(m.ruban.scrollLeft, 5, 'un « resize » en hauteur seule ne doit pas ramener le ruban sous le doigt');
  m.win.innerWidth = 390;
  m.ecouteurs.resize();                              // largeur changée : rotation
  assert.equal(m.ruban.scrollLeft, attendu, 'un changement de largeur doit recentrer l’onglet actif');

  console.log('OK : barre d’actions sur une rangée sans écraser le cas « match terminé », réserve en bas de page, '
    + 'maintenance affichée une fois et sans urgence fictive, repli accentué, onglets en ruban recentré.');
})().catch((e) => { console.error('ÉCHEC :', e.message); process.exit(1); });
