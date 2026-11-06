/**
 * Rend le logo SVG en PNG, aux tailles utiles.
 *
 * `sharp` vit dans mobile_new/node_modules : ce script s'exécute donc depuis
 * n'importe où, mais résout la bibliothèque là-bas et travaille en chemins
 * absolus.
 *
 * Deux variantes, pour une raison précise :
 *
 *  - `logo-*.png` garde les coins arrondis (rx=112), pour l'icône
 *    d'application, le site et les stores.
 *  - `telegram-*.png` est à fond perdu. Telegram recadre la photo d'un canal
 *    en cercle : des coins arrondis y seraient rognés, et le liseré
 *    transparent qu'ils laissent se voit sur les fonds clairs.
 *
 *     node brand/rendre.js
 */
const fs   = require('fs');
const path = require('path');

const RACINE = path.resolve(__dirname);
const sharp  = require(path.join(RACINE, '..', 'mobile_new', 'node_modules', 'sharp'));

const svg = fs.readFileSync(path.join(RACINE, 'logo-pronowin.svg'), 'utf8');

// Fond perdu : on neutralise l'arrondi, rien d'autre ne change.
const svgPlein = svg.replace('rx="112"', 'rx="0"');
if (svgPlein === svg) {
  console.error('ANCRE INTROUVABLE : rx="112" absent du SVG — le rendu Telegram');
  console.error('aurait gardé les coins arrondis sans que rien ne le signale.');
  process.exit(1);
}

const sorties = [
  ['logo-pronowin-512.png',   svg,       512],
  ['logo-pronowin-1024.png',  svg,      1024],
  ['pronowin-telegram-512.png',  svgPlein,  512],
  ['pronowin-telegram-1024.png', svgPlein, 1024],
];

// Assemblages carrés « emblème + mot », pour une photo de profil. Générés par
// lockup.js ; déjà à fond perdu, donc rendus tels quels.
for (const base of ['profil-pronowin-sombre', 'profil-pronowin-orange']) {
  const f = path.join(RACINE, `${base}.svg`);
  if (fs.existsSync(f)) {
    const source = fs.readFileSync(f, 'utf8');
    sorties.push([`${base}-512.png`, source, 512], [`${base}-1024.png`, source, 1024]);
  } else {
    console.error(`  MANQUE ${base}.svg — lancez d'abord : node brand/lockup.js`);
    process.exitCode = 1;
  }
}

// Logotypes : générés par logotype.js, rendus ici à une largeur utile. Ils ne
// sont pas carrés — on impose la largeur et on laisse la hauteur suivre.
const LOGOTYPES = [
  'logotype-pronowin-fond',
  'logotype-pronowin-clair',
  'logotype-pronowin-noir',
];

(async () => {
  for (const [nom, source, taille] of sorties) {
    const cible = path.join(RACINE, nom);
    await sharp(Buffer.from(source), { density: 384 })
      .resize(taille, taille)
      .png({ compressionLevel: 9 })
      .toFile(cible);

    const { width, height, channels } = await sharp(cible).metadata();
    const octets = fs.statSync(cible).size;
    console.log(`  ${nom.padEnd(30)} ${width}x${height}  ${channels} canaux  ${(octets / 1024).toFixed(1)} Ko`);
  }

  for (const base of LOGOTYPES) {
    const src = path.join(RACINE, `${base}.svg`);
    if (!fs.existsSync(src)) {
      console.error(`  MANQUE ${base}.svg — lancez d'abord : node brand/logotype.js`);
      process.exitCode = 1;
      continue;
    }
    for (const largeur of [600, 1200]) {
      const nom = `${base}-${largeur}.png`;
      await sharp(fs.readFileSync(src), { density: 384 })
        .resize({ width: largeur })
        .png({ compressionLevel: 9 })
        .toFile(path.join(RACINE, nom));

      const m = await sharp(path.join(RACINE, nom)).metadata();
      const o = fs.statSync(path.join(RACINE, nom)).size;
      console.log(`  ${nom.padEnd(30)} ${m.width}x${m.height}  ${m.channels} canaux  ${(o / 1024).toFixed(1)} Ko`);
    }
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
