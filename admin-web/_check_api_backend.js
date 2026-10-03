/**
 * Chaque appel de l'admin vers l'API doit atteindre une route du backend.
 *
 * L'admin est un client comme un autre : il parle au backend en HTTP. Un appel
 * vers une route absente ou avec le mauvais verbe ne casse rien au démarrage,
 * ne produit aucune alerte, et se manifeste seulement au clic — par un bouton
 * qui « ne marche pas ».
 *
 * C'est l'étage où se jouait la panne de « Dépublier » : le bouton visait bien
 * une route admin, mais celle-ci appelait un endpoint qui refusait l'écriture.
 * Ce contrôle-ci couvre le cas voisin et plus fréquent : l'endpoint n'existe
 * pas, ou pas avec ce verbe.
 *
 *   node _check_api_backend.js
 */
const fs   = require('fs');
const path = require('path');

const BACKEND = 'C:/xampp/htdocs/PronoWin/backend/src';

// ── Routes du backend ───────────────────────────────────────────────────────
const routes = new Set();
const index = fs.readFileSync(BACKEND + '/index.ts', 'utf8');

// Les préfixes sont des gabarits : app.use(`${v1}/auth`, …).
const constantes = {};
for (const m of index.matchAll(/const\s+(\w+)\s*=\s*['"]([^'"]+)['"]/g)) {
  constantes[m[1]] = m[2];
}
const resoudre = (s) => s.replace(/\$\{(\w+)\}/g, (t, n) => n in constantes ? constantes[n] : t);

const prefixes = {}, fichierDe = {};
for (const m of index.matchAll(
    /app\.use\(\s*[`'"]([^`'"]+)[`'"]\s*,\s*(?:\w+\s*,\s*)*(\w+)\s*\)/g)) {
  prefixes[m[2]] = resoudre(m[1]);
}
for (const m of index.matchAll(/import\s+(\w+)\s+from\s+['"]\.\/routes\/([\w.]+)['"]/g)) {
  fichierDe[m[1]] = m[2];
}

const dossier = BACKEND + '/routes';
const fichiersRoutes = fs.readdirSync(dossier).filter(f => f.endsWith('.ts'));

for (const f of fichiersRoutes) {
  const base  = path.basename(f, '.ts');
  const ident = Object.keys(fichierDe).find(k => fichierDe[k] === base);
  const prefixe = ident ? prefixes[ident] : null;
  if (!prefixe) continue;

  const src = fs.readFileSync(path.join(dossier, f), 'utf8');
  // Le nom du routeur varie : `router` ici, `r` là.
  const nom = (src.match(/const\s+(\w+)\s*=\s*(?:express\.)?Router\s*\(/) || [])[1];
  if (!nom) continue;

  const re = new RegExp(
    `\\b${nom}\\s*\\.\\s*(get|post|put|patch|delete)\\s*\\(\\s*[\`'"]([^\`'"]*)[\`'"]`, 'g');
  for (const m of src.matchAll(re)) {
    routes.add(m[1].toUpperCase() + ' ' + ((prefixe + m[2]).replace(/\/+$/, '') || '/'));
  }
}

// ── Appels émis par l'admin ─────────────────────────────────────────────────
// `api(token)` rend une instance axios dont la baseURL est l'API v1 ; les
// appels s'écrivent donc `a.get('/pronostics/...')`.
const appels = [];
const sources = ['server.js',
  ...fs.readdirSync('routes').filter(f => f.endsWith('.js')).map(f => 'routes/' + f)];

for (const f of sources) {
  fs.readFileSync(f, 'utf8').split('\n').forEach((ligne, i) => {
    const m = ligne.match(
      /\b(?:a|api|client)\s*\.\s*(get|post|put|patch|delete)\s*\(\s*(?:`([^`]+)`|'([^']+)')/);
    if (!m) return;
    let chemin = m[2] ?? m[3];
    if (!chemin.startsWith('/')) return;

    // Les chemins sont souvent concaténés :
    //
    //     a.get('/pronostics/admin/match/' + req.params.matchId)
    //
    // Ne lire que le littéral rendait « /pronostics/admin/match/ », qui ne
    // correspond à aucune route : ma première version signalait ainsi 26
    // appels parfaitement corrects. Ce qui suit le littéral compte autant que
    // le littéral lui-même.
    const suite = ligne.slice(m.index + m[0].length);
    // Une concaténation qui commence par « ? » construit une requête, pas un
    // chemin : `'/upcoming' + (x ? '?competition=' + x : '')`. La compter comme
    // segment ajoutait deux niveaux inexistants.
    const construitRequete = /^\s*\+[^;]*['"]\?/.test(suite);
    if (!construitRequete && /^\s*\+/.test(suite)) {
      // Autant de segments variables que de concaténations qui suivent.
      const morceaux = suite.split('+').slice(1);
      for (const morceau of morceaux) {
        // Une concaténation de chaîne littérale prolonge le chemin tel quel.
        const litteral = morceau.match(/^\s*['"]([^'"]*)['"]/);
        if (litteral) { chemin += litteral[1]; continue; }
        if (!chemin.endsWith('/')) chemin += '/';
        chemin += ':param';
        // Une chaîne littérale peut suivre la variable : `+ id + '/publish'`.
      }
    }
    chemin = chemin.replace(/\/{2,}/g, '/');
    appels.push({ methode: m[1].toUpperCase(), chemin, fichier: f, ligne: i + 1 });
  });
}

// ── Comparaison ─────────────────────────────────────────────────────────────
//
// Les deux cotes portent des segments variables : `:id` chez Express, et cote
// admin un proxy comme `'/admin/stats/' + req.params.endpoint`. Il faut donc
// des jokers **des deux cotes** : compiler une expression depuis la seule route
// ne pouvait pas faire correspondre `/admin/stats/:param` a `/admin/stats/online`.
const segments = (chemin) => chemin
  .split('?')[0]
  .split('/')
  .filter(Boolean)
  .map(s => (/^:/.test(s) || /\$\{/.test(s)) ? null : s);   // null = joker

const correspond = (a, b) =>
  a.length === b.length &&
  a.every((s, i) => s === null || b[i] === null || s === b[i]);

const compilees = [...routes].map(r => {
  const [meth, chemin] = r.split(' ');
  return { meth, seg: segments(chemin) };
});

if (routes.size < fichiersRoutes.length * 2 || appels.length < 30) {
  console.log(`ANALYSEUR DÉFAILLANT — ${routes.size} routes backend lues pour `
            + `${fichiersRoutes.length} fichiers, ${appels.length} appels admin.`);
  process.exitCode = 2;
} else {
  const orphelins = appels.filter(a => {
    const seg = segments('/api/v1' + a.chemin);
    return !compilees.some(r => r.meth === a.methode && correspond(r.seg, seg));
  });

  console.log(`${routes.size} routes backend · ${appels.length} appels de l'admin`);
  if (orphelins.length === 0) {
    console.log('\nTout appel de l\'administration atteint une route existante.');
  } else {
    console.log(`\n${orphelins.length} appel(s) sans route correspondante :`);
    orphelins.forEach(o => console.log(
      `  · ${o.methode} ${o.chemin}\n      ${o.fichier}:${o.ligne}`));
    process.exitCode = 1;
  }
}
