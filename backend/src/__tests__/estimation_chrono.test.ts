/**
 * Début estimé des mi-temps quand API-Football ne le date pas (chrono à la
 * seconde, 17 octobre 2026 : `periods` vide sur les trois matchs en direct).
 */
import { MatchInfoService } from '../services/match_info.service';
import { debutEstime, observerRencontre, precisionEstimation, _oublierEstimations } from '../services/estimation_chrono';
import { _reinitialiser } from '../services/etat_taches';

const T = Date.UTC(2026, 9, 17, 15, 0, 0);
const min = 60_000;
const rencontre = (phase: string, elapsed: number, extra: number | null = null, periods: any = { first: null, second: null }) => ({
  fixture: { id: 7, status: { short: phase, elapsed, extra }, periods, referee: null, venue: {} },
  teams: { home: { id: 1, name: 'Villarreal' }, away: { id: 2, name: 'Elche' } },
  league: { round: 'J9', season: 2026 }, score: {},
});

beforeEach(() => _oublierEstimations());
afterEach(() => { _reinitialiser(); jest.useRealTimers(); });

describe('estimation du début de la mi-temps', () => {
  it('un relevé : début situé à la minute près, milieu servi', () => {
    // « 39 » = minute en cours, de 38:00 à 38:59.
    observerRencontre(rencontre('1H', 39), T);
    expect(precisionEstimation(7, 1)).toBe(60);
    expect(debutEstime(7, 1)).toBe(Math.round((T - 38.5 * min) / 1000));
  });

  it('les relevés suivants resserrent l\'intervalle', () => {
    observerRencontre(rencontre('1H', 39), T);
    observerRencontre(rencontre('1H', 40), T + 30_000);
    // (T−39, T−38] ∩ (T+30 s−40, T+30 s−39] = (T−39, T−38:30]
    expect(precisionEstimation(7, 1)).toBe(30);
    expect(debutEstime(7, 1)).toBe(Math.round((T - 38.75 * min) / 1000));
  });

  it('seconde mi-temps : minutes comptées à partir de 45', () => {
    observerRencontre(rencontre('2H', 67), T);
    // 67 = de 66:00 à 66:59, soit 21 à 22 minutes après la reprise.
    expect(debutEstime(7, 2)).toBe(Math.round((T - 21.5 * min) / 1000));
    expect(debutEstime(7, 1)).toBeNull();
  });

  it('temps additionnel, pauses, données invalides : aucune contrainte', () => {
    for (const r of [rencontre('1H', 45), rencontre('2H', 90), rencontre('2H', 80, 3),
                     rencontre('HT', 45), rencontre('ET', 105), rencontre('2H', 45)]) {
      observerRencontre(r, T);
    }
    observerRencontre({ fixture: { id: 'x', status: { short: '1H', elapsed: 10 } } }, T);
    observerRencontre(null, T);
    expect([debutEstime(7, 1), debutEstime(7, 2)]).toEqual([null, null]);
  });

  it('minute corrigée par la source : le relevé récent fait foi', () => {
    observerRencontre(rencontre('1H', 39), T);
    observerRencontre(rencontre('1H', 30), T + 30_000);
    expect(debutEstime(7, 1)).toBe(Math.round((T + 30_000 - 29.5 * min) / 1000));
  });
});

describe('informations de match', () => {
  it('servent l\'estimation quand la source ne date pas les mi-temps, et le disent', async () => {
    jest.useFakeTimers(); jest.setSystemTime(T);
    const get = jest.fn(async () => ({ data: { errors: [], response: [rencontre('2H', 67)] } }));
    const info = await new MatchInfoService({ get } as any, () => true).get(7, 'LIVE', new Date(T - 80 * min));
    expect(info).toMatchObject({ phase: '2H', periods: { first: null, second: Math.round((T - 21.5 * min) / 1000) }, periods_estimes: true });
  });

  it('préfèrent les débuts publiés par la source', async () => {
    jest.useFakeTimers(); jest.setSystemTime(T);
    const periods = { first: 1792249230, second: 1792252830 };
    const get = jest.fn(async () => ({ data: { errors: [], response: [rencontre('2H', 67, null, periods)] } }));
    const info = await new MatchInfoService({ get } as any, () => true).get(7, 'LIVE', new Date(T - 80 * min));
    expect(info).toMatchObject({ periods, periods_estimes: false });
  });
});
