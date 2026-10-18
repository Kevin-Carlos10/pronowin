/**
 * Synchronisation des scores économe en quota (18 octobre 2026).
 *
 * Avant : toutes les 30 s, deux téléchargements complets (hier + aujourd'hui)
 * — 5 449 appels le 17 octobre, 72 % du quota, épuisé ce jour-là. Désormais :
 * le direct en un appel (`live=all`), le relevé complet toutes les 5 minutes,
 * ou tout de suite (une fois par minute au plus) quand un match quitte le
 * direct.
 */
import { ApiFootballService, _oublierReleves } from '../services/api_football.service';

const T0 = Date.UTC(2026, 9, 18, 15, 0, 0);
const rencontre = (id: number, statut: string) => ({
  fixture: { id, date: '2026-10-18T14:00:00+00:00', status: { short: statut, elapsed: statut === 'FT' ? 90 : 30 } },
  league: { id: 39, name: 'Premier League', logo: null },
  teams: { home: { id: 1, name: 'A', logo: null }, away: { id: 2, name: 'B', logo: null } },
  goals: { home: 1, away: 0 },
});
const reponse = (r: any[]) => ({ data: { errors: [], response: r } });

function service(direct: () => any) {
  const get = jest.fn(async (_url: string, cfg: any) => {
    if (cfg?.params?.live === 'all') return direct();
    // Relevé par date : un match terminé, un à venir (écarté).
    return reponse([rencontre(2, 'FT'), rencontre(3, 'NS')]);
  });
  const svc = new ApiFootballService();
  (svc as any).client = { get };
  (svc as any)._hasKey = () => true;
  const appels = () => ({
    direct: get.mock.calls.filter(c => c[1]?.params?.live === 'all').length,
    parDate: get.mock.calls.filter(c => c[1]?.params?.date).length,
  });
  return { svc, get, appels };
}

beforeEach(() => { _oublierReleves(); jest.useFakeTimers(); jest.setSystemTime(T0); });
afterEach(() => jest.useRealTimers());

it('premier relevé : le direct et le relevé complet, fusionnés (le direct l\'emporte)', async () => {
  const { svc, appels } = service(() => reponse([rencontre(1, '2H')]));
  const r = await svc.getAllLiveAndRecentFixtures();
  expect(appels()).toEqual({ direct: 1, parDate: 2 });
  expect(r.map(f => [f.fixture.id, f.fixture.status.short]).sort()).toEqual([[1, '2H'], [2, 'FT']]);
});

it('cycles suivants : le direct seul, un appel ; le relevé complet revient toutes les 5 minutes', async () => {
  const { svc, appels } = service(() => reponse([rencontre(1, '2H')]));
  await svc.getAllLiveAndRecentFixtures();
  for (let i = 1; i <= 9; i++) {          // neuf cycles de 30 s : 4 min 30
    jest.setSystemTime(T0 + i * 30_000);
    expect((await svc.getAllLiveAndRecentFixtures()).map(f => f.fixture.id)).toEqual([1]);
  }
  expect(appels()).toEqual({ direct: 10, parDate: 2 });
  jest.setSystemTime(T0 + 5 * 60_000);
  await svc.getAllLiveAndRecentFixtures();
  expect(appels()).toEqual({ direct: 11, parDate: 4 });
});

it('un match quitte le direct : relevé complet anticipé, une fois par minute au plus', async () => {
  const { svc, appels } = service(() => reponse([]));
  await svc.getAllLiveAndRecentFixtures();                   // T0 : complet
  jest.setSystemTime(T0 + 30_000);
  await svc.getAllLiveAndRecentFixtures({ anticiper: true }); // < 1 min : pas encore
  expect(appels().parDate).toBe(2);
  jest.setSystemTime(T0 + 60_000);
  const r = await svc.getAllLiveAndRecentFixtures({ anticiper: true });
  expect(appels().parDate).toBe(4);
  // Le match terminé est relevé : son résultat sera réglé.
  expect(r.map(f => f.fixture.id)).toEqual([2]);
});

it('le direct échoue : relevé complet aussitôt, comme avant', async () => {
  const { svc, appels } = service(() => ({ data: { errors: { requests: 'limit' }, response: [] } }));
  await svc.getAllLiveAndRecentFixtures();
  jest.setSystemTime(T0 + 30_000);
  const r = await svc.getAllLiveAndRecentFixtures();
  expect(appels().parDate).toBe(4);
  expect(r.map(f => f.fixture.id)).toEqual([2]);
});

it('le direct est partagé : deux lectures dans le même cycle font un seul appel', async () => {
  const { svc, appels } = service(() => reponse([rencontre(1, '1H')]));
  await svc.getLiveFixtures();
  await svc.getLiveFixtures();
  expect(appels().direct).toBe(1);
});

describe('synchroniseur des scores', () => {
  // Chargés ici : le service des pronostics tire la base, simulée ci-dessous.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { PronosticsService } = require('../services/pronostics.service');

  afterEach(() => jest.restoreAllMocks());

  async function synchroniser(enDirectChezLeFournisseur: number[], enDirectEnBase: number[]) {
    jest.spyOn(prisma.match, 'findMany').mockImplementation(async (args: any) =>
      args?.where?.status === 'LIVE' && args?.where?.matchDate === undefined
        ? enDirectEnBase.map(externalId => ({ externalId }))
        : []);
    jest.spyOn(apiFootballService, 'getLiveFixtures')
      .mockResolvedValue(enDirectChezLeFournisseur.map(id => rencontre(id, '2H')));
    const releve = jest.spyOn(apiFootballService, 'getAllLiveAndRecentFixtures').mockResolvedValue([]);
    await new PronosticsService().syncMatchScores();
    return releve.mock.calls[0][0];
  }

  it('un match en direct en base a quitté le direct : relevé complet anticipé', async () => {
    expect(await synchroniser([7], [7, 8])).toEqual({ anticiper: true });
  });

  it('tous les matchs en direct en base y sont encore : le direct suffit', async () => {
    expect(await synchroniser([7, 8, 9], [7, 8])).toEqual({ anticiper: false });
  });
});
