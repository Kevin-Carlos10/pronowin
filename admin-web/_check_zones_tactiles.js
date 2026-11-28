/**
 * Ce qu'on touche au doigt doit être assez grand, et un champ ne doit pas
 * faire zoomer la page.
 *
 * ── Ce qui a été mesuré ───────────────────────────────────────────────────
 *
 * Sur un écran de 390 px, dans la barre partagée par toutes les pages : menu
 * 26 × 26, recherche 34 × 26 ; dans le tiroir, bascule de thème 28 × 20 ; dans
 * le bandeau de maintenance, lien 79 × 19. La bascule de thème passait même
 * sous le plancher WCAG 2.5.8 (24 px), ordinateur compris.
 *
 * Et la règle de base fixait 13 px pour tous les champs du panneau. Safari sur
 * iPhone zoome toute la page dès qu'on touche un champ sous 16 px : chaque
 * formulaire, à chaque champ, puis dézoomer à la main pour continuer.
 *
 * ── Ce que ce contrôle tient ──────────────────────────────────────────────
 *
 *   1. le plancher de 16 px sur les champs, sur écran tactile, et qui l'emporte
 *      sur les tailles fixées par classe dans les pages ;
 *   2. les zones de 44 px du menu et de la recherche ;
 *   3. le plancher de 24 px partout, et 44 px au doigt, pour la bascule de
 *      thème et le lien du bandeau.
 *
 * Il lit la feuille de style **sans ses commentaires** : ceux qui expliquent
 * ces règles citent « 16 px » et « 44 px », et un contrôle qui les lirait se
 * validerait sur sa propre explication.
 *
 * ── Ce qu'il ne remplace pas ──────────────────────────────────────────────
 *
 * Qu'une icône n'ait pas bougé, qu'une zone agrandie ne déborde pas sur un
 * voisin : cela a été mesuré dans un navigateur réel (centres des icônes
 * inchangés à 27 et 207 px, sondes `elementFromPoint` sans empiétement). Un
 * contrôle textuel ne sait pas le dire.
 */
const fs     = require('fs');
const path   = require('path');
const assert = require('node:assert/strict');

const brut = fs.readFileSync(path.join(__dirname, 'public', 'style.css'), 'utf8');
const css  = brut.replace(/\/\*[\s\S]*?\*\//g, '');
const compact = (t) => t.replace(/\s+/g, ' ').trim();

/** Le contenu du premier bloc `@media (pointer: coarse)`, accolades équilibrées. */
function blocTactile() {
  const debut = css.search(/@media\s*\(\s*pointer\s*:\s*coarse\s*\)\s*\{/);
  assert.ok(debut >= 0, 'aucun bloc @media (pointer: coarse) — les planchers tactiles ont disparu');
  let i = css.indexOf('{', debut) + 1, niveau = 1;
  const ouverture = i;
  for (; i < css.length && niveau > 0; i++) {
    if (css[i] === '{') niveau++;
    else if (css[i] === '}') niveau--;
  }
  return compact(css.slice(ouverture, i - 1));
}

/** Les déclarations d'une règle hors média, pour un sélecteur exact. */
function declarations(selecteur) {
  const echappe = selecteur.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp('(^|[}\\s,])' + echappe + '\\s*(,[^{]*)?\\{([^}]*)\\}', 'g');
  return [...css.matchAll(re)].map((m) => compact(m[3])).join(' ; ');
}

const tactile = blocTactile();

// ── 1. Le plancher de 16 px sur les champs ─────────────────────────────────
assert.match(tactile, /input\s*,\s*select\s*,\s*textarea\s*\{\s*font-size:\s*16px\s*!important/,
  'sur écran tactile, input/select/textarea doivent tenir 16 px — sinon Safari zoome à chaque champ');

// ── 2. Menu et recherche : 44 px ───────────────────────────────────────────
const zones = declarations('.search-trigger-btn') + ' ; ' + declarations('.hamburger');
assert.match(zones, /min-width:\s*44px/,  'le menu et la recherche doivent offrir 44 px de large');
assert.match(zones, /min-height:\s*44px/, 'le menu et la recherche doivent offrir 44 px de haut');

// ── 3. Bascule de thème et lien du bandeau : 24 px partout, 44 au doigt ───
assert.match(declarations('.mode-btn'), /min-height:\s*24px/,
  'la bascule de thème doit atteindre le plancher WCAG 2.5.8 (24 px), ordinateur compris');
assert.match(declarations('.bandeau-lien'), /min-height:\s*24px/,
  'le lien du bandeau doit atteindre 24 px');
assert.match(tactile, /\.mode-btn\s*\{[^}]*min-height:\s*44px/,     'bascule de thème : 44 px au doigt');
assert.match(tactile, /\.bandeau-lien\s*\{[^}]*min-height:\s*44px/, 'lien du bandeau : 44 px au doigt');

// Le lien doit porter la classe, sinon la règle ne s'applique à rien.
const gabarit = fs.readFileSync(path.join(__dirname, 'views', 'layout_top.ejs'), 'utf8');
assert.match(gabarit, /<a href="\/admin\/settings" class="bandeau-lien"/,
  'le lien « Désactiver » du bandeau a perdu sa classe : sa zone tactile n’est plus agrandie');

console.log('OK : champs à 16 px au doigt, menu et recherche à 44 px, '
  + 'bascule de thème et lien du bandeau à 24 px (44 au doigt).');
