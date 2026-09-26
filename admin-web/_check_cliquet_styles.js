/**
 * Cliquet de la refonte visuelle du panneau (constat A14 de l'audit du
 * 24 septembre 2026).
 *
 * 61 tailles de police, plus de mille styles écrits en ligne, des couleurs
 * codées en dur : c'est la cause profonde des défauts de contraste (A10) —
 * une couleur écrite en chiffres ne suit pas le thème. La refonte est
 * progressive ; ce contrôle garantit seulement qu'on n'aggrave plus : chaque
 * compteur peut baisser, aucun ne peut monter.
 *
 * Quand un compteur baisse, abaisser la valeur ci-dessous : le cliquet se
 * resserre, et le terrain gagné ne se reperd pas.
 *
 * Pour une nouvelle règle : une classe de style.css, les jetons de couleur
 * (var(--success), rgba(var(--success-rgb), .12)…) et l'échelle --fs-*.
 *
 *   node _check_cliquet_styles.js
 */
const fs = require('fs');
const path = require('path');

const PLAFONDS = {
  stylesEnLigne:     1103,
  taillesDistinctes: 61,
  couleursEnDur:     154,   // 232 avant le passage des teintes d'état aux jetons
};

const dossier = path.join(__dirname, 'views');
let stylesEnLigne = 0;
let couleursEnDur = 0;
const tailles = new Set();
for (const f of fs.readdirSync(dossier).filter((x) => x.endsWith('.ejs'))) {
  const s = fs.readFileSync(path.join(dossier, f), 'utf8');
  stylesEnLigne += (s.match(/style="/g) || []).length;
  for (const m of s.matchAll(/font-size:\s*([0-9.]+(?:px|rem|em))/g)) tailles.add(m[1]);
  couleursEnDur += (s.match(/#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b|rgba?\(\s*\d/g) || []).length;
}
const mesures = { stylesEnLigne, taillesDistinctes: tailles.size, couleursEnDur };

let echecs = 0;
console.log('\nCliquet des styles du panneau');
for (const [cle, plafond] of Object.entries(PLAFONDS)) {
  const v = mesures[cle];
  if (v > plafond) {
    console.log(`  ✗ ${cle} : ${v} (plafond ${plafond}) — utiliser une classe ou un jeton de style.css`);
    echecs++;
  } else if (v < plafond) {
    console.log(`  ✓ ${cle} : ${v} — abaisser le plafond à ${v} dans _check_cliquet_styles.js`);
  } else {
    console.log(`  ✓ ${cle} : ${v}`);
  }
}
console.log(echecs === 0 ? '\n✅ Rien d\'aggravé\n' : `\n❌ ${echecs} compteur(s) en hausse\n`);
process.exit(echecs === 0 ? 0 : 1);
