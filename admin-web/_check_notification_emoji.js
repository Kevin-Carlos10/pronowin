/**
 * Le panneau ne conseille ni ne pré-remplit d'emoji.
 *
 * Les notifications automatiques de l'application n'en portent plus — dix-neuf
 * titres ont été nettoyés dans sept services du backend, et un contrôle les y
 * garde (`notifications_sans_emoji.test.ts`).
 *
 * Cette page-ci disait pourtant l'inverse à l'opérateur :
 *
 *     <li>😀 Un emoji en tête de titre booste l'ouverture</li>
 *
 * et ses cinq modèles rapides pré-remplissaient chacun un titre orné —
 * « 🎯 Nouveau pronostic disponible ! », « 🏆 Pronostic gagnant ! ». Un clic,
 * et la campagne partait ornée.
 *
 * Nettoyer le backend sans toucher à cette page aurait donc produit exactement
 * le défaut que ce dépôt corrige depuis des semaines : une règle appliquée
 * d'un côté, et contredite de l'autre, à l'endroit précis où quelqu'un s'en
 * remet à l'outil.
 *
 * Le corps du message n'est pas contrôlé : l'emoji y est moins voyant, et
 * c'est le titre que la capture montre sur l'écran de verrouillage.
 *
 *   node _check_notification_emoji.js
 */
const fs = require('fs');
const path = require('path');

const VUE = 'views/notifications.ejs';
const source = fs.readFileSync(path.join(__dirname, VUE), 'utf8');

// Pictogrammes et symboles décoratifs. Ni les lettres accentuées, ni les
// guillemets français, ni les tirets cadratins : ce n'est pas la ponctuation
// qu'on chasse.
const EMOJI =
  /[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]/u;

const echecs = [];
const ok = (m) => console.log('  OK    ' + m);
const ko = (m) => { echecs.push(m); console.log('  ECHEC ' + m); };

/* ─── Contrepartie : le motif reconnaît-il quelque chose ? ─────────────── */
//
// Sans elle, une expression cassée ferait passer tous les contrôles en
// n'ayant rien regardé.
if (EMOJI.test('😀') && EMOJI.test('🏆') && !EMOJI.test('Résultat : gagnant !')) {
  ok('le motif distingue un pictogramme de la ponctuation française');
} else {
  ko('le motif ne reconnaît pas ce qu\'il devrait — les contrôles suivants ne prouvent rien');
}

/* ─── Les modèles rapides ──────────────────────────────────────────────── */
//
// Le tableau est littéral dans la vue : chaque entrée vaut
// [libellé du bouton, titre pré-rempli, corps pré-rempli].
const modeles = [...source.matchAll(/^\s*\['([^']*)', '((?:[^'\\]|\\.)*)',/gm)];

if (modeles.length < 3) {
  ko(`seulement ${modeles.length} modèle(s) rapide(s) trouvé(s) : la vue a changé de forme, ce contrôle ne regarde plus rien`);
} else {
  const ornes = modeles
    .filter(([, libelle, titre]) => EMOJI.test(libelle) || EMOJI.test(titre))
    .map(([, libelle, titre]) => `« ${libelle} » / « ${titre} »`);

  if (ornes.length) {
    ko(`modèle(s) rapide(s) avec emoji : ${ornes.join(', ')}`);
  } else {
    ok(`${modeles.length} modèles rapides, aucun emoji`);
  }
}

/* ─── Les conseils affichés à l'opérateur ──────────────────────────────── */
const conseils = [...source.matchAll(/<li>([\s\S]*?)<\/li>/g)].map((m) => m[1]);

if (!conseils.length) {
  ko('aucune liste de conseils trouvée : la vue a changé de forme');
} else {
  const fautifs = conseils.filter((c) => EMOJI.test(c));
  if (fautifs.length) {
    ko(`conseil(s) avec emoji : ${fautifs.map((c) => c.replace(/<[^>]*>/g, '').trim()).join(' | ')}`);
  } else {
    ok(`${conseils.length} conseils, aucun emoji`);
  }
}

/* ─── Et le conseil contraire ne revient pas ───────────────────────────── */
if (/emoji[^<]{0,40}(booste|augmente|améliore)/i.test(source)) {
  ko('la page conseille de nouveau d\'ajouter un emoji au titre');
} else {
  ok('aucun conseil n\'invite à ajouter un emoji');
}

console.log(`\n${echecs.length ? echecs.length + ' problème(s)' : 'Tous les contrôles passent'}\n`);
process.exit(echecs.length ? 1 : 0);
