/**
 * Le formulaire refuse de publier un pronostic sous la cote minimale — et
 * laisse passer tout le reste.
 *
 * ── Pourquoi un contrôle côté formulaire, alors que le serveur refuse déjà ──
 *
 * Le serveur est l'autorité : `verifierCotePublication` refuse, quel que soit
 * le chemin. Mais un refus serveur recharge le formulaire depuis la base, et
 * l'administrateur perd l'analyse qu'il vient d'écrire. Le formulaire doit
 * donc l'arrêter avant l'envoi.
 *
 * ── Ce que ce contrôle tient ──────────────────────────────────────────────
 *
 *   1. le seuil du formulaire est celui du serveur — deux copies d'un même
 *      nombre finissent toujours par diverger, et c'est alors le formulaire
 *      qui laisse passer ce que le serveur refuse, ou l'inverse ;
 *   2. « Publier » est retenu sous le seuil, « brouillon » jamais ;
 *   3. l'avertissement suit la cote, qu'elle soit saisie ou remplie par
 *      programme — ce second cas n'émet pas d'événement « input » ;
 *   4. après un refus, l'avertissement n'est pas laissé sous la barre
 *      d'actions fixée en bas de l'écran. Constaté sur un écran étroit :
 *      centrer le champ laissait l'explication, juste en dessous, recouverte.
 *
 * Le code exécuté est celui de la vue rendue, extrait tel quel : un contrôle
 * qui recopierait la logique ne testerait que sa copie.
 */
const fs     = require('fs');
const path   = require('path');
const vm     = require('vm');
const ejs    = require('ejs');
const assert = require('node:assert/strict');
const { views, opts } = require('./test_all_views.js');

// ── 1. Un seul seuil ─────────────────────────────────────────────────────────
const serveur = fs.readFileSync(
  path.join(__dirname, '..', 'backend', 'src', 'services', 'pronostics.service.ts'), 'utf8');
const mServeur = /export const COTE_MINIMALE_PUBLICATION\s*=\s*([\d.]+)/.exec(serveur);
assert.ok(mServeur, 'COTE_MINIMALE_PUBLICATION introuvable côté serveur');

const vue = fs.readFileSync(path.join(__dirname, 'views', 'pronostic_form.ejs'), 'utf8');
const mVue = /const COTE_MINIMALE_PUBLICATION\s*=\s*([\d.]+)/.exec(vue);
assert.ok(mVue, 'COTE_MINIMALE_PUBLICATION introuvable dans le formulaire');
assert.equal(Number(mVue[1]), Number(mServeur[1]),
  'le formulaire et le serveur ne refusent pas à la même cote');

// ── Le script réel, extrait de la vue rendue ────────────────────────────────
function rendre(cote) {
  const [, nom, locals] = views.find(([l]) => l === 'pronostic_form (edit)');
  const match = JSON.parse(JSON.stringify(locals.match));
  match.pronostic = { ...match.pronostic, odds_recommended: cote, is_published: false };
  return new Promise((ok, ko) =>
    ejs.renderFile(path.join(__dirname, 'views', nom + '.ejs'), { ...locals, match }, opts,
      (err, html) => (err ? ko(err) : ok(html))));
}

function extraire(html) {
  const debut = html.indexOf('const COTE_MINIMALE_PUBLICATION');
  const fin   = html.indexOf('/* Note éditoriale', debut);
  assert.ok(debut > 0 && fin > debut,
    'bloc de la cote minimale introuvable dans le rendu — le contrôle ne vérifierait rien');
  return html.slice(debut, fin);
}

/** Un DOM réduit aux quatre éléments que le bloc touche. */
function monter(code, { coteInitiale = '', alerteBas = 236, barreHaut = 271, barreFixe = true } = {}) {
  const ecouteurs = {};
  const defilements = [];
  const champ = {
    value: coteInitiale, focusOpts: null, centre: false,
    addEventListener: (n, f) => { ecouteurs['champ:' + n] = f; },
    focus(o) { this.focusOpts = o ?? {}; },
    // Présent pour qu'un retour à l'ancien comportement — centrer le champ —
    // échoue sur l'assertion qui le décrit, et non sur un simulacre incomplet.
    scrollIntoView() { this.centre = true; },
  };
  const alerte = {
    hidden: true, textContent: '', centre: false,
    scrollIntoView() { this.centre = true; },
    getBoundingClientRect: () => ({ top: alerteBas - 38, bottom: alerteBas }),
  };
  const barre = { getBoundingClientRect: () => ({ top: barreHaut }) };
  const form  = { addEventListener: (n, f) => { ecouteurs['form:' + n] = f; } };
  const document = {
    getElementById: (id) => ({ 'odds-rec': champ, 'odds-rec-seuil': alerte, 'pro-form': form }[id] ?? null),
    querySelector: (s) => (s === '.prono-actions' ? barre : null),
  };
  const ctx = vm.createContext({
    document,
    getComputedStyle: () => ({ position: barreFixe ? 'fixed' : 'static' }),
    window: { scrollBy: (x, y) => defilements.push(y) },
  });
  vm.runInContext(code, ctx);
  return { ecouteurs, champ, alerte, defilements, ctx };
}

function soumettre(m, cote, bouton) {
  m.champ.value = cote;
  let bloque = false;
  m.ecouteurs['form:submit']({ submitter: bouton, preventDefault: () => { bloque = true; } });
  return bloque;
}

const PUBLIER   = { name: 'publish', value: 'true' };
const BROUILLON = { name: 'publish', value: 'false' };

(async () => {
  const code = extraire(await rendre(1.85));

  // ── 2. Publier est retenu sous le seuil, brouillon jamais ─────────────────
  let m = monter(code);
  assert.equal(soumettre(m, '1.15', PUBLIER), true,  'publier à 1,15 doit être retenu');
  assert.equal(soumettre(m, '1.19', PUBLIER), true,  'publier à 1,19 doit être retenu');
  assert.equal(soumettre(m, '1.20', PUBLIER), false, 'publier à 1,20 : le seuil lui-même est permis');
  assert.equal(soumettre(m, '1.85', PUBLIER), false, 'publier à 1,85 doit passer');
  assert.equal(soumettre(m, '1.15', BROUILLON), false, 'un brouillon à 1,15 doit passer');
  assert.equal(soumettre(m, '1.01', BROUILLON), false, 'un brouillon à 1,01 doit passer');
  // Soumission sans bouton identifié (navigateur ancien) : le serveur tranche.
  assert.equal(soumettre(m, '1.15', null), false, 'sans soumetteur connu, on laisse le serveur décider');

  // ── 3. L'avertissement suit la cote ───────────────────────────────────────
  m = monter(code);
  m.champ.value = '1.18';
  m.ecouteurs['champ:input']();
  assert.equal(m.alerte.hidden, false, 'saisie à 1,18 : avertissement attendu');
  assert.match(m.alerte.textContent, /1,18/);
  assert.match(m.alerte.textContent, /85 %/, 'le seuil d’équilibre est calculé depuis la cote');
  assert.match(m.alerte.textContent, /brouillon/);
  m.champ.value = '1.50';
  m.ecouteurs['champ:input']();
  assert.equal(m.alerte.hidden, true, 'à 1,50 l’avertissement doit disparaître');
  m.champ.value = '';
  m.ecouteurs['champ:input']();
  assert.equal(m.alerte.hidden, true, 'champ vide : rien à dire tant qu’on tape');

  // Remplissage par programme : `setRecommendedOdd` appelle `etatCote`
  // directement, puisqu'aucun événement n'est émis.
  m.champ.value = '1.12';
  vm.runInContext('etatCote()', m.ctx);
  assert.equal(m.alerte.hidden, false, 'remplissage à 1,12 : avertissement attendu');
  assert.match(vue, /function setRecommendedOdd[\s\S]*?etatCote\(\);[\s\S]*?\n\}/,
    'setRecommendedOdd doit rafraîchir l’avertissement — il n’émet pas « input »');
  assert.match(vue, /\/\/ Un brouillon enregistré sous le seuil[^\n]*\n\s*etatCote\(\);/,
    'un brouillon déjà enregistré sous le seuil doit l’annoncer à l’ouverture');

  // ── 4. Après un refus : focus sur le champ, explication dégagée ───────────
  m = monter(code, { alerteBas: 305, barreHaut: 271 });   // mesuré : recouvert
  soumettre(m, '1.15', PUBLIER);
  assert.equal(m.alerte.centre, true, 'c’est l’avertissement qu’on amène à l’écran');
  // La propriété, pas l'objet : il est créé dans la VM, avec un prototype
  // d'un autre royaume, et une égalité profonde stricte le refuserait à tort.
  assert.equal(m.champ.focusOpts?.preventScroll, true,
    'le focus ne doit pas redéfiler vers le seul champ');
  assert.deepEqual(m.defilements, [305 - 271 + 12],
    'l’avertissement recouvert doit être remonté au-dessus de la barre');

  m = monter(code, { alerteBas: 236, barreHaut: 271 });   // déjà visible
  soumettre(m, '1.15', PUBLIER);
  assert.deepEqual(m.defilements, [], 'rien à remonter quand rien n’est recouvert');

  m = monter(code, { alerteBas: 305, barreHaut: 271, barreFixe: false });
  soumettre(m, '1.15', PUBLIER);
  assert.deepEqual(m.defilements, [], 'barre non fixée (grand écran) : aucune correction');

  console.log('OK : seuil commun au serveur, publication retenue sous 1,20, brouillon libre, '
    + 'avertissement suivi, explication dégagée de la barre.');
})().catch((e) => { console.error('ÉCHEC :', e.message); process.exit(1); });
