/**
 * Contrôle du jeu d'icônes.
 *
 * Deux familles de références :
 *   - statiques  : <use href="#ic-crown"/>          → vérifiables ici.
 *   - calculées  : <use href="#ic-' + expr + '"/>   → la cible dépend des
 *     données ; on ne peut pas la résoudre statiquement, mais les identifiants
 *     proviennent tous de server.js (ACTION_LABELS, SEGMENTS), qu'on vérifie
 *     donc séparément.
 *
 *   node _check_icons.js
 */
const fs = require('fs'), path = require('path');

const sprite  = fs.readFileSync(path.join(__dirname, 'views/_icons.ejs'), 'utf8');
const defined = new Set([...sprite.matchAll(/<symbol id="(ic-[^"]+)"/g)].map(m => m[1]));

const used = new Map();
const orphans = [];
const spriteManquant = [];
let dynamic = 0;
let resolus = 0;

/**
 * Un `<use href="#ic-x"/>` ne résout que si le sprite est présent DANS le
 * document rendu. Vérifier que le symbole existe dans _icons.ejs ne suffit
 * donc pas : `login.ejs` et `error.ejs` sont des documents autonomes qui
 * n'incluaient pas le sprite, et affichaient dix carrés vides sans qu'aucune
 * erreur ne soit levée — ni au rendu, ni ici.
 *
 * Est « autonome » toute vue qui émet sa propre balise <body> : les autres
 * sont des fragments servis à l'intérieur de layout_top, qui porte le sprite.
 */
function spriteAbsent(source) {
  const autonome = /<body[\s>]/.test(source);
  if (!autonome) return false;
  const porteLeSprite = /include\(\s*['"]_icons['"]/.test(source)
                     || /<symbol id="ic-/.test(source);
  return !porteLeSprite;
}

/**
 * `<use href="#ic-<%= ic %>"/>` — l'identifiant vient d'une variable EJS.
 *
 * Quand cette variable est un simple ternaire de littéraux dans la même vue
 * (`const ic = lvl==='delete'?'trash':lvl==='write'?'edit':'eye'`), la cible
 * EST vérifiable : il suffit de prendre les littéraux en position de valeur,
 * c'est-à-dire précédés de `?` ou `:` — sans quoi on ramasserait aussi les
 * `'delete'` et `'write'` du test, qui ne sont pas des noms d'icônes.
 *
 * Retourne null si la variable n'est pas déclarée dans le fichier : la
 * référence redevient alors calculée et non vérifiable.
 */
function litterauxDeVariable(source, nom) {
  const decl = source.match(
    new RegExp(`(?:const|let|var)\\s+${nom}\\s*=\\s*([^;]*?)(?:;|%>)`));
  if (!decl) return null;
  const valeurs = [...decl[1].matchAll(/[?:]\s*'([^']+)'/g)].map(m => m[1]);
  return valeurs.length ? valeurs : null;
}

for (const f of fs.readdirSync(path.join(__dirname, 'views'))) {
  if (!f.endsWith('.ejs')) continue;
  const s = fs.readFileSync(path.join(__dirname, 'views', f), 'utf8');
  if (/<use href="#ic-/.test(s) && spriteAbsent(s)) spriteManquant.push(f);
  for (const m of s.matchAll(/<use href="#(ic-[^"]*)"/g)) {
    const id = m[1];

    // Interpolation EJS d'une variable locale : on tente de la résoudre.
    const interp = id.match(/^ic-<%=\s*([A-Za-z_$][\w$]*)\s*%>$/);
    if (interp) {
      const noms = litterauxDeVariable(s, interp[1]);
      if (!noms) { dynamic++; continue; }
      for (const n of noms) {
        resolus++;
        used.set('ic-' + n, (used.get('ic-' + n) ?? 0) + 1);
        if (!defined.has('ic-' + n)) orphans.push(`${f} → #ic-${n} (via ${interp[1]})`);
      }
      continue;
    }

    // Référence calculée : concaténation ('...' + expr), littéral gabarit (${…}),
    // ou toute autre expression EJS qu'on ne sait pas résoudre.
    if (id === 'ic-' || id.includes("'") || id.includes('${') || id.includes('<%')) { dynamic++; continue; }
    used.set(id, (used.get(id) ?? 0) + 1);
    if (!defined.has(id)) orphans.push(`${f} → #${id}`);
  }
}

// Identifiants d'icônes portés par les données, injectés dans <use href="#ic-...">.
// test_all_views.js redéfinit SEGMENTS/ACTION_LABELS pour ses fixtures : si ses
// valeurs divergent de server.js, le harnais rend des icônes vides sans rien
// signaler (l'identifiant est dans un attribut, invisible à l'inspection du texte).
const SOURCES = ['server.js', 'test_all_views.js', 'lib/permissions.js'];
const fromData = [];
const badData  = [];

for (const f of SOURCES) {
  for (const m of fs.readFileSync(path.join(__dirname, f), 'utf8').matchAll(/icon: '([^']+)'/g)) {
    fromData.push(m[1]);
    if (!defined.has('ic-' + m[1])) badData.push(`${f} → ${m[1]}`);
  }
}

const totalUses = [...used.values()].reduce((a, b) => a + b, 0);
console.log(`${defined.size} symboles définis`);
console.log(`${totalUses} références statiques (${used.size} icônes distinctes)`
          + `, ${resolus} résolues depuis une variable EJS, ${dynamic} calculées`);
console.log(`${new Set(fromData).size} identifiants d'icônes dans les données (${SOURCES.join(', ')})`);

if (orphans.length) { console.log('\nRÉFÉRENCES ORPHELINES :'); orphans.forEach(o => console.log('  ' + o)); }
if (badData.length) { console.log('\nICÔNES DE DONNÉES SANS SYMBOLE :'); [...new Set(badData)].forEach(b => console.log('  ' + b)); }
if (spriteManquant.length) {
  console.log('\nDOCUMENTS AUTONOMES SANS SPRITE (toutes les icônes y sont vides) :');
  spriteManquant.forEach(f => console.log(`  ${f} — ajouter <%- include('_icons') %> après <body>`));
}
if (!orphans.length && !badData.length && !spriteManquant.length) console.log('\nAucune référence orpheline.');

const unused = [...defined].filter(d => !used.has(d) && !fromData.includes(d.slice(3)));
if (unused.length) console.log('\nSymboles jamais référencés : ' + unused.join(', '));

process.exitCode = (orphans.length || badData.length || spriteManquant.length) ? 1 : 0;
