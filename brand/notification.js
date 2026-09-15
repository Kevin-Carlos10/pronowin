/**
 * Icône de notification Android : trophée blanc, « P » évidé, fond transparent.
 *
 * Depuis Android 5, la petite icône d'une notification est rendue **en
 * silhouette** : le système ne garde que le canal alpha et repeint la forme.
 * Une icône en couleurs pleines y devient un carré blanc, et l'icône de
 * lanceur — qui a un fond orange opaque — en est une.
 *
 * D'où ce fichier séparé : mêmes tracés que l'emblème, mais en blanc sur
 * transparent, le « P » percé plutôt que peint. Percé, il reste lisible une
 * fois la forme repeinte ; peint, il disparaîtrait dans la silhouette.
 *
 * Les tracés sont **relus depuis logo-pronowin.svg**, comme pour l'assemblage :
 * deux copies d'un même dessin finissent par diverger, et celle que personne
 * ne regarde est celle qui se périme.
 *
 *     node brand/notification.js
 */
const fs    = require('fs');
const path  = require('path');
const sharp = require(path.join(__dirname, '..', 'mobile_new', 'node_modules', 'sharp'));

const RACINE = path.resolve(__dirname);
const RES    = path.join(RACINE, '..', 'mobile_new', 'android', 'app', 'src', 'main', 'res');

// Tailles Android pour une petite icône de notification.
const DENSITES = {
  'drawable-mdpi':    24,
  'drawable-hdpi':    36,
  'drawable-xhdpi':   48,
  'drawable-xxhdpi':  72,
  'drawable-xxxhdpi': 96,
};

// ── Extraction, avec validation ──────────────────────────────────────────────

const embleme = fs.readFileSync(path.join(RACINE, 'logo-pronowin.svg'), 'utf8');

const anses = [...embleme.matchAll(/<path d="(M(?:176|336) 180[^"]+)"\s*\/>/g)].map((m) => m[1]);
const coupe = (embleme.match(/<path fill="#FFFFFF" d="([^"]+)"/) || [])[1];
const lettreP = embleme.match(
  /<path fill="#E8541A" fill-rule="evenodd" transform="([^"]+)" d="([^"]+)"/);

if (anses.length !== 2 || !coupe || !lettreP) {
  console.error('EXTRACTION INCOMPLÈTE depuis logo-pronowin.svg :');
  console.error(`  anses ${anses.length}/2 · coupe ${coupe ? 'ok' : 'absente'} `
              + `· « P » ${lettreP ? 'ok' : 'absent'}`);
  console.error("Une icône amputée d'une anse serait produite sans que rien ne le dise.");
  process.exit(1);
}

// Boîte du trophée dans le repère de l'emblème, demi-épaisseur des anses
// comprise. Identique à celle de lockup.js.
const T = { x: 107, y: 150, l: 298, h: 238 };

// La forme occupe 88 % du carré : Android attend un glyphe qui remplit son
// cadre, avec une marge courte.
const COTE = 512;
const k  = (COTE * 0.88) / Math.max(T.l, T.h);
const tx = (COTE - T.l * k) / 2 - T.x * k;
const ty = (COTE - T.h * k) / 2 - T.y * k;

const nettoyer = (d) => d.replace(/\s+/g, ' ').trim();

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${COTE} ${COTE}"
     width="${COTE}" height="${COTE}">
  <!--
    Icône de notification. Blanc sur transparent, « P » percé.
    Générée par brand/notification.js — ne pas retoucher, régénérer.
  -->
  <defs>
    <mask id="trou">
      <rect width="${COTE}" height="${COTE}" fill="black"/>
      <g transform="translate(${tx.toFixed(2)}, ${ty.toFixed(2)}) scale(${k.toFixed(4)})">
        <g fill="none" stroke="white" stroke-width="22"
           stroke-linecap="round" stroke-linejoin="round">
          <path d="${anses[0]}"/>
          <path d="${anses[1]}"/>
        </g>
        <path fill="white" d="${nettoyer(coupe)}"/>
        <path fill="black" fill-rule="evenodd" transform="${lettreP[1]}"
              d="${nettoyer(lettreP[2])}"/>
      </g>
    </mask>
  </defs>
  <rect width="${COTE}" height="${COTE}" fill="white" mask="url(#trou)"/>
</svg>
`;

fs.writeFileSync(path.join(RACINE, 'ic_notification.svg'), svg, 'utf8');

(async () => {
  console.log('  ic_notification.svg');
  for (const [dossier, taille] of Object.entries(DENSITES)) {
    const cible = path.join(RES, dossier);
    fs.mkdirSync(cible, { recursive: true });
    const fichier = path.join(cible, 'ic_notification.png');

    await sharp(Buffer.from(svg), { density: 384 })
      .resize(taille, taille)
      .png({ compressionLevel: 9 })
      .toFile(fichier);

    const m = await sharp(fichier).metadata();
    if (!m.hasAlpha) {
      console.error(`  ${dossier} : image SANS canal alpha — Android la rendrait pleine`);
      process.exitCode = 1;
      continue;
    }
    console.log(`  ${dossier.padEnd(18)} ${m.width}x${m.height}  alpha ok  `
              + `${(fs.statSync(fichier).size / 1024).toFixed(1)} Ko`);
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
