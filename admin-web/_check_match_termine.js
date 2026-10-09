/**
 * Match terminé : l'écran doit dire la même chose que le serveur.
 *
 * `upsertPronostic` refuse toute écriture sur un match terminé :
 *
 *     if (match.status === 'FINISHED')
 *       throw new Error('Impossible de créer un pronostic pour un match terminé.')
 *
 * L'écran, lui, laissait tous les champs actifs et proposait « Publier
 * maintenant ». On saisissait, on validait, et rien n'était enregistré — avec,
 * en prime, un message d'erreur parlant de *création* alors qu'on modifiait.
 *
 * Deux actions doivent rester possibles, parce qu'elles ne passent pas par
 * cette écriture : dépublier (route dédiée) et corriger le résultat.
 *
 *   node _check_match_termine.js
 */
const { parse } = require('node-html-parser');
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

const griefs = [];

(async () => {
  let termines = 0, ouverts = 0;

  const base = views.find(([nom]) => nom === 'pronostic_form (edit)');
  const publieAvantMatch = ['publication figée avant match', 'pronostic_form', {
    ...base[2], match: { ...base[2].match, status: 'SCHEDULED',
      pronostic: { ...base[2].match.pronostic, is_published: true,
        publicationRecordedAt: '2026-10-08T12:00:00Z' } },
  }];
  for (const [nom, vue, locals] of [...views, publieAvantMatch]) {
    if (vue !== 'pronostic_form') continue;
    let html;
    try { html = await ejs.renderFile('views/pronostic_form.ejs', locals, opts); }
    catch { continue; }

    const d  = parse(html);
    const pf = d.querySelector('#pro-form');
    if (!pf) continue;

    const fini = String(locals.match?.status ?? '').toUpperCase() === 'FINISHED';
    const soumissions = pf.querySelectorAll('button[type="submit"]').length;
    const jeu = pf.querySelector('fieldset');

    if (fini || locals.match?.pronostic?.publicationRecordedAt) {
      termines++;
      if (soumissions > 0) {
        griefs.push(`${nom} : ${soumissions} bouton(s) de soumission sur un match `
                  + `terminé — ils ne peuvent que échouer.`);
      }
      if (!jeu || jeu.getAttribute('disabled') === undefined) {
        griefs.push(`${nom} : les champs ne sont pas désactivés — l'écran invite `
                  + `à saisir ce que le serveur refusera.`);
      }
      // La dépublication reste légitime : c'est même le geste principal sur un
      // match terminé.
      const publie = locals.match?.pronostic?.is_published;
      if (publie) {
        const dep = pf.querySelectorAll('button').some(b => /Dépublier/.test(b.text));
        if (!dep) {
          griefs.push(`${nom} : plus aucun moyen de dépublier un pronostic publié `
                    + `sur un match terminé.`);
        }
      }
      // L'utilisateur doit savoir pourquoi, et quoi faire à la place.
      const texte = d.text.replace(/\s+/g, ' ');
      if (!/verrouill|n'est plus modifiable/i.test(texte)) {
        griefs.push(`${nom} : rien n'explique pourquoi le formulaire est inerte.`);
      }
      if (d.querySelector('input[name="result"][value="null"]')) {
        griefs.push(nom + ' : un résultat peut encore être retiré du bilan.');
      }
      const corrections = d.querySelectorAll('input[name="result"]')
        .map(input => input.getAttribute('value'));
      if (fini && locals.match?.pronostic?.id && !['WIN','LOSS','PUSH'].every(v => corrections.includes(v))) {
        griefs.push(nom + ' : une correction de verdict manque.');
      }
    } else {
      ouverts++;
      if (soumissions === 0) {
        griefs.push(`${nom} : match non terminé mais aucun bouton de soumission.`);
      }
      if (jeu && jeu.getAttribute('disabled') !== undefined) {
        griefs.push(`${nom} : champs désactivés alors que le match n'est pas terminé.`);
      }
    }
  }

  // Sans les deux cas, la comparaison ne prouve rien.
  if (termines === 0 || ouverts === 0) {
    console.log(`ANALYSEUR DÉFAILLANT — ${termines} rendu(s) terminé(s), `
              + `${ouverts} ouvert(s) : il faut les deux pour comparer.`);
    process.exitCode = 2;
    return;
  }

  console.log(`${termines} formulaire(s) verrouillé(s) et ${ouverts} ouvert(s) examinés`);
  if (griefs.length === 0) {
    console.log('\nL\'écran refuse ce que le serveur refuse, et le dit.');
  } else {
    console.log(`\n${griefs.length} problème(s) :`);
    [...new Set(griefs)].forEach(g => console.log('  · ' + g));
    process.exitCode = 1;
  }
})();
