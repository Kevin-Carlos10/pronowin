/**
 * La consommation du quota d'API-Football, comptée appel par appel.
 *
 * Le panneau ne voyait que le dernier « restant » relevé : ni ce qui l'avait
 * consommé, ni la tendance des jours passés.
 */
jest.mock('../lib/prisma', () => ({ prisma: { $executeRaw: jest.fn() } }));

import {
  familleDe, compterAppel, verserCompteurs, analyserConsommation, jourUtc,
  _reinitialiserConsommation, type LigneConso, type LigneQuota,
} from '../services/consommation_football.service';
import { exigenceDe } from '../utils/permissions_admin';

const { prisma } = require('../lib/prisma');
const executer = prisma.$executeRaw as jest.Mock;

/** Les valeurs passées à chaque requête SQL, sans le texte. */
const valeurs = () => executer.mock.calls.map(([, ...v]) => v);

beforeEach(() => {
  _reinitialiserConsommation();
  executer.mockReset().mockResolvedValue(1);
});

describe('famille d\'un appel', () => {
  it('le chemin, et pour /fixtures l\'usage qui en fait le coût', () => {
    expect(familleDe('/odds', { fixture: 1 })).toBe('/odds');
    expect(familleDe('/fixtures', { live: 'all' })).toBe('/fixtures?live');
    expect(familleDe('/fixtures?id=123')).toBe('/fixtures?id');
    expect(familleDe('/fixtures', { date: '2026-10-05' })).toBe('/fixtures?date');
    expect(familleDe('/fixtures', { team: 50, last: 5 })).toBe('/fixtures');
    expect(familleDe('https://v3.football.api-sports.io/players/topscorers/')).toBe('/players/topscorers');
  });

  it('rien qui puisse casser la clé de comptage', () => {
    expect(familleDe('/odds|live')).toBe('/oddslive');
    expect(familleDe(undefined)).toBe('/');
  });
});

describe('comptage et versement', () => {
  it('additionne en mémoire, verse en une ligne par famille', async () => {
    compterAppel({ url: '/fixtures', params: { live: 'all' } });
    compterAppel({ url: '/fixtures', params: { live: 'all' } });
    compterAppel({ url: '/odds' }, { echec: true });
    await verserCompteurs();

    const jour = jourUtc();
    expect(valeurs()).toEqual(expect.arrayContaining([
      [jour, '/fixtures?live', 2, 0],
      [jour, '/odds', 1, 1],
    ]));
  });

  it('garde la plus petite valeur restante du jour', async () => {
    compterAppel({ url: '/odds' }, { entetes: { 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '7000' } });
    compterAppel({ url: '/odds' }, { entetes: { 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '6990' } });
    compterAppel({ url: '/odds' }, { entetes: { 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '6995' } });
    await verserCompteurs();
    expect(valeurs()).toEqual(expect.arrayContaining([[jourUtc(), 7500, 6990, expect.any(Date)]]));
  });

  it('une base en panne : rien n\'est perdu, rien n\'est compté deux fois', async () => {
    compterAppel({ url: '/odds' });
    compterAppel({ url: '/standings' });
    // La première ligne passe, la seconde échoue.
    executer.mockResolvedValueOnce(1).mockRejectedValueOnce(new Error('base injoignable'));
    await verserCompteurs();

    executer.mockReset().mockResolvedValue(1);
    await verserCompteurs();
    const familles = valeurs().filter((v) => typeof v[1] === 'string' && v[1].startsWith('/')).map((v) => v[1]);
    // Seule la ligne qui avait échoué est versée au second passage.
    expect(familles).toHaveLength(1);
  });

  it('le comptage ne lève jamais', () => {
    expect(() => compterAppel(null)).not.toThrow();
    expect(() => compterAppel({ url: 42 as any }, { entetes: { 'x-ratelimit-requests-limit': 'n/a' } })).not.toThrow();
  });
});

describe('lecture pour le panneau', () => {
  const MAINTENANT = new Date('2026-10-05T12:00:00Z');   // la moitié du jour UTC
  const lignes: LigneConso[] = [
    { jour: '2026-10-05', famille: '/fixtures?live', appels: 1500, echecs: 2 },
    { jour: '2026-10-05', famille: '/odds',          appels: 500,  echecs: 0 },
    { jour: '2026-10-04', famille: '/fixtures?live', appels: 3000, echecs: 0 },
    { jour: '2026-10-03', famille: '/fixtures?live', appels: 2800, echecs: 0 },
  ];
  const quotas: LigneQuota[] = [
    { jour: '2026-10-05', limite: 7500, restantMin: 5300, releveLe: MAINTENANT },
    { jour: '2026-10-04', limite: 7500, restantMin: 4300, releveLe: MAINTENANT },
  ];
  const r = analyserConsommation(lignes, quotas, MAINTENANT);

  it('aujourd\'hui : le décompte du fournisseur, le nôtre, et l\'écart', () => {
    expect(r.aujourdhui).toMatchObject({
      serveur: 2000, echecs: 2, fournisseur: 2200, limite: 7500, restant: 5300, horsServeur: 200,
      remiseAZero: '2026-10-06T00:00:00.000Z',
    });
  });

  it('la projection prolonge le rythme jusqu\'à minuit UTC', () => {
    expect(r.aujourdhui.projection).toBe(4400);   // 2 200 en une demi-journée
    const tot = analyserConsommation(lignes, quotas, new Date('2026-10-05T00:20:00Z'));
    expect(tot.aujourdhui.projection).toBeNull();  // moins d'une heure : trop tôt
  });

  it('trente jours, les jours sans mesure signalés comme tels', () => {
    expect(r.jours).toHaveLength(30);
    expect(r.jours[29]).toMatchObject({ jour: '2026-10-05', serveur: 2000, fournisseur: 2200 });
    expect(r.jours[28]).toMatchObject({ jour: '2026-10-04', serveur: 3000, fournisseur: 3200, mesure: true });
    expect(r.jours[27]).toMatchObject({ jour: '2026-10-03', fournisseur: null, mesure: true });
    expect(r.jours[0].mesure).toBe(false);
    // Moyenne des jours mesurés avant aujourd'hui : (3 200 + 2 800) / 2.
    expect(r.moyenne7j).toBe(3000);
  });

  it('ce qui consomme, du plus gros au plus petit', () => {
    expect(r.familles.aujourdhui).toEqual([
      { famille: '/fixtures?live', appels: 1500, echecs: 2, part: 75 },
      { famille: '/odds', appels: 500, echecs: 0, part: 25 },
    ]);
    expect(r.familles.septJours[0]).toMatchObject({ famille: '/fixtures?live', appels: 7300 });
  });
});

it('réservé à l\'administrateur principal', () => {
  expect(exigenceDe('GET', '/admin/stats/football')).toEqual({ acces: 'principal' });
  // Les autres statistiques restent à la section.
  expect(exigenceDe('GET', '/admin/stats/canaux')).toMatchObject({ acces: 'section', sections: ['statistiques'] });
});
