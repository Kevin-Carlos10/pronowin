/**
 * Collisions entre les classes du gabarit et celles des vues.
 *
 * `profile.ejs` posait `class="pf-avatar main"` : le modificateur « main »
 * portait le même nom que la zone de contenu du gabarit, dont la règle est
 *
 *     .main { margin-left: var(--sidebar-w); min-height: 100vh; padding: 28px }
 *
 * L'avatar héritait donc de 100vh de hauteur et s'étirait sur toute la colonne,
 * en une ellipse verticale. Rien ne le signalait : la page rendait, les scripts
 * compilaient, les icônes étaient bonnes.
 *
 * Le contrôle repose sur un invariant simple et vérifiable : une classe qui
 * structure la page — celle qui fixe la hauteur de la fenêtre, la marge de la
 * barre latérale ou un positionnement fixe — n'a de sens qu'une seule fois par
 * page. Deux occurrences signifient qu'une vue s'en est emparée.
 *
 *   node _check_layout.js
 */
const ejs = require('ejs');
const fs  = require('fs');
const { views, opts } = require('./test_all_views.js');

/** Propriétés qui n'ont de sens que sur l'ossature de la page. */
const PROPRIETES_STRUCTURELLES = [
  /min-height:\s*100vh/i,
  /margin-left:\s*var\(--sidebar-w\)/i,
  /height:\s*100vh/i,
];

/** Classes porteuses de ces propriétés, lues dans la feuille de style. */
function classesStructurelles() {
  // Les commentaires sont retirés d'abord : un `/* … */` entre deux règles
  // empêchait de reconnaître celle qui suit, et le contrôle ne surveillait donc
  // aucune classe tout en se déclarant vert.
  const css = fs.readFileSync('public/style.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const trouvees = new Set();
  for (const bloc of css.split('}')) {
    const i = bloc.indexOf('{');
    if (i < 0) continue;
    const selecteur = bloc.slice(0, i).trim();
    const corps     = bloc.slice(i + 1);
    if (!PROPRIETES_STRUCTURELLES.some(re => re.test(corps))) continue;
    // Sélecteur simple uniquement : `.nom`, pas `.a .b` ni `.a:hover`.
    const m = selecteur.match(/^\.([a-z][a-z0-9-]*)$/i);
    if (m) trouvees.add(m[1]);
  }
  return [...trouvees];
}

/** Occurrences d'une classe dans un attribut `class`, mot entier. */
function compter(html, classe) {
  let n = 0;
  for (const m of html.matchAll(/class="([^"]*)"/g)) {
    if (m[1].split(/\s+/).includes(classe)) n++;
  }
  return n;
}

(async () => {
  const structurelles = classesStructurelles();
  const echecs = [];
  let vues = 0;

  for (const [label, vue, locals] of views) {
    let html;
    try {
      html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts);
    } catch {
      continue; // `test_all_views.js` signale déjà les vues qui ne rendent pas.
    }
    vues++;

    for (const classe of structurelles) {
      const n = compter(html, classe);
      if (n > 1) {
        echecs.push(
          `${label} — la classe « ${classe} » apparaît ${n} fois.\n` +
          `      → elle structure la page (hauteur de fenêtre, marge de la barre latérale).\n` +
          `      → une vue l'utilise sans doute comme modificateur : préfixez-le.`);
      }
    }
  }

  console.log(`${structurelles.length} classe(s) structurelle(s) surveillée(s) : ${structurelles.join(', ')}`);
  console.log(`${vues} vues rendues`);

  if (echecs.length) {
    console.log('\nCOLLISIONS DE CLASSES :');
    [...new Set(echecs)].forEach(e => console.log('  ' + e));
    console.log('\nRappel : un modificateur de vue se préfixe (« pf-principal »),');
    console.log('jamais un nom générique qui existe déjà dans la feuille globale.');
  } else {
    console.log('\nAucune collision avec les classes du gabarit.');
  }

  process.exitCode = echecs.length ? 1 : 0;
})();
