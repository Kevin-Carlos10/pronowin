/**
 * Visuel de mise en avant Google Play — 1024 × 500.
 *
 * Contraintes de la fiche, qui dictent le dessin :
 *
 *  - **Sans canal alpha.** Google refuse la transparence sur ce visuel. Le
 *    fond est donc peint, et la sortie aplatie.
 *  - **Recadrable.** Selon la surface, Play rogne les bords et superpose
 *    parfois l'icône de l'application. Tout ce qui compte reste au centre,
 *    dans une zone sûre.
 *  - **Lu très petit.** Sur une liste de recommandations, il fait quelques
 *    centimètres. Une phrase de plus n'y serait pas lue — d'où le parti pris :
 *    l'emblème, le nom, une ligne.
 *
 * L'emblème et le logotype sont **relus depuis leurs sources**, comme partout
 * ailleurs dans ce dossier : deux copies d'un même dessin finissent par
 * diverger, et celle que personne ne regarde est celle qui se périme.
 *
 *     node brand/feature-graphic.js
 */
const fs    = require('fs');
const path  = require('path');
const sharp = require(path.join(__dirname, '..', 'mobile_new', 'node_modules', 'sharp'));

const RACINE = path.resolve(__dirname);

const L = 1024;
const H = 500;

// Zone sûre : Play peut rogner les bords. Rien d'essentiel au-delà.
const MARGE_SURE = 0.86;

// ── Sources, relues et validées ──────────────────────────────────────────────

const embleme = fs.readFileSync(path.join(RACINE, 'logo-pronowin.svg'), 'utf8');

const anses = [...embleme.matchAll(/<path d="(M(?:176|336) 180[^"]+)"\s*\/>/g)].map((m) => m[1]);
const coupe = (embleme.match(/<path fill="#FFFFFF" d="([^"]+)"/) || [])[1];
const lettreP = embleme.match(
  /<path fill="#E8541A" fill-rule="evenodd" transform="([^"]+)" d="([^"]+)"/);

const logotype = fs.readFileSync(path.join(RACINE, 'logotype-pronowin-clair.svg'), 'utf8');
const motProno = (logotype.match(/<path fill="#F5F5F7" d="([^"]+)"/) || [])[1];
const motWin   = (logotype.match(/<path fill="#E8541A" d="([^"]+)"/) || [])[1];
const boiteMot = logotype.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);

// Le groupe qui positionne les glyphes. Les tracés d'opentype.js sortent en
// coordonnées de police — ligne de base à zéro, ascendantes négatives — et
// c'est ce `translate` qui les amène dans la boîte. L'extraire aussi : sans
// lui, le mot flotte au-dessus de sa place, et rien ne le signale sinon l'œil.
const poseMot = logotype.match(/<g transform="translate\(([-\d.]+), ?([-\d.]+)\)"/);

if (anses.length !== 2 || !coupe || !lettreP || !motProno || !motWin || !boiteMot || !poseMot) {
  console.error('EXTRACTION INCOMPLÈTE :');
  console.error(`  emblème — anses ${anses.length}/2 · coupe ${coupe ? 'ok' : 'absente'} `
              + `· « P » ${lettreP ? 'ok' : 'absent'}`);
  console.error(`  logotype — « Prono » ${motProno ? 'ok' : 'absent'} `
              + `· « Win » ${motWin ? 'ok' : 'absent'} `
              + `· boîte ${boiteMot ? 'ok' : 'absente'} `
              + `· pose ${poseMot ? 'ok' : 'absente'}`);
  console.error('Un visuel amputé serait produit sans que rien ne le signale.');
  process.exit(1);
}

// ── Mise en page ─────────────────────────────────────────────────────────────

// Boîte du trophée dans le repère de l'emblème, demi-épaisseur des anses
// comprise. Identique à lockup.js et notification.js.
const T = { x: 107, y: 150, l: 298, h: 238 };

const MOT_L = parseFloat(boiteMot[1]);
const MOT_H = parseFloat(boiteMot[2]);

const hTrophee = 150;
const kTrophee = hTrophee / T.h;
const lTrophee = T.l * kTrophee;

const hMot = 92;
const kMot = hMot / MOT_H;
const lMot = MOT_L * kMot;

const ECART = 34;
const lTotale = lTrophee + ECART + lMot;

if (lTotale > L * MARGE_SURE) {
  console.error(`DÉBORDEMENT : ${Math.round(lTotale)} px de large pour une zone sûre `
              + `de ${Math.round(L * MARGE_SURE)} px. Play rognerait le dessin.`);
  process.exit(1);
}

const xDepart = (L - lTotale) / 2;
const yTrophee = (H - hTrophee) / 2 - 18;   // remonté : la ligne de texte suit
const yMot     = (H - hMot) / 2 - 18;

const nettoyer = (d) => d.replace(/\s+/g, ' ').trim();

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${L} ${H}"
     width="${L}" height="${H}">
  <defs>
    <linearGradient id="fond" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"    stop-color="#161A24"/>
      <stop offset="0.55" stop-color="#0F1218"/>
      <stop offset="1"    stop-color="#1B1016"/>
    </linearGradient>
    <radialGradient id="lueur" cx="0.5" cy="0.42" r="0.55">
      <stop offset="0"   stop-color="#E8541A" stop-opacity="0.20"/>
      <stop offset="1"   stop-color="#E8541A" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="${L}" height="${H}" fill="url(#fond)"/>
  <rect width="${L}" height="${H}" fill="url(#lueur)"/>

  <g transform="translate(${xDepart.toFixed(2)}, ${yTrophee.toFixed(2)}) scale(${kTrophee.toFixed(4)})">
    <g transform="translate(${-T.x}, ${-T.y})">
      <g fill="none" stroke="#FFFFFF" stroke-width="22"
         stroke-linecap="round" stroke-linejoin="round">
        <path d="${anses[0]}"/>
        <path d="${anses[1]}"/>
      </g>
      <path fill="#FFFFFF" d="${nettoyer(coupe)}"/>
      <path fill="#E8541A" fill-rule="evenodd" transform="${lettreP[1]}"
            d="${nettoyer(lettreP[2])}"/>
    </g>
  </g>

  <g transform="translate(${(xDepart + lTrophee + ECART).toFixed(2)}, ${yMot.toFixed(2)}) scale(${kMot.toFixed(4)})">
    <g transform="translate(${poseMot[1]}, ${poseMot[2]})">
      <path fill="#F5F5F7" d="${motProno}"/>
      <path fill="#E8541A" d="${motWin}"/>
    </g>
  </g>

  <text x="${L / 2}" y="${H - 92}" text-anchor="middle"
        font-family="Inter, -apple-system, Segoe UI, Roboto, sans-serif"
        font-size="27" font-weight="500" fill="#F5F5F7" fill-opacity="0.72"
        letter-spacing="0.4">Le pronostic qui montre ses chiffres</text>
</svg>
`;

fs.writeFileSync(path.join(RACINE, 'feature-graphic.svg'), svg, 'utf8');

(async () => {
  const cible = path.join(RACINE, 'feature-graphic-1024x500.png');

  await sharp(Buffer.from(svg), { density: 384 })
    .resize(L, H)
    .flatten({ background: '#161A24' })   // Play refuse le canal alpha
    .png({ compressionLevel: 9 })
    .toFile(cible);

  const m = await sharp(cible).metadata();
  const octets = fs.statSync(cible).size;

  console.log(`  feature-graphic.svg`);
  console.log(`  feature-graphic-1024x500.png   ${m.width}x${m.height}  `
            + `${m.channels} canaux  ${(octets / 1024).toFixed(1)} Ko`);

  if (m.width !== 1024 || m.height !== 500) {
    console.error('  DIMENSIONS REFUSÉES par Play : il exige exactement 1024 × 500.');
    process.exitCode = 1;
  }
  if (m.hasAlpha) {
    console.error('  CANAL ALPHA présent : Play refuse la transparence sur ce visuel.');
    process.exitCode = 1;
  }
  console.log(`  emprise du dessin : ${Math.round(lTotale)} px sur ${L} `
            + `(${((lTotale / L) * 100).toFixed(1)} % — zone sûre ${MARGE_SURE * 100} %)`);
})().catch((e) => { console.error(e.message); process.exit(1); });
