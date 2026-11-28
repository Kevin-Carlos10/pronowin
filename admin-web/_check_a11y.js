/**
 * Accessibilité mesurable des vues rendues.
 *
 * Trois manques qu'aucun autre contrôle ne voit, parce que la page rend très
 * bien sans eux :
 *
 *   1. un champ de saisie sans nom accessible — un `placeholder` ne compte pas,
 *      il disparaît dès la première frappe et n'est pas annoncé comme nom ;
 *   2. un bouton réduit à une icône, sans texte ni `aria-label` : annoncé
 *      « bouton », sans plus ;
 *   3. un en-tête de tableau sans `scope`, qui empêche d'associer une cellule
 *      à sa colonne.
 *
 *   node _check_a11y.js
 */
const ejs = require('ejs');
const { views, opts } = require('./test_all_views.js');

function champsSansNom(html) {
  const ids   = new Set([...html.matchAll(/<label[^>]*\sfor="([^"]*)"/g)].map(m => m[1]));
  const zones = [...html.matchAll(/<label\b[^>]*>[\s\S]*?<\/label>/g)]
                  .map(m => [m.index, m.index + m[0].length]);
  const dansLabel = i => zones.some(([a, b]) => i > a && i < b);
  const restants = [];
  for (const m of html.matchAll(/<(input|select|textarea)\b([^<>]*)>/g)) {
    const a = m[2];
    if (/type="(hidden|submit|button)"/.test(a))                 continue;
    if (/aria-label=|aria-labelledby=|title=/.test(a))           continue;
    const id = (a.match(/\sid="([^"]*)"/) || [])[1];
    if (id && ids.has(id))                                       continue;
    if (dansLabel(m.index))                                      continue;
    restants.push((a.match(/name="([^"]*)"/) || [])[1] ?? '(sans name)');
  }
  return restants;
}

function boutonsSansNom(html) {
  const restants = [];
  for (const m of html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
    const [, attrs, contenu] = m;
    if (contenu.replace(/<[^>]*>/g, '').replace(/&\w+;/g, '').trim())  continue;
    if (/aria-label=|title=/.test(attrs))                              continue;
    restants.push((attrs.match(/class="([^"]*)"/) || [])[1] ?? '(sans classe)');
  }
  return restants;
}

function enTetesSansScope(html) {
  return [...html.matchAll(/<th\b([^>]*)>/g)].filter(m => !/scope=/.test(m[1])).length;
}

/**
 * Attributs ARIA dont les guillemets ont été échappés.
 *
 * `<%= cond ? 'aria-current="page"' : '' %>` produit
 * `aria-current=&#34;page&#34;` : l'attribut existe, mais sa valeur porte des
 * guillemets littéraux et ne vaut donc pas « page ». La page rend
 * parfaitement, et le repère est silencieusement perdu pour un lecteur
 * d'écran. Le motif correct met l'expression DANS l'attribut :
 * `aria-current="<%= cond ? 'page' : 'false' %>"`.
 */
function ariaEchappes(html) {
  return [...html.matchAll(/\saria-[a-z]+=&#3[49];/g)].length;
}

(async () => {
  const champs = new Map(), boutons = new Map();
  let thNus = 0, ariaNus = 0, vues = 0;

  for (const [, vue, locals] of views) {
    let html;
    try { html = await ejs.renderFile('views/' + vue + '.ejs', locals, opts); }
    catch { continue; }
    vues++;

    const c = champsSansNom(html);
    if (c.length) champs.set(vue, new Set([...(champs.get(vue) ?? []), ...c]));
    const b = boutonsSansNom(html);
    if (b.length) boutons.set(vue, new Set([...(boutons.get(vue) ?? []), ...b]));
    thNus  += enTetesSansScope(html);
    ariaNus += ariaEchappes(html);
  }

  const total = m => [...m.values()].reduce((n, s) => n + s.size, 0);
  const detail = m => [...m.entries()]
    .map(([v, s]) => `      ${v} : ${[...s].join(', ')}`).join('\n');

  console.log(`${vues} vues rendues`);
  console.log(`  champs sans nom accessible : ${total(champs)}`);
  if (champs.size) console.log(detail(champs));
  console.log(`  boutons icône sans nom     : ${total(boutons)}`);
  if (boutons.size) console.log(detail(boutons));
  console.log(`  en-têtes <th> sans scope   : ${thNus}`);
  console.log(`  attributs ARIA échappés    : ${ariaNus}`);

  const echec = total(champs) + total(boutons) + thNus + ariaNus;
  console.log(echec ? '\nDes éléments restent sans nom accessible.'
                    : '\nTous les champs, boutons et en-têtes sont nommés.');
  process.exitCode = echec ? 1 : 0;
})();
