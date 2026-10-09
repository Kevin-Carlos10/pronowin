/**
 * Planche de contrôle : le logo tel que Telegram l'affiche réellement.
 *
 * Un logo se juge à deux endroits que le fichier source ne montre pas :
 *
 *  1. **En cercle.** Telegram recadre la photo d'un canal en disque. Ce qui
 *     dépasse est perdu, et on ne s'en aperçoit qu'une fois publié.
 *  2. **En 40 px.** C'est la taille dans la liste des discussions — là où le
 *     logo est vu cent fois pour une fois en grand. Un détail qui s'y empâte
 *     est un détail de trop.
 *
 * La planche pose côte à côte le disque en 512 et les réductions 160 / 80 / 40
 * ré-agrandies au voisin le plus proche, pour montrer ce qui subsiste vraiment.
 *
 *     node brand/verifier.js
 */
const fs   = require('fs');
const path = require('path');

const RACINE = path.resolve(__dirname);
const sharp  = require(path.join(RACINE, '..', 'mobile_new', 'node_modules', 'sharp'));

// Sujet de la planche : passer un nom de fichier en argument pour en contrôler
// un autre. Par défaut, l'assemblage carré — c'est lui qu'on pose en photo de
// profil, et c'est là que le recadrage circulaire fait des dégâts.
const SOURCE = path.join(RACINE,
  process.argv[2] || 'profil-pronowin-sombre-512.png');

if (!fs.existsSync(SOURCE)) {
  console.error(`${path.basename(SOURCE)} introuvable — lancez d'abord : npm run rendre`);
  process.exit(1);
}

const ETIQUETTE = path.basename(SOURCE, '.png');

const disque = Buffer.from(
  '<svg width="512" height="512"><circle cx="256" cy="256" r="256" fill="#fff"/></svg>');

(async () => {
  // 1. Le disque, comme Telegram le découpe.
  const rond = await sharp(SOURCE)
    .composite([{ input: disque, blend: 'dest-in' }])
    .png()
    .toBuffer();

  await sharp(rond).toFile(path.join(RACINE, `apercu-cercle-${ETIQUETTE}.png`));

  // 2. Les petites tailles, ré-agrandies sans lissage pour montrer ce qui reste.
  const vignettes = [];
  for (const t of [160, 80, 40]) {
    const petit = await sharp(rond).resize(t, t).png().toBuffer();
    vignettes.push(await sharp(petit)
      .resize(256, 256, { kernel: 'nearest' })
      .png()
      .toBuffer());
  }

  // 3. Planche : disque en grand à gauche, les trois réductions à droite.
  const planche = await sharp({
    create: { width: 512 + 256, height: 768, channels: 4,
              background: { r: 245, g: 245, b: 247, alpha: 1 } },
  })
    .composite([
      { input: await sharp(rond).resize(512, 512).toBuffer(), top: 128, left: 0 },
      { input: vignettes[0], top: 0,   left: 512 },
      { input: vignettes[1], top: 256, left: 512 },
      { input: vignettes[2], top: 512, left: 512 },
    ])
    .png()
    .toFile(path.join(RACINE, `planche-${ETIQUETTE}.png`));

  console.log(`  apercu-cercle-${ETIQUETTE}.png`.padEnd(48) + 'recadrage circulaire de Telegram');
  console.log(`  planche-${ETIQUETTE}.png`.padEnd(48) + '512 px, puis 160 / 80 / 40 ré-agrandis');
  console.log('  planche :', planche.width + 'x' + planche.height);
})().catch((e) => { console.error(e.message); process.exit(1); });
