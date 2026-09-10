/**
 * Aucun champ de saisie n'affiche une casse différente de ce qu'il enregistre.
 *
 * La page « Code promo » posait `text-transform: uppercase` sur tous ses
 * champs. Le nom du partenaire saisi « 1xbet » s'affichait donc « 1XBET », et
 * l'application montrait ensuite « 1xbet » aux utilisateurs. Le formulaire
 * mentait sur son propre contenu, et rien depuis cette page ne permettait de
 * s'en apercevoir : on relit ce qu'on vient de taper, on voit des capitales,
 * on conclut que des capitales ont été enregistrées.
 *
 * `text-transform` reste légitime partout ailleurs — étiquettes, en-têtes de
 * tableau, badges. Ce sont des textes qu'on lit, pas des valeurs qu'on
 * enregistre. La règle ne vise donc que les sélecteurs qui touchent un
 * `input` ou un `textarea`.
 *
 *   node _check_casse_affichee.js
 */
const fs   = require('fs');
const path = require('path');

const DOSSIER = path.join(__dirname, 'views');

/** Un bloc `sélecteur { … }` dont le sélecteur mentionne input/textarea. */
const REGLE = /([^{}]+)\{([^}]*)\}/g;

const fautifs = [];

function parcourir(dossier) {
  for (const entree of fs.readdirSync(dossier, { withFileTypes: true })) {
    const chemin = path.join(dossier, entree.name);
    if (entree.isDirectory()) { parcourir(chemin); continue; }
    if (!entree.name.endsWith('.ejs')) continue;

    const source = fs.readFileSync(chemin, 'utf8');

    // Seulement ce qui est entre <style> … </style> : le reste du fichier
    // contient du texte et des accolades EJS qui ne sont pas du CSS.
    for (const bloc of source.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
      // Les commentaires CSS expliquent souvent le défaut en le citant.
      const css = bloc[1].replace(/\/\*[\s\S]*?\*\//g, '');

      for (const regle of css.matchAll(REGLE)) {
        const selecteur = regle[1].trim();
        const corps     = regle[2];

        if (!/\b(input|textarea)\b/.test(selecteur)) continue;
        if (!/text-transform\s*:\s*(uppercase|lowercase|capitalize)/.test(corps)) continue;

        fautifs.push(`${path.relative(__dirname, chemin).replace(/\\/g, '/')} `
                   + `→ ${selecteur.replace(/\s+/g, ' ')}`);
      }
    }

    // Le même défaut posé en style en ligne sur un champ.
    for (const balise of source.matchAll(/<(?:input|textarea)\b[^>]*>/gi)) {
      if (/style\s*=\s*"[^"]*text-transform\s*:\s*(uppercase|lowercase|capitalize)/i
            .test(balise[0])) {
        fautifs.push(`${path.relative(__dirname, chemin).replace(/\\/g, '/')} `
                   + `→ style en ligne sur un champ`);
      }
    }
  }
}

parcourir(DOSSIER);

console.log('');
if (fautifs.length) {
  console.log('  ÉCHEC — champ(s) affichant une casse différente de la valeur saisie :\n');
  for (const f of fautifs) console.log(`    ${f}`);
  console.log('\n  Un formulaire doit montrer ce qu\'il enregistre. Si la valeur');
  console.log('  doit être normalisée, faites-le à l\'enregistrement, pas à l\'affichage.\n');
  process.exit(1);
}

console.log('  OK — aucun champ n\'affiche une casse différente de ce qu\'il enregistre\n');
