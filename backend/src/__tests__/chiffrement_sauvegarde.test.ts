
import fs from 'fs';
import os from 'os';
import path from 'path';
const { chiffrer, dechiffrer } = require('../../../exploitation/chiffrement-sauvegarde.js');
const { copier } = require('../../../exploitation/pronowin-copie-distante.js');
let dir: string, source: string, cle: string, chiffre: string, copie: string;
beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'chiffrement-pronowin-'));
  source = path.join(dir, 'pronowin_2026-10-08_0230.dump');
  cle = path.join(dir, 'cle'); chiffre = path.join(dir, 'copie.enc'); copie = path.join(dir, 'restaure.dump');
  fs.writeFileSync(source, Buffer.from('Sauvegarde privée de contrôle\n'.repeat(100)));
  fs.writeFileSync(cle, 'cle-de-test-sans-secret-reel-01234567890123456789');
});
afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));
it('restaure à l’identique et ne laisse pas le contenu en clair dans le chiffré', async () => {
  await chiffrer(source, chiffre, cle);
  expect(fs.readFileSync(chiffre).includes(Buffer.from('Sauvegarde privée'))).toBe(false);
  await dechiffrer(chiffre, copie, cle);
  expect(fs.readFileSync(copie)).toEqual(fs.readFileSync(source));
});
it.each(['contenu', 'entete', 'tag', 'cle'])('refuse une altération de %s sans produire une restauration', async zone => {
  await chiffrer(source, chiffre, cle);
  if (zone === 'cle') fs.writeFileSync(cle, 'autre-cle-de-test-012345678901234567890123456789');
  else {
    const b = fs.readFileSync(chiffre);
    b[zone === 'entete' ? 9 : zone === 'tag' ? b.length - 1 : 50] ^= 1;
    fs.writeFileSync(chiffre, b);
  }
  await expect(dechiffrer(chiffre, copie, cle)).rejects.toThrow();
  expect(fs.existsSync(copie)).toBe(false);
  expect(fs.readdirSync(dir).some(n => n.endsWith('.partiel'))).toBe(false);
});
it('ne remplace jamais une restauration existante', async () => {
  await chiffrer(source, chiffre, cle); fs.writeFileSync(copie, 'à garder');
  await expect(dechiffrer(chiffre, copie, cle)).rejects.toThrow(/existe/);
  expect(fs.readFileSync(copie, 'utf8')).toBe('à garder');
});
it('purge les pages S3 suivantes et préserve les autres documents', async () => {
  const cmd = Object.fromEntries(['GetPublicAccessBlockCommand','PutObjectCommand','DeleteObjectCommand','ListObjectsV2Command'].map(n =>
    [n, class { constructor(public input: any) {} static nom = n; }]));
  let page = 0; const supprimees: string[] = [];
  const s3 = { send: async (c: any) => {
    if (c.constructor.nom === 'DeleteObjectCommand') supprimees.push(c.input.Key);
    if (c.constructor.nom === 'GetPublicAccessBlockCommand') return {
        PublicAccessBlockConfiguration: { BlockPublicAcls: true, IgnorePublicAcls: true,
          BlockPublicPolicy: true, RestrictPublicBuckets: true },
      };
      if (c.constructor.nom === 'ListObjectsV2Command') return page++ === 0
      ? { Contents: [{ Key: 'prod/facture.pdf', LastModified: new Date('2020-01-01') }], IsTruncated: true, NextContinuationToken: 'suite' }
      : { Contents: [{ Key: 'prod/pronowin_2020-01-01_0230.dump.enc', LastModified: new Date('2020-01-01') }] };
    return {};
  } };
  const r = await copier({ config: { prefixe: 'prod', bucket: 'prive', region: 'eu-west-3', fichierCle: cle },
    fichiers: [source], s3, cmd, lire: async () => 403 });
  expect(page).toBe(2); expect(r.supprimes).toBe(1);
  expect(supprimees).not.toContain('prod/facture.pdf');
});
