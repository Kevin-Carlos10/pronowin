/**
 * Les couleurs écrites en texte sont celles qui se lisent, et chaque écran a
 * son propre titre.
 *
 * Mesuré le 24 septembre 2026 sur 25 vues, 3 largeurs et 2 thèmes (445
 * mesures, constats A10 à A13) :
 *
 *   - 188 endroits écrivaient en texte les teintes de remplissage
 *     (--success, --error, --warning, --info, --purple) ou l'accent --primary :
 *     sur le thème clair, « 0 FCFA » en vert sur blanc tombait à 2,28:1, et le
 *     thème clair comptait 73 couples de couleurs sous le seuil WCAG ;
 *   - le seul h1 de chaque page était le logo « PronoWin » ;
 *   - du blanc sur l'accent orange, 2,03:1.
 *
 * Les teintes lisibles existent (--on-success… --primary-texte) et sont
 * définies pour chaque thème dans style.css. Ce contrôle empêche d'en
 * revenir aux teintes de remplissage : il lit les sources, commentaires
 * retirés — un commentaire qui cite l'ancien motif ne doit ni faire échouer
 * ni passer le contrôle.
 *
 *   node _check_contraste_tokens.js
 */
const fs = require('fs');
const path = require('path');

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

const sansCommentaires = (s) => s
  .replace(/<%#[\s\S]*?%>/g, '')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/(^|[^:"'])\/\/[^\n]*/g, '$1');

const VUES = path.join(__dirname, 'views');
const sources = [
  ...fs.readdirSync(VUES).filter((f) => f.endsWith('.ejs')).map((f) => path.join(VUES, f)),
  path.join(__dirname, 'public', 'style.css'),
];

console.log('\nCouleurs de texte et titres');

// ── Teintes de remplissage écrites en texte ──
const texteEnTeinte = /(?<![-\w])color\s*:\s*(var\(--(success|error|warning|info|purple|primary|border|border-s)\)|#(F5A623|EF4444|22C55E|F59E0B|3B82F6|A78BFA|FCA5A5|93C5FD|F87171|34D399|FBBF24)\b)/gi;
const conditionnel = /color:\s*<%=[^%]*'var\(--(success|error|warning|info|purple)\)'/g;
const fautes = [];
for (const f of sources) {
  const s = sansCommentaires(fs.readFileSync(f, 'utf8'));
  for (const m of s.matchAll(texteEnTeinte)) fautes.push(`${path.basename(f)} : ${m[0]}`);
  for (const m of s.matchAll(conditionnel)) fautes.push(`${path.basename(f)} : ${m[0].slice(0, 60)}`);
}
if (fautes.length === 0) ok('aucune teinte de remplissage n\'est écrite en texte');
else {
  ko(`${fautes.length} texte(s) écrits dans une teinte de remplissage :`);
  fautes.slice(0, 12).forEach((x) => console.log('      ' + x));
}

// ── Les tokens lisibles existent pour les deux thèmes ──
const css = sansCommentaires(fs.readFileSync(path.join(__dirname, 'public', 'style.css'), 'utf8'));
const blocs = (sel) => [...css.matchAll(new RegExp(sel.replace(/[.[\]]/g, '\\$&') + '\\s*\\{([^}]*)\\}', 'g'))].map((m) => m[1]).join('\n');
const racine = blocs(':root');
const clair = blocs('html.light');
const manquants = ['--on-success', '--on-danger', '--on-warning', '--on-info', '--on-purple', '--primary-texte']
  .filter((t) => !racine.includes(t + ':') || !clair.includes(t + ':'));
if (manquants.length === 0) ok('chaque teinte lisible est définie pour le thème sombre et le thème clair');
else ko('teintes lisibles sans valeur pour l\'un des thèmes : ' + manquants.join(', '));

// ── Blanc sur l'accent ──
const blancSurAccent = [];
for (const f of sources) {
  const s = sansCommentaires(fs.readFileSync(f, 'utf8'));
  for (const regle of s.matchAll(/\{[^{}]*\}/g)) {
    if (/background\s*:\s*var\(--primary\)/.test(regle[0]) && /(?<![-\w])color\s*:\s*#fff\b/i.test(regle[0])) {
      blancSurAccent.push(path.basename(f));
    }
  }
}
if (blancSurAccent.length === 0) ok('aucun texte blanc sur l\'accent vif (2,03:1)');
else ko('blanc sur --primary dans : ' + [...new Set(blancSurAccent)].join(', '));

// ── Titres ──
const layout = sansCommentaires(fs.readFileSync(path.join(VUES, 'layout_top.ejs'), 'utf8'));
if (!/<h1[\s>]/.test(layout)) ok('le logo de la barre latérale n\'est plus un titre');
else ko('layout_top.ejs contient un h1 : il devient le titre de chaque page');

const sansTitre = fs.readdirSync(VUES).filter((f) => f.endsWith('.ejs')).filter((f) => {
  const s = sansCommentaires(fs.readFileSync(path.join(VUES, f), 'utf8'));
  return /<div class="topbar">/.test(s) && !/<h1[\s>]/.test(s);
});
if (sansTitre.length === 0) ok('chaque écran à barre de titre porte son propre h1');
else ko('écrans sans h1 : ' + sansTitre.join(', '));

console.log(echecs === 0 ? '\n✅ Couleurs lisibles, titres à leur place\n' : `\n❌ ${echecs} problème(s)\n`);
process.exit(echecs === 0 ? 0 : 1);
