/**
 * Dépublier ne doit jamais passer par une écriture complète.
 *
 * Le bouton « Dépublier » ajoutait `publish=false` au formulaire d'édition et
 * le soumettait. Ce chemin traverse `upsertPronostic`, qui porte ce garde-fou :
 *
 *     if (match.status === 'FINISHED')
 *       throw new Error('Impossible de créer un pronostic pour un match terminé.')
 *
 * Écrit pour empêcher de *créer* un pronostic après coup, il bloquait aussi le
 * simple retrait — c'est-à-dire précisément dans le cas où l'on veut retirer un
 * pronostic de la vitrine. La boîte de confirmation s'ouvrait, on confirmait,
 * et rien ne se passait.
 *
 * Rien ne pouvait le voir : le gabarit était valide, la page se rendait, et le
 * bouton n'apparaissait dans aucun jeu d'essai — il exige `pro.id`, absent du
 * seul cas « edit » existant.
 *
 *   node _check_depublication.js
 */
const fs   = require('fs');
const { parse } = require('node-html-parser');
const ejs  = require('ejs');
const { views, opts } = require('./test_all_views.js');

const griefs = [];

(async () => {
  const source = fs.readFileSync('views/pronostic_form.ejs', 'utf8');

  // ── 1. Le script ne doit plus détourner le formulaire d'édition ───────────
  const depublish = source.slice(source.indexOf('function depublish'));
  const corps = depublish.slice(0, depublish.indexOf('\n}') + 2);
  if (/pro-form/.test(corps)) {
    griefs.push('depublish() vise encore #pro-form : la dépublication repasserait '
              + 'par une écriture complète, refusée sur un match terminé.');
  }
  if (/name\s*=\s*['"]publish['"]/.test(corps) || /'publish'/.test(corps)) {
    griefs.push('depublish() fabrique encore un champ « publish » : c\'est la '
              + 'signature de l\'ancien chemin.');
  }

  // ── 2. Le rendu doit exposer un formulaire dédié, hors du formulaire ──────
  let rendus = 0;
  for (const [nom, vue, locals] of views) {
    if (vue !== 'pronostic_form') continue;
    let html;
    try { html = await ejs.renderFile('views/pronostic_form.ejs', locals, opts); }
    catch { continue; }

    const d = parse(html);
    const bouton = d.querySelectorAll('button').some(b => /Dépublier/.test(b.text));
    if (!bouton) continue;
    rendus++;

    const dedie = d.querySelector('#form-depublier');
    if (!dedie) {
      griefs.push(`${nom} : bouton « Dépublier » présent sans formulaire dédié.`);
      continue;
    }
    // Un formulaire imbriqué dans un autre est ignoré par le navigateur : la
    // soumission ne partirait nulle part.
    if (d.querySelector('#pro-form #form-depublier')) {
      griefs.push(`${nom} : #form-depublier est imbriqué dans #pro-form — le `
                + `navigateur ignore un formulaire dans un formulaire.`);
    }
    const action = dedie.getAttribute('action') ?? '';
    if (!/\/depublier$/.test(action)) {
      griefs.push(`${nom} : #form-depublier pointe vers « ${action} » et non `
                + `vers la route de dépublication.`);
    }
  }

  if (rendus === 0) {
    console.log('ANALYSEUR DÉFAILLANT — aucun rendu ne fait apparaître le bouton.\n'
              + '  Le bouton exige `pro.id` et `pro.is_published` : sans jeu '
              + 'd\'essai correspondant, ce contrôle ne prouve rien.');
    process.exitCode = 2;
    return;
  }

  console.log(`${rendus} rendu(s) avec le bouton « Dépublier »`);
  if (griefs.length === 0) {
    console.log('\nLa dépublication ne passe pas par une écriture complète.');
  } else {
    console.log(`\n${griefs.length} problème(s) :`);
    [...new Set(griefs)].forEach(g => console.log('  · ' + g));
    process.exitCode = 1;
  }
})();
