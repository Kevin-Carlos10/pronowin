/**
 * Structure : ce qu'un bloc n'a pas le droit de contenir.
 *
 * Défaut d'origine, sur la page Pronostics : la bannière « Pronostic gratuit du
 * jour » — une carte pleine largeur — était écrite **à l'intérieur** de la
 * tuile « Brouillons », entre son libellé et sa valeur.
 *
 * Rien ne le signalait. Le gabarit était valide, la vue se rendait sans erreur,
 * les sept contrôles existants passaient. À l'écran, en revanche : le texte
 * débordait sur la tuile voisine et s'y faisait couper au milieu des mots, et
 * le compteur de brouillons était repoussé hors de la tuile.
 *
 * Les expressions régulières ne peuvent pas répondre à cette question : une
 * recherche « une carte à moins de N caractères d'une tuile » traverse les
 * balises fermantes et déclenche sur du code parfaitement correct — c'est ce
 * qu'a fait ma première tentative. Il faut l'arbre.
 *
 *   node _check_imbrication.js
 */
const { parse } = require('node-html-parser');
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

/**
 * Conteneurs étroits, et ce qu'on n'y met jamais.
 *
 * Une tuile de statistique fait une fraction de la largeur : y placer un bloc
 * conçu pour occuper toute la page produit un débordement systématique.
 */
const REGLES = [
  { hote: '.pro-stat',   interdit: '.card',      pourquoi: 'tuile de statistique' },
  { hote: '.pro-stat',   interdit: '.pro-stats', pourquoi: 'tuile de statistique' },
  { hote: '.stat-tile',  interdit: '.card',      pourquoi: 'tuile de statistique' },
  { hote: '.badge',      interdit: '.card',      pourquoi: 'badge' },
  { hote: '.bottom-nav', interdit: '.card',      pourquoi: 'barre de navigation' },
];

(async () => {
  const griefs = [];
  let examinees = 0;

  for (const [nom, vue, locals] of views) {
    let html;
    try { html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts); }
    catch { continue; }

    const racine = parse(html);
    examinees++;

    for (const regle of REGLES) {
      for (const hote of racine.querySelectorAll(regle.hote)) {
        const intrus = hote.querySelectorAll(regle.interdit);
        if (intrus.length === 0) continue;

        // Un extrait du texte aide à retrouver le bloc dans le gabarit.
        const extrait = intrus[0].text.replace(/\s+/g, ' ').trim().slice(0, 60);
        griefs.push(
          `${nom} : « ${regle.interdit} » imbriqué dans une ${regle.pourquoi} ` +
          `(${regle.hote}) — « ${extrait}… »`);
      }
    }
  }

  // L'analyseur doit prouver qu'il a lu quelque chose : sans vues examinées,
  // « aucun problème » ne veut rien dire.
  if (examinees < 20) {
    console.log(`ANALYSEUR DÉFAILLANT — seulement ${examinees} vues rendues.`);
    process.exitCode = 2;
    return;
  }

  console.log(`${examinees} vues analysées`);
  if (griefs.length === 0) {
    console.log('\nAucun bloc pleine largeur enfermé dans un conteneur étroit.');
  } else {
    console.log(`\n${griefs.length} imbrication(s) impossible(s) :`);
    [...new Set(griefs)].forEach(g => console.log('  · ' + g));
    process.exitCode = 1;
  }
})();
