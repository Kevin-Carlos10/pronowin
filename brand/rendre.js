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

(async () => {
  for (const [nom, source, taille] of sorties) {
    const cible = path.join(RACINE, nom);
    await sharp(Buffer.from(source), { density: 384 })
      .resize(taille, taille)
      .png({ compressionLevel: 9 })
      .toFile(cible);

    const { width, height, channels } = await sharp(cible).metadata();
    const octets = fs.statSync(cible).size;
    console.log(`  ${nom.padEnd(28)} ${width}x${height}  ${channels} canaux  ${(octets / 1024).toFixed(1)} Ko`);
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
