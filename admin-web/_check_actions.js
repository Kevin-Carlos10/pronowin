/**
 * Chaque action de l'interface doit atteindre une route qui existe.
 *
 * Un formulaire qui poste vers une route absente, un lien vers une page qui
 * n'est pas déclarée, un `onclick` qui appelle une fonction jamais définie :
 * rien de tout cela ne casse le rendu. La page s'affiche, le bouton s'anime,
 * et il ne se passe rien — ou bien on tombe sur un 404 après avoir cliqué.
 *
 * C'est exactement ce qui est arrivé à « Dépublier » : le bouton existait, la
 * boîte de confirmation s'ouvrait, et l'action échouait en silence.
 *
 *   node _check_actions.js
 */
const fs   = require('fs');
const path = require('path');
const { parse } = require('node-html-parser');
const ejs  = require('ejs');
const { views, opts } = require('./test_all_views.js');

// ── Routes réellement déclarées ─────────────────────────────────────────────
const routes = { GET: [], POST: [], PUT: [], PATCH: [], DELETE: [] };

const fichiers = ['server.js',
  ...fs.readdirSync('routes').filter(f => f.endsWith('.js')).map(f => 'routes/' + f)];

for (const f of fichiers) {
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(/app\.(get|post|put|patch|delete)\(\s*'([^']+)'/g)) {
    routes[m[1].toUpperCase()].push(m[2]);
  }
}

/** `/admin/pronostics/edit/:matchId` → expression qui accepte un segment. */
const compiler = (chemin) => new RegExp('^' + chemin
  .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  .replace(/:\w+/g, '[^/]+')
  .replace(/\\\*/g, '.*') + '$');

const compilees = Object.fromEntries(
  Object.entries(routes).map(([m, l]) => [m, l.map(compiler)]));

const existe = (methode, url) => {
  const chemin = url.split('?')[0].replace(/\/+$/, '') || '/';
  return (compilees[methode] ?? []).some(re => re.test(chemin));
};

/** Une URL que ce contrôle n'a pas vocation à vérifier. */
const externe = (u) => !u || u.startsWith('#') || u.startsWith('http')
  || u.startsWith('mailto:') || u.startsWith('tel:')
  || u.startsWith('javascript:') || u.startsWith('data:');

// ── Analyse ─────────────────────────────────────────────────────────────────
const griefs = [];
let examinees = 0, actions = 0;

(async () => {
  for (const [nom, vue, locals] of views) {
    let html;
    try { html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts); }
    catch { continue; }
    examinees++;

    const d = parse(html);

    const scriptsPage = d.querySelectorAll('script').map(s => s.text).join('\n');

    // 1. Formulaires : leur destination doit exister.
    for (const f of d.querySelectorAll('form')) {
      const action  = f.getAttribute('action');
      const methode = (f.getAttribute('method') ?? 'GET').toUpperCase();

      // Action absente du balisage : légitime si un script la pose avant
      // l'envoi — c'est le cas des modales, qui n'apprennent la cible qu'au
      // moment du clic. Ma première version les signalait toutes, soit huit
      // faux positifs : un contrôle qui crie au loup finit ignoré.
      if (action === undefined) {
        const id = f.getAttribute('id');
        const posee = id
          && new RegExp(`getElementById\\(['\`]${id}['\`]\\)\\s*\\.action\\s*=`).test(scriptsPage);
        const poseeSurVariable = /\b\w+\.action\s*=\s*[`'"]/.test(scriptsPage);
        if (!posee && !poseeSurVariable) {
          griefs.push(`${nom} : <form ${methode}> sans action et aucun script ne `
                    + `la pose — l'envoi retomberait sur la page courante.`);
        }
        continue;
      }
      if (externe(action)) continue;

      actions++;
      // Une interpolation vide produit « /admin/x/ » : l'identifiant manque, et
      // la requête n'atteindra aucune route.
      if (/\/$/.test(action) && action !== '/') {
        griefs.push(`${nom} : formulaire ${methode} « ${action} » — segment final `
                  + `vide, un identifiant n'a pas été interpolé.`);
        continue;
      }
      if (!existe(methode, action)) {
        griefs.push(`${nom} : formulaire ${methode} « ${action} » — aucune route.`);
      }
    }

    // 2. Liens internes : la page visée doit être déclarée.
    for (const a of d.querySelectorAll('a[href]')) {
      const href = a.getAttribute('href');
      if (externe(href) || !href.startsWith('/')) continue;
      actions++;
      if (!existe('GET', href)) {
        const libelle = a.text.replace(/\s+/g, ' ').trim().slice(0, 34);
        griefs.push(`${nom} : lien « ${libelle} » → ${href} — aucune route GET.`);
      }
    }

    // 3. `onclick` : la fonction appelée doit être définie quelque part.
    //
    // Les gabarits déclarent leurs fonctions dans un <script> de la page ou
    // dans layout_bottom ; on cherche donc dans le document entier.
    const scripts = d.querySelectorAll('script').map(s => s.text).join('\n');
    for (const el of d.querySelectorAll('[onclick]')) {
      const code = el.getAttribute('onclick') ?? '';
      for (const m of code.matchAll(/(?:^|[^.\w])([a-zA-Z_$][\w$]*)\s*\(/g)) {
        const fn = m[1];
        if (['if', 'for', 'while', 'return', 'function', 'switch', 'catch',
             'typeof', 'new', 'confirm', 'alert', 'parseInt', 'parseFloat',
             'Number', 'String', 'Boolean', 'Array', 'Object', 'JSON',
             'setTimeout', 'setInterval', 'encodeURIComponent', 'decodeURIComponent',
             'event'].includes(fn)) continue;
        actions++;
        const definie = new RegExp(
          `(?:function\\s+${fn}\\b|(?:const|let|var)\\s+${fn}\\s*=|${fn}\\s*=\\s*(?:async\\s*)?(?:function|\\())`)
          .test(scripts);
        if (!definie) {
          griefs.push(`${nom} : onclick appelle « ${fn}() » — fonction introuvable.`);
        }
      }
    }
  }

  if (examinees < 20 || actions < 100) {
    console.log(`ANALYSEUR DÉFAILLANT — ${examinees} vues, ${actions} actions lues.`);
    process.exitCode = 2;
    return;
  }

  const uniques = [...new Set(griefs)];
  console.log(`${examinees} vues · ${actions} actions vérifiées · `
            + `${Object.values(routes).flat().length} routes déclarées`);
  if (uniques.length === 0) {
    console.log('\nToute action de l\'interface atteint une route ou une fonction existante.');
  } else {
    console.log(`\n${uniques.length} action(s) sans destination :`);
    uniques.forEach(g => console.log('  · ' + g));
    process.exitCode = 1;
  }
})();
