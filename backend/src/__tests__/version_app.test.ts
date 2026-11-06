/**
 * La version de l'application de chaque membre.
 *
 * Le serveur l'ignorait : relever la version minimale se faisait à l'aveugle,
 * au risque de bloquer d'un coup ceux qui n'avaient pas fait la mise à jour.
 */
jest.mock('../lib/prisma', () => ({
  prisma: { versionAppCompte: { upsert: jest.fn() } },
}));

import {
  lireVersionApp, noterVersionApp, analyserVersions, familleDistribution, _oublierVersions,
  type MembreActif, type VersionVue,
} from '../services/version_app.service';

const { prisma } = require('../lib/prisma');
const upsert = prisma.versionAppCompte.upsert as jest.Mock;

const entetes = (version: string, p: Record<string, string> = {}) => ({
  'x-app-version': version, 'x-app-build': '34', 'x-app-plateforme': 'android', 'x-app-canal': 'direct', ...p,
});

beforeEach(() => {
  _oublierVersions();
  upsert.mockReset().mockResolvedValue({});
});

describe('lecture des en-têtes', () => {
  it('version, build, plateforme, canal', () => {
    expect(lireVersionApp(entetes('1.0.18'))).toEqual(
      { version: '1.0.18', build: 34, plateforme: 'android', canal: 'direct' });
  });

  it('une version absente ou mal formée n\'est rien', () => {
    expect(lireVersionApp({})).toBeNull();
    expect(lireVersionApp(entetes('1.0.18; DROP TABLE'))).toBeNull();
    expect(lireVersionApp(entetes('v2'))).toBeNull();
  });

  it('une valeur inattendue ne passe pas telle quelle', () => {
    expect(lireVersionApp(entetes('1.0.18', { 'x-app-plateforme': 'windows-phone', 'x-app-canal': 'pirate',
                                               'x-app-build': 'abc' })))
      .toEqual({ version: '1.0.18', build: null, plateforme: 'autre', canal: null });
  });
});

describe('enregistrement', () => {
  it('une écriture, puis plus rien tant que rien ne change', () => {
    noterVersionApp('u1', entetes('1.0.18'));
    noterVersionApp('u1', entetes('1.0.18'));
    noterVersionApp('u1', entetes('1.0.18'));
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert.mock.calls[0][0]).toMatchObject({ where: { userId: 'u1' }, update: { version: '1.0.18', canal: 'direct' } });
  });

  it('une mise à jour s\'écrit aussitôt', () => {
    noterVersionApp('u1', entetes('1.0.18'));
    noterVersionApp('u1', entetes('1.0.19'));
    expect(upsert).toHaveBeenCalledTimes(2);
  });

  it('une application qui ne déclare rien ne laisse aucune trace', () => {
    noterVersionApp('u1', {});
    expect(upsert).not.toHaveBeenCalled();
  });

  it('une base en panne : l\'écriture sera retentée à la requête suivante', async () => {
    upsert.mockRejectedValueOnce(new Error('base injoignable'));
    noterVersionApp('u1', entetes('1.0.18'));
    await new Promise((r) => setImmediate(r));
    noterVersionApp('u1', entetes('1.0.18'));
    expect(upsert).toHaveBeenCalledTimes(2);
  });
});

describe('analyse pour le panneau', () => {
  const vu = new Date('2026-10-05T10:00:00Z');
  const membre = (id: string, premium = false): MembreActif => ({ id, pseudo: id, premium, vuLe: vu });
  const version = (userId: string, v: string, plateforme: string, canal: string | null): VersionVue =>
    ({ userId, version: v, build: null, plateforme, canal, vuLe: vu });

  const membres = [
    membre('a'), membre('b', true), membre('c'), membre('d', true), membre('e'), membre('f', true),
  ];
  const versions = [
    version('a', '1.0.19', 'android', 'direct'),
    version('b', '1.0.18', 'android', 'direct'),   // en retard sur l'APK
    version('c', '1.0.18', 'ios', 'store'),         // à jour : la plus haute vue sur iOS
    version('d', '1.0.18', 'android', 'store'),
    // e : rien déclaré → 1.0.17 ou antérieure.
    version('f', '1.0.18', 'android', 'store'),
  ];
  const r = analyserVersions(membres, versions, { store: '1.0.0', apk: '1.0.18' });

  it('la référence : la plus haute entre la configuration et ce qui est utilisé', () => {
    expect(r.references).toEqual({ ios: '1.0.18', play: '1.0.18', apk: '1.0.19' });
  });

  it('à jour, en retard, et ceux qui ne déclarent rien', () => {
    expect(r).toMatchObject({ actifs: 6, aJour: 4, enRetard: 1, enRetardPremium: 1, inconnus: 1, inconnusPremium: 0 });
    expect(r.listeEnRetard).toEqual([expect.objectContaining({ userId: 'b', premium: true, version: '1.0.18', famille: 'apk' })]);
  });

  it('répartition par version et canal, la plus récente en tête', () => {
    expect(r.versions.map((v) => [v.version, v.famille, v.membres])).toEqual([
      ['1.0.19', 'apk', 1], ['1.0.18', 'play', 2], ['1.0.18', 'apk', 1], ['1.0.18', 'ios', 1],
    ]);
    expect(r.versions[0].part).toBe(16.7);
  });

  it('les familles de distribution', () => {
    expect(familleDistribution('ios', null)).toBe('ios');
    expect(familleDistribution('android', 'direct')).toBe('apk');
    expect(familleDistribution('android', null)).toBe('play');
    expect(familleDistribution('web', null)).toBe('autre');
  });
});
