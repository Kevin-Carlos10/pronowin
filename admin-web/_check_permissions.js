/**
 * Contrôle du rendu des pastilles de permission.
 *
 * Trois vues affichent les libellés de `PERMISSIONS`, et deux d'entre elles les
 * retaillaient pour retirer l'emoji de tête : `replace(/^\S+\s/,'')` dans
 * sub_admins.ejs, `split(' ').slice(1)` dans profile.ejs. Le jour où les
 * libellés ont perdu leur emoji, le premier s'est mis à manger le nom du
 * module et le second à rendre une pastille vide — sans la moindre erreur de
 * rendu. `test_all_views.js` continuait d'afficher « 42/42 vues OK ».
 *
 * Ici on lit le HTML produit : chaque pastille doit porter une icône de niveau
 * existante ET un libellé exactement égal à celui du catalogue.
 *
 *   node _check_permissions.js
 */
const path = require('path');
const ejs  = require('ejs');
const { PERMISSIONS } = require('./lib/permissions');
const { views, opts } = require('./test_all_views.js');

const ATTENDUS = PERMISSIONS.map(p => p.label);
const NIVEAUX  = ['read', 'write', 'delete'];

/**
 * Les fixtures n'accordent qu'une permission : elles ne prouveraient qu'un
 * libellé sur dix. On en dérive un cas qui les accorde toutes, en alternant les
 * trois niveaux pour que les trois icônes passent aussi par le rendu.
 */
function toutesPermissions(source, champ) {
  const cas = views.find(v => v[0] === source);
  if (!cas) return null;
  const toutes = PERMISSIONS.map((p, i) => p.key + ':' + NIVEAUX[i % 3]);
  const locals = { ...cas[2] };
  if (champ === 'adminPerms') locals.adminPerms = toutes;
  else locals.subs = [{ ...cas[2].subs[0], permissions: toutes }];
  return [source + ' — toutes permissions', cas[1], locals, PERMISSIONS.length];
}

const CAS = [
  ['sub_admins', 'sub_admins', null, 1],
  ['profile (sub-admin)', 'profile', null, 1],
  toutesPermissions('sub_admins', 'subs'),
  toutesPermissions('profile (sub-admin)', 'adminPerms'),
].filter(Boolean);

const texte = p => p.replace(/<svg[\s\S]*?<\/svg>/g, '').trim();
let echecs = 0;

(async () => {
  for (const [label, vue, locauxForces, attendu] of CAS) {
    const locaux = locauxForces ?? views.find(v => v[0] === label)[2];
    const html = await ejs.renderFile('views/' + vue + '.ejs', locaux, opts);

    const pastilles = [...html.matchAll(
      /<span class="perm-(?:tag|badge) [^"]*">([\s\S]*?)<\/span>/g)].map(m => m[1]);

    const problemes = [];
    if (pastilles.length !== attendu)
      problemes.push(`${pastilles.length} pastilles au lieu de ${attendu}`);

    const sansIcone = pastilles.filter(p => !/<use href="#ic-(?:trash|edit|eye)"\/>/.test(p));
    if (sansIcone.length) problemes.push(`${sansIcone.length} sans icône de niveau`);

    const vides = pastilles.filter(p => texte(p) === '');
    if (vides.length) problemes.push(`${vides.length} à libellé vide`);

    const inconnus = [...new Set(pastilles.map(texte).filter(t => t && !ATTENDUS.includes(t)))];
    if (inconnus.length) problemes.push('libellés hors catalogue : ' + inconnus.join(', '));

    if (problemes.length) { console.log('  KO  ' + label + ' : ' + problemes.join(' ; ')); echecs++; }
    else console.log(`  ok  ${label.padEnd(34)} ${pastilles.length} pastilles, icône + libellé complet`);
  }

  console.log(echecs ? `\n${echecs} cas en échec.` : '\nRendu des permissions conforme au catalogue.');
  process.exitCode = echecs ? 1 : 0;
})();
