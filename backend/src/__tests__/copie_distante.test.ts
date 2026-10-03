/**
 * Copie des sauvegardes hors du serveur (constat O4 de l'audit du
 * 24 septembre 2026) : exploitation/pronowin-copie-distante.js, contre des
 * doublures de S3 et de la lecture anonyme.
 *
 * Le bucket de l'application a été lisible sans identifiants : un dump de la
 * base ne doit partir que vers un préfixe qui ne l'est pas.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { copier, RETENTION_JOURS } = require('../../../exploitation/pronowin-copie-distante.js');

/** Les commandes S3, réduites à leur nom et à leurs paramètres. */
const cmd = Object.fromEntries(
  ['PutObjectCommand', 'DeleteObjectCommand', 'ListObjectsV2Command'].map((n) =>
    [n, class { constructor(public input: any) {} static nom = n; }]));

function faux(objetsExistants: { Key: string; LastModified: Date }[] = []) {
  const envois: { nom: string; input: any }[] = [];
  const s3 = {
    send: async (c: any) => {
      envois.push({ nom: c.constructor.nom, input: c.input });
      if (c.constructor.nom === 'ListObjectsV2Command') return { Contents: objetsExistants };
      return {};
    },
  };
  return { s3, envois };
}

const maintenant = new Date('2026-09-25T02:30:00Z');
const config = { bucket: 'sauvegardes', region: 'eu-west-3', prefixe: 'prod', fichierCle: '/cle' };
let dossier = '';
let dump = '';

beforeEach(() => {
  dossier = fs.mkdtempSync(path.join(os.tmpdir(), 'copie-distante-'));
  dump = path.join(dossier, 'pronowin_2026-09-25_0230.dump');
  fs.writeFileSync(dump, 'contenu de la base');
});
afterEach(() => fs.rmSync(dossier, { recursive: true, force: true }));

/** Un « chiffrement » de banc : écrit la cible, marque la source. */
const chiffrerFichier = (source: string, cible: string) =>
  fs.writeFileSync(cible, 'chiffré:' + fs.readFileSync(source, 'utf8'));

describe('copie distante (O4)', () => {
  it('un préfixe lisible sans identifiants : rien n\'est envoyé, le témoin est retiré', async () => {
    const { s3, envois } = faux();
    await expect(copier({ config, fichiers: [dump], s3, cmd, chiffrerFichier, maintenant,
      lire: async () => 200 })).rejects.toThrow(/lisible sans identifiants/);

    const cles = envois.filter((e) => e.nom === 'PutObjectCommand').map((e) => e.input.Key);
    expect(cles).toEqual([`prod/.controle-${maintenant.getTime()}`]);        // seul le témoin
    expect(envois.some((e) => e.nom === 'DeleteObjectCommand' && e.input.Key === cles[0])).toBe(true);
  });

  it('un contrôle non concluant (réseau) n\'envoie rien non plus', async () => {
    const { s3, envois } = faux();
    await expect(copier({ config, fichiers: [dump], s3, cmd, chiffrerFichier, maintenant,
      lire: async () => 0 })).rejects.toThrow(/non concluant/);
    expect(envois.filter((e) => e.nom === 'PutObjectCommand')).toHaveLength(1);
  });

  it('préfixe privé : le fichier part chiffré, sous le préfixe, et le clair reste local', async () => {
    const { s3, envois } = faux();
    const r = await copier({ config, fichiers: [dump], s3, cmd, chiffrerFichier, maintenant,
      lire: async () => 403 });

    const envoi = envois.find((e) => e.nom === 'PutObjectCommand' && e.input.Key.endsWith('.dump.enc'));
    expect(envoi?.input.Key).toBe('prod/pronowin_2026-09-25_0230.dump.enc');
    expect(String(envoi?.input.Body)).toBe('chiffré:contenu de la base');
    expect(fs.existsSync(`${dump}.enc`)).toBe(false);                        // pas de reste sur disque
    expect(r).toMatchObject({ distante: maintenant.toISOString(), envoyes: ['pronowin_2026-09-25_0230.dump.enc'] });
  });

  it(`au-delà de ${RETENTION_JOURS} jours, les copies distantes sont retirées`, async () => {
    const jours = (n: number) => new Date(maintenant.getTime() - n * 86400000);
    const { s3, envois } = faux([
      { Key: 'prod/ancien.dump.enc', LastModified: jours(RETENTION_JOURS + 1) },
      { Key: 'prod/recent.dump.enc', LastModified: jours(2) },
    ]);
    const r = await copier({ config, fichiers: [dump], s3, cmd, chiffrerFichier, maintenant, lire: async () => 403 });

    const retires = envois.filter((e) => e.nom === 'DeleteObjectCommand').map((e) => e.input.Key);
    expect(retires).toContain('prod/ancien.dump.enc');
    expect(retires).not.toContain('prod/recent.dump.enc');
    expect(r.supprimes).toBe(1);
  });

  it('un chiffrement sans résultat n\'envoie pas le fichier', async () => {
    const { s3, envois } = faux();
    await expect(copier({ config, fichiers: [dump], s3, cmd, maintenant, lire: async () => 403,
      chiffrerFichier: () => { /* rien d'écrit */ } })).rejects.toThrow(/sans résultat/);
    expect(envois.some((e) => e.nom === 'PutObjectCommand' && e.input.Key.endsWith('.enc'))).toBe(false);
  });
});
