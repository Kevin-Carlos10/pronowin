/**
 * Logotype « PronoWin » — le texte converti en tracés.
 *
 * Pourquoi ne pas écrire `<text>` : le site compose la marque avec une pile de
 * polices système (`-apple-system, SF Pro Display, Helvetica Neue, Arial`).
 * Un logo qui s'appuie là-dessus se rend différemment sur chaque machine — et
 * ne le dit pas. Ici les lettres sont des courbes : le fichier est identique
 * partout, sans police à installer.
 *
 * Police : Inter Bold, sous SIL Open Font License 1.1, qui autorise
 * explicitement l'usage des contours dans un logo. Arial et Segoe UI, les
 * deux polices vers lesquelles la pile du site retombe sous Windows, sont
 * sous licence Monotype/Microsoft — les intégrer à une marque déposable
 * poserait un problème que personne ne découvrirait avant le dépôt.
 *
 *     node brand/logotype.js
 */
const fs   = require('fs');
const path = require('path');
const ot   = require('opentype.js');

const RACINE = path.resolve(__dirname);
const POLICE = path.join(RACINE, 'inter-700.ttf');

const TAILLE  = 200;   // corps, en unités SVG
const SERRAGE = -0.02; // approche, en em — la marque de référence est serrée

// « Prono » clair, « Win » en accent : c'est déjà ainsi que le site compose la
// marque (`.brand span { color: var(--accent) }`).
const CLAIR  = '#F5F5F7';
const SOMBRE = '#1D1D1F';
const ACCENT = '#E8541A';
const FOND   = '#161A24';   // le bleu-nuit de la référence

const octets = fs.readFileSync(POLICE);
const police = ot.parse(octets.buffer.slice(octets.byteOffset,
                                            octets.byteOffset + octets.byteLength));

const MOT = 'PronoWin';
const COUPE = 5;  // « Prono » | « Win »

/**
 * Composition glyphe par glyphe.
 *
 * `getPaths()` refuse cette police : opentype.js ne sait pas lire la
 * fonctionnalité `ccmp` d'Inter (lookupType 6, substFormat 2) et lève une
 * exception avant d'avoir tracé quoi que ce soit. On compose donc à la main —
 * ce qui, pour huit lettres latines sans ligature ni signe diacritique, ne
 * retire rien : `ccmp` n'y aurait rien substitué.
 *
 * Avantage secondaire : la position de chaque lettre est explicite, donc la
 * coupure de couleur entre « Prono » et « Win » ne peut pas décaler le mot.
 */
const echelle = TAILLE / police.unitsPerEm;
const traces  = [];
let plume     = 0;

for (let i = 0; i < MOT.length; i++) {
  const glyphe = police.charToGlyph(MOT[i]);
  if (!glyphe || glyphe.index === 0) {
    console.error(`ANOMALIE : « ${MOT[i]} » absent de la police (glyphe .notdef).`);
    console.error('Le logotype afficherait un rectangle vide à sa place.');
    process.exit(1);
  }

  traces.push(glyphe.getPath(plume, 0, TAILLE));
  plume += glyphe.advanceWidth * echelle + TAILLE * SERRAGE;

  // Crénage de la police pour la paire — « o » suivi de « W » en a besoin.
  if (i < MOT.length - 1) {
    const suivant = police.charToGlyph(MOT[i + 1]);
    plume += police.getKerningValue(glyphe, suivant) * echelle;
  }
}

/** Boîte englobante de plusieurs tracés. */
function englobe(liste) {
  const b = { x1: Infinity, y1: Infinity, x2: -Infinity, y2: -Infinity };
  for (const t of liste) {
    const c = t.getBoundingBox();
    b.x1 = Math.min(b.x1, c.x1); b.y1 = Math.min(b.y1, c.y1);
    b.x2 = Math.max(b.x2, c.x2); b.y2 = Math.max(b.y2, c.y2);
  }
  return b;
}

const d = (liste) => liste.map((t) => t.toPathData(2)).join(' ');

const dProno = d(traces.slice(0, COUPE));
const dWin   = d(traces.slice(COUPE));
const boite  = englobe(traces);

/**
 * Assemble le SVG.
 *
 * La boîte est calculée sur les contours réels, pas sur les métriques de la
 * police : les jambages qui ne servent pas ici (accents, descendantes) y
 * ajouteraient un vide que personne ne verrait avant de centrer le logo
 * quelque part.
 */
function svg({ marge, fond, couleurProno, nom }) {
  const l = (boite.x2 - boite.x1) + marge * 2;
  const h = (boite.y2 - boite.y1) + marge * 2;
  const dx = -boite.x1 + marge;
  const dy = -boite.y1 + marge;

  const rect = fond
    ? `\n  <rect width="${l.toFixed(2)}" height="${h.toFixed(2)}" `
      + `rx="${(h * 0.18).toFixed(2)}" fill="${fond}"/>`
    : '';

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${l.toFixed(2)} ${h.toFixed(2)}"
     width="${Math.round(l)}" height="${Math.round(h)}" role="img" aria-label="PronoWin">
  <title>PronoWin</title>
  <!--
    ${nom}

    Généré par brand/logotype.js — ne pas retoucher à la main, régénérer.
    Lettres converties en tracés depuis Inter Bold (SIL OFL 1.1) : aucune
    police n'est requise pour l'afficher, et le rendu est le même partout.
  -->${rect}
  <g transform="translate(${dx.toFixed(2)}, ${dy.toFixed(2)})">
    <path fill="${couleurProno}" d="${dProno}"/>
    <path fill="${ACCENT}" d="${dWin}"/>
  </g>
</svg>
`;
}

const variantes = [
  ['logotype-pronowin-fond.svg',  { marge: TAILLE * 0.42, fond: FOND, couleurProno: CLAIR,
                                    nom: 'Sur fond bleu-nuit, comme la référence.' }],
  ['logotype-pronowin-clair.svg', { marge: TAILLE * 0.12, fond: null, couleurProno: CLAIR,
                                    nom: 'Fond transparent, à poser sur un fond sombre.' }],
  ['logotype-pronowin-noir.svg',  { marge: TAILLE * 0.12, fond: null, couleurProno: SOMBRE,
                                    nom: 'Fond transparent, à poser sur un fond clair.' }],
];

for (const [nom, opts] of variantes) {
  fs.writeFileSync(path.join(RACINE, nom), svg(opts), 'utf8');
  console.log(`  ${nom}`);
}

console.log(`\n  boîte des contours : ${(boite.x2 - boite.x1).toFixed(1)} x `
          + `${(boite.y2 - boite.y1).toFixed(1)} unités (corps ${TAILLE})`);
