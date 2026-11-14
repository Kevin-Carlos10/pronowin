/**
 * Assemblage « emblème + mot », carré, pour une photo de profil.
 *
 * Le problème qu'il résout : Telegram recadre la photo d'un canal **en
 * cercle**. Y poser le logotype seul ne laisse voir que « Pro » — le mot est
 * large et plat, le disque en coupe les deux bouts. Il faut une image carrée
 * dont le contenu tient dans le disque inscrit : l'emblème au-dessus, le mot
 * en dessous.
 *
 * Le trophée est **relu depuis logo-pronowin.svg**, pas recopié ici. Deux
 * copies d'un même dessin finissent toujours par diverger, et celle que
 * personne ne regarde est celle qui se périme. L'extraction se valide : si le
 * fichier source change de structure, ce script s'arrête au lieu de produire
 * un assemblage amputé d'une anse.
 *
 *     node brand/lockup.js
 */
const fs   = require('fs');
const path = require('path');
const ot   = require('opentype.js');

const RACINE = path.resolve(__dirname);

const CLAIR  = '#F5F5F7';
const ACCENT = '#E8541A';
const FOND   = '#161A24';

const COTE   = 1024;             // image carrée
const RAYON  = COTE / 2;         // disque de recadrage de Telegram
const MARGE_SECURITE = 0.86;     // du rayon — au-delà, ça frôle le bord

// ── 1. Le trophée, relu depuis l'emblème ─────────────────────────────────────

const embleme = fs.readFileSync(path.join(RACINE, 'logo-pronowin.svg'), 'utf8');

const anses = [...embleme.matchAll(/<path d="(M(?:176|336) 180[^"]+)"\s*\/>/g)]
  .map((m) => m[1]);
const coupe = (embleme.match(/<path fill="#FFFFFF" d="([^"]+)"/) || [])[1];
const lettreP = embleme.match(
  /<path fill="#E8541A" fill-rule="evenodd" transform="([^"]+)" d="([^"]+)"/);

if (anses.length !== 2 || !coupe || !lettreP) {
  console.error('EXTRACTION INCOMPLÈTE depuis logo-pronowin.svg :');
  console.error(`  anses  : ${anses.length}/2`);
  console.error(`  coupe  : ${coupe ? 'ok' : 'introuvable'}`);
  console.error(`  « P »  : ${lettreP ? 'ok' : 'introuvable'}`);
  console.error("L'assemblage aurait été produit sans une partie du dessin, et");
  console.error("rien ne l'aurait signalé — d'où cet arrêt.");
  process.exit(1);
}

// Boîte du trophée dans le repère de l'emblème, demi-épaisseur des anses
// comprise (le trait déborde de son tracé de 11 unités de chaque côté).
const TROPHEE = { x: 107, y: 150, l: 298, h: 238 };

// ── 2. Le mot, en tracés ─────────────────────────────────────────────────────

const POLICE = path.join(RACINE, 'inter-700.ttf');
if (!fs.existsSync(POLICE)) {
  console.error(`${path.basename(POLICE)} absent — lancez d'abord : npm run logotype`);
  process.exit(1);
}
const octets = fs.readFileSync(POLICE);
const police = ot.parse(octets.buffer.slice(octets.byteOffset,
                                            octets.byteOffset + octets.byteLength));

const MOT = 'PronoWin';
const COUPE_COULEUR = 5;      // « Prono » | « Win »
const CORPS   = 200;
const SERRAGE = -0.02;

const echelle = CORPS / police.unitsPerEm;
const traces  = [];
let plume = 0;
for (let i = 0; i < MOT.length; i++) {
  const g = police.charToGlyph(MOT[i]);
  traces.push(g.getPath(plume, 0, CORPS));
  plume += g.advanceWidth * echelle + CORPS * SERRAGE;
  if (i < MOT.length - 1) {
    plume += police.getKerningValue(g, police.charToGlyph(MOT[i + 1])) * echelle;
  }
}

const boite = traces.reduce((b, t) => {
  const c = t.getBoundingBox();
  return { x1: Math.min(b.x1, c.x1), y1: Math.min(b.y1, c.y1),
           x2: Math.max(b.x2, c.x2), y2: Math.max(b.y2, c.y2) };
}, { x1: Infinity, y1: Infinity, x2: -Infinity, y2: -Infinity });

const MOT_L = boite.x2 - boite.x1;
const MOT_H = boite.y2 - boite.y1;

const d = (liste) => liste.map((t) => t.toPathData(2)).join(' ');
const dProno = d(traces.slice(0, COUPE_COULEUR));
const dWin   = d(traces.slice(COUPE_COULEUR));

// ── 3. Mise en page, puis vérification qu'elle tient dans le disque ──────────

const LARGEUR_MOT = 670;                          // largeur visée du mot
const kMot        = LARGEUR_MOT / MOT_L;
const hMot        = MOT_H * kMot;

const HAUTEUR_TROPHEE = 324;
const kTrophee        = HAUTEUR_TROPHEE / TROPHEE.h;
const lTrophee        = TROPHEE.l * kTrophee;

const ECART = 65;
const hTotale = HAUTEUR_TROPHEE + ECART + hMot;
const yHaut   = (COTE - hTotale) / 2;

const yTrophee = yHaut;
const yMot     = yHaut + HAUTEUR_TROPHEE + ECART;

/** Le point le plus éloigné du centre, parmi les coins des deux blocs. */
function debord() {
  const coins = [
    [lTrophee / 2, yTrophee - RAYON], [lTrophee / 2, yTrophee + HAUTEUR_TROPHEE - RAYON],
    [LARGEUR_MOT / 2, yMot - RAYON],  [LARGEUR_MOT / 2, yMot + hMot - RAYON],
  ];
  return Math.max(...coins.map(([dx, dy]) => Math.hypot(dx, dy)));
}

const distance = debord();
const ratio    = distance / RAYON;

console.log(`  trophée  ${lTrophee.toFixed(0)} x ${HAUTEUR_TROPHEE} px`);
console.log(`  mot      ${LARGEUR_MOT} x ${hMot.toFixed(0)} px`);
console.log(`  coin le plus éloigné : ${distance.toFixed(0)} px sur ${RAYON} de rayon `
          + `(${(ratio * 100).toFixed(1)} %)`);

if (ratio > MARGE_SECURITE) {
  console.error(`\nDÉBORDEMENT : le contenu atteint ${(ratio * 100).toFixed(1)} % du rayon, `
              + `au-delà de la limite de ${MARGE_SECURITE * 100} %.`);
  console.error('Le recadrage circulaire de Telegram rognerait le dessin — c\'est');
  console.error('exactement le défaut que cet assemblage doit corriger.');
  process.exit(1);
}

// ── 4. Écriture ──────────────────────────────────────────────────────────────

function svg({ fond, couleurMot, couleurAccent, couleurP, nom }) {
  const tx = (COTE - lTrophee) / 2 - TROPHEE.x * kTrophee;
  const ty = yTrophee - TROPHEE.y * kTrophee;
  const mx = (COTE - LARGEUR_MOT) / 2 - boite.x1 * kMot;
  const my = yMot - boite.y1 * kMot;

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${COTE} ${COTE}"
     width="${COTE}" height="${COTE}" role="img" aria-label="PronoWin">
  <title>PronoWin</title>
  <!--
    ${nom}

    Généré par brand/lockup.js — ne pas retoucher, régénérer.

    Carré, à fond perdu, contenu inscrit dans le disque : Telegram recadre la
    photo d'un canal en cercle. Le coin le plus éloigné du centre est à
    ${(ratio * 100).toFixed(1)} % du rayon.

    Le trophée est relu depuis logo-pronowin.svg ; le mot est converti en
    tracés depuis Inter Bold (SIL OFL 1.1).
  -->
  <rect width="${COTE}" height="${COTE}" fill="${fond}"/>

  <g transform="translate(${tx.toFixed(2)}, ${ty.toFixed(2)}) scale(${kTrophee.toFixed(4)})">
    <g fill="none" stroke="${couleurMot}" stroke-width="22"
       stroke-linecap="round" stroke-linejoin="round">
      <path d="${anses[0]}"/>
      <path d="${anses[1]}"/>
    </g>
    <path fill="${couleurMot}" d="${coupe.replace(/\s+/g, ' ').trim()}"/>
    <path fill="${couleurP}" fill-rule="evenodd" transform="${lettreP[1]}"
          d="${lettreP[2].replace(/\s+/g, ' ').trim()}"/>
  </g>

  <g transform="translate(${mx.toFixed(2)}, ${my.toFixed(2)}) scale(${kMot.toFixed(4)})">
    <path fill="${couleurMot}" d="${dProno}"/>
    <path fill="${couleurAccent}" d="${dWin}"/>
  </g>
</svg>
`;
}

const variantes = [
  ['profil-pronowin-sombre.svg', {
    fond: FOND, couleurMot: CLAIR, couleurAccent: ACCENT, couleurP: ACCENT,
    nom: 'Fond bleu-nuit, trophée blanc, « Win » en accent.' }],
  ['profil-pronowin-orange.svg', {
    fond: ACCENT, couleurMot: '#FFFFFF', couleurAccent: FOND, couleurP: ACCENT,
    nom: 'Fond orange plein, dessin blanc, « Win » en bleu-nuit.' }],
];

for (const [nom, opts] of variantes) {
  fs.writeFileSync(path.join(RACINE, nom), svg(opts), 'utf8');
  console.log(`  ${nom}`);
}
