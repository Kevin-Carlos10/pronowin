/**
 * WOFF → TTF.
 *
 * `opentype.js` lit le TTF et l'OTF, pas le WOFF ; `@fontsource` ne livre que
 * du WOFF et du WOFF2. Or un WOFF n'est qu'un conteneur : les mêmes tables
 * qu'un TTF, chacune éventuellement compressée en zlib, précédées d'un en-tête
 * de 44 octets. La conversion est mécanique, et Node sait déjà décompresser.
 *
 * (Le WOFF2, lui, utilise Brotli **et** une transformation des tables `glyf` /
 * `loca` : ce n'est pas la même opération, et ce fichier ne la fait pas. Il
 * refuse explicitement plutôt que de produire une police silencieusement
 * corrompue.)
 *
 *     node brand/woff2ttf.js entree.woff sortie.ttf
 */
const fs   = require('fs');
const zlib = require('zlib');

function woffVersTtf(woff) {
  const signature = woff.toString('ascii', 0, 4);
  if (signature === 'wOF2') {
    throw new Error('WOFF2 non pris en charge (Brotli + tables transformées). '
                  + 'Fournir un .woff ou un .ttf.');
  }
  if (signature !== 'wOFF') {
    throw new Error(`signature « ${signature} » — ce n'est pas un WOFF.`);
  }

  const flavor    = woff.readUInt32BE(4);
  const numTables = woff.readUInt16BE(12);

  const entrees = [];
  for (let i = 0; i < numTables; i++) {
    const p = 44 + i * 20;
    entrees.push({
      tag:        woff.toString('ascii', p, p + 4),
      offset:     woff.readUInt32BE(p + 4),
      compLength: woff.readUInt32BE(p + 8),
      origLength: woff.readUInt32BE(p + 12),
      checksum:   woff.readUInt32BE(p + 16),
    });
  }

  // Les tables doivent être triées par tag dans un sfnt.
  entrees.sort((a, b) => (a.tag < b.tag ? -1 : a.tag > b.tag ? 1 : 0));

  const donnees = entrees.map((e) => {
    const brut = woff.subarray(e.offset, e.offset + e.compLength);
    // compLength === origLength signifie « stockée telle quelle ».
    const table = e.compLength >= e.origLength ? brut : zlib.inflateSync(brut);
    if (table.length !== e.origLength) {
      throw new Error(`table ${e.tag} : ${table.length} octets décompressés, `
                    + `${e.origLength} attendus.`);
    }
    return table;
  });

  // En-tête sfnt : version, nombre de tables, et les trois champs de recherche
  // binaire que le format exige (ignorés par les lecteurs modernes, mais un
  // fichier qui ne les porte pas est hors spécification).
  const puissance     = Math.floor(Math.log2(numTables));
  const searchRange   = Math.pow(2, puissance) * 16;
  const entrySelector = puissance;
  const rangeShift    = numTables * 16 - searchRange;

  const enTete = Buffer.alloc(12);
  enTete.writeUInt32BE(flavor, 0);
  enTete.writeUInt16BE(numTables, 4);
  enTete.writeUInt16BE(searchRange, 6);
  enTete.writeUInt16BE(entrySelector, 8);
  enTete.writeUInt16BE(rangeShift, 10);

  const repertoire = Buffer.alloc(numTables * 16);
  let curseur = 12 + numTables * 16;
  const corps = [];

  entrees.forEach((e, i) => {
    const table = donnees[i];
    const p = i * 16;
    repertoire.write(e.tag, p, 4, 'ascii');
    repertoire.writeUInt32BE(e.checksum, p + 4);
    repertoire.writeUInt32BE(curseur, p + 8);
    repertoire.writeUInt32BE(e.origLength, p + 12);

    corps.push(table);
    curseur += table.length;

    // Alignement sur 4 octets, exigé entre deux tables.
    const reste = table.length % 4;
    if (reste !== 0) {
      const bourrage = Buffer.alloc(4 - reste);
      corps.push(bourrage);
      curseur += bourrage.length;
    }
  });

  return Buffer.concat([enTete, repertoire, ...corps]);
}

module.exports = { woffVersTtf };

if (require.main === module) {
  const [entree, sortie] = process.argv.slice(2);
  if (!entree || !sortie) {
    console.error('usage : node woff2ttf.js entree.woff sortie.ttf');
    process.exit(1);
  }
  const ttf = woffVersTtf(fs.readFileSync(entree));
  fs.writeFileSync(sortie, ttf);
  console.log(`${sortie} — ${(ttf.length / 1024).toFixed(1)} Ko`);
}
