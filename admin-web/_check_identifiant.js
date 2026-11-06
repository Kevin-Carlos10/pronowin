/**
 * Un sous-admin se connecte avec l'identifiant qu'on lui a donné.
 *
 * La création enregistrait `username.trim().toLowerCase()` ; la connexion et le
 * contrôle de doublon comparaient la saisie brute. Le 7 septembre 2026, en
 * production, cela a donné exactement ceci (journal d'audit) :
 *
 *   22:56  sub_admin_created   username: 'Lonfo_lookman'   → enregistré 'lonfo_lookman'
 *   23:19  login_failed        ×3
 *   23:21  sub_admin_created   username: 'Lonfo_Lookman'   → doublon accepté
 *   23:21  login_failed        ×2
 *   23:45  sub_admin_created   username: 'L_L'             → enregistré 'l_l'
 *   23:46  login_failed        ×2
 *
 * Le compte existait, il était actif, le mot de passe était bon — et l'écran
 * répondait « Identifiants incorrects. », c'est-à-dire qu'il accusait le mot de
 * passe pour une faute de casse sur l'identifiant. Rien dans les tests ne
 * pouvait le voir : les vues se rendaient, le compte s'affichait sur la page,
 * `test_all_views.js` restait vert.
 *
 * Ce contrôle vérifie deux choses distinctes :
 *
 *   1. la règle elle-même — `lib/identifiant.js` ramène bien les variantes de
 *      casse et d'espaces à la même forme, et ne va pas au-delà ;
 *   2. que ses trois appelants passent par elle. C'est le vrai risque : la
 *      règle était déjà appliquée à la création, et manquait aux deux autres
 *      endroits. Une comparaison brute qui reviendrait reproduirait la panne à
 *      l'identique.
 *
 *   node _check_identifiant.js
 */
const fs   = require('fs');
const path = require('path');

const { normaliserIdentifiant } = require('./lib/identifiant');

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

// ── 1. La règle ──────────────────────────────────────────────────────────────
console.log('\nForme canonique de l\'identifiant');

// Les cas réels du 7 septembre : ce sont les identifiants tapés à la création,
// et ceux que leurs titulaires ont ensuite essayés.
const equivalents = [
  ['Lonfo_lookman', 'lonfo_lookman'],
  ['Lonfo_Lookman', 'lonfo_lookman'],
  ['L_L',           'l_l'],
  ['  jean_martin ', 'jean_martin'],   // espaces collés par un copier-coller
];
for (const [saisi, attendu] of equivalents) {
  const obtenu = normaliserIdentifiant(saisi);
  if (obtenu === attendu) ok(`« ${saisi} » → ${attendu}`);
  else ko(`« ${saisi} » → « ${obtenu} », attendu « ${attendu} »`);
}

// Sans ces deux-là, une règle qui renverrait une constante passerait tout ce
// qui précède : elle ne prouverait qu'on retrouve pas le bon compte.
if (normaliserIdentifiant('lookman') !== normaliserIdentifiant('lonfo_lookman')) {
  ok('deux identifiants différents restent différents');
} else {
  ko('la règle confond deux identifiants distincts');
}
if (normaliserIdentifiant(undefined) === '' && normaliserIdentifiant(null) === '') {
  ok('un champ vide ne devient pas un identifiant');
} else {
  ko('un champ absent produit autre chose que la chaîne vide');
}

// La règle doit rester `trim` + `toLowerCase`, rien de plus : la création
// appliquait déjà exactement cela, donc l'élargir (accents, tirets) rendrait
// introuvables des comptes déjà enregistrés.
if (normaliserIdentifiant('jean-martin') === 'jean-martin'
 && normaliserIdentifiant('rené_l')      === 'rené_l') {
  ok('la règle ne touche ni aux tirets ni aux accents des comptes existants');
} else {
  ko('la règle transforme plus que la casse : des comptes déjà enregistrés '
   + 'deviendraient injoignables');
}

// ── 2. Les appelants ─────────────────────────────────────────────────────────
console.log('\nComparaisons d\'identifiant dans le code');

// Toute comparaison sur `username` doit être normalisée des deux côtés. On
// cherche celles qui ne le sont pas — c'est la forme exacte qu'avait le bug :
//
//     s.username === username
//
const sources = ['server.js', ...fs.readdirSync('routes').map(f => path.join('routes', f))]
  .filter(f => f.endsWith('.js'));

const brut = /(?:^|[^a-zA-Z0-9_])(?:s|sub|a)\.username\s*===/;

for (const fichier of sources) {
  const lignes = fs.readFileSync(fichier, 'utf8').split('\n');
  let vues = 0;
  lignes.forEach((ligne, i) => {
    const nue = ligne.trim();
    // Les commentaires citent la comparaison fautive pour l'expliquer.
    if (nue.startsWith('//') || nue.startsWith('*')) return;
    if (!brut.test(nue)) return;
    // Normalisée des deux côtés : c'est la forme corrigée.
    if (/normaliserIdentifiant\s*\(\s*(?:s|sub|a)\.username\s*\)/.test(nue)) return;
    ko(`${fichier}:${i + 1} compare l'identifiant brut — ${nue}`);
    vues++;
  });
  if (vues === 0 && /\.username/.test(fs.readFileSync(fichier, 'utf8'))) {
    ok(`${fichier} : aucune comparaison brute`);
  }
}

// Et les deux endroits qui doivent la faire doivent la faire vraiment : un
// contrôle qui n'interdit que la mauvaise forme reste vert sur du code qui a
// perdu la comparaison entière.
const appelants = [
  ['server.js',             /const saisi = normaliserIdentifiant\(username\)/,
                            'la connexion normalise la saisie'],
  ['server.js',             /find\(s => normaliserIdentifiant\(s\.username\) === saisi && s\.isActive !== false/,
                            'la connexion cherche le compte sur la forme canonique'],
  ['routes/exploitation.js', /const identifiant = normaliserIdentifiant\(username\)/,
                            'la création normalise avant d\'enregistrer'],
  ['routes/exploitation.js', /find\(s => normaliserIdentifiant\(s\.username\) === identifiant\)/,
                            'le contrôle de doublon compare la forme canonique'],
  ['routes/exploitation.js', /username: {5,}identifiant,/,
                            'le compte est enregistré sous sa forme canonique'],
];
for (const [fichier, motif, quoi] of appelants) {
  if (motif.test(fs.readFileSync(fichier, 'utf8'))) ok(quoi);
  else ko(`${quoi} — introuvable dans ${fichier}`);
}

// ── 3. Les comptes déjà enregistrés ──────────────────────────────────────────
//
// Deux dégâts survivent au correctif, parce qu'ils sont dans les données :
// les doublons créés avant lui, et les empreintes d'avant le passage à bcrypt.
// `checkPwd` est `bcrypt.compareSync` ; sur une empreinte SHA-256 il renvoie
// `false` sans erreur, donc le compte se voit sur la page, se dit « Actif », et
// ne s'ouvre jamais.
// Ces constats portent sur `data/sub_admins.json`, qui est dans `.gitignore` :
// chaque machine a le sien, la production a le sien. Ils sont donc signalés
// mais ne font pas échouer la suite — sinon un clone neuf partirait rouge pour
// une raison qui n'est pas dans le code, et le contrôle finirait supprimé.
// Ce qui fait échouer, c'est la partie précédente : le code.
console.log('\nComptes enregistrés (constats, sans échec)');
const SA_FILE = path.join(__dirname, 'data', 'sub_admins.json');
let subs = [];
try { subs = JSON.parse(fs.readFileSync(SA_FILE, 'utf8')); } catch { /* fichier absent */ }

const echecsCode = echecs;
let constats = 0;
const signale = (m) => { console.log('  ! ' + m); constats++; };

const parIdentifiant = new Map();
for (const s of subs) {
  const cle = normaliserIdentifiant(s.username);
  parIdentifiant.set(cle, [...(parIdentifiant.get(cle) ?? []), s.name]);
}
for (const [cle, noms] of parIdentifiant) {
  if (noms.length > 1) {
    signale(`« ${cle} » désigne ${noms.length} comptes (${noms.join(', ')}) : la `
     + 'connexion en ouvrira un au hasard du mot de passe. En supprimer un '
     + 'depuis la page Sous-admins.');
  }
}
for (const s of subs) {
  if (!/^\$2[aby]\$/.test(s.passwordHash ?? '')) {
    signale(`« ${s.name} » porte une empreinte d'avant bcrypt : le compte `
     + 's\'affiche actif mais aucun mot de passe ne l\'ouvre. Lui en redéfinir '
     + 'un depuis la page Sous-admins le répare.');
  }
}
if (constats === 0) ok(`${subs.length} compte(s) sans doublon ni empreinte périmée`);

if (constats > 0) {
  console.log(`\n⚠️  ${constats} compte(s) à reprendre dans le panneau `
            + '(données locales, hors périmètre du code).');
}
console.log(echecsCode === 0
  ? '\n✅ Identifiants de sous-admin : le code applique la même règle partout\n'
  : `\n❌ ${echecsCode} problème(s) dans le code\n`);
process.exit(echecsCode === 0 ? 0 : 1);
