/**
 * Relevé par date gardé 30 minutes pour un jour calme (18 octobre 2026).
 *
 * La liste des matchs relisait les 7 prochains jours à chaque ouverture avec
 * la fraîcheur d'un direct (25 s) : la moitié des appels « par date » de la
 * matinée. Un jour où rien ne se joue avant 3 heures est désormais gardé
 * 30 minutes ; aujourd'hui, en pratique, reste à 25 s.
 */
import { ApiFootballService, dureeReleveParDate, _oublierReleves } from '../services/api_football.service';

const T0 = Date.UTC(2026, 9, 18, 9, 0, 0);
const heure = 3600_000;
const rencontre = (id: number, statut: string, debut: number) => ({
  fixture: { id, date: new Date(debut).toISOString(), status: { short: statut, elapsed: null } },
  league: { id: 39, name: 'Premier League', logo: null },
  teams: { home: { id: 1, name: 'A', logo: null }, away: { id: 2, name: 'B', logo: null } },
  goals: { home: null, away: null },
});

describe('durée de vie du relevé d\'un jour', () => {
  it('rien avant 3 heures : 30 minutes', () => {
    expect(dureeReleveParDate([rencontre(1, 'NS', T0 + 5 * heure), rencontre(2, 'NS', T0 + 30 * heure)], T0)).toBe(30 * 60_000);
  });
  it('un coup d\'envoi dans moins de 3 heures : 25 s', () => {
    expect(dureeReleveParDate([rencontre(1, 'NS', T0 + 2 * heure), rencontre(2, 'NS', T0 + 9 * heure)], T0)).toBe(25_000);
  });
  it('un match en cours, ou à la mi-temps : 25 s', () => {
    expect(dureeReleveParDate([rencontre(1, '2H', T0 - heure)], T0)).toBe(25_000);
    expect(dureeReleveParDate([rencontre(1, 'HT', T0 - heure)], T0)).toBe(25_000);
  });
  it('un match « à venir » dont l\'heure est passée (retard) : 25 s', () => {
    expect(dureeReleveParDate([rencontre(1, 'NS', T0 - 10 * 60_000)], T0)).toBe(25_000);
  });
  it('tout est terminé, ou rien au programme : 30 minutes', () => {
    expect(dureeReleveParDate([rencontre(1, 'FT', T0 - 3 * heure), rencontre(2, 'PST', T0 + heure)], T0)).toBe(30 * 60_000);
    expect(dureeReleveParDate([], T0)).toBe(30 * 60_000);
  });
});

describe('la liste des matchs à venir', () => {
  beforeEach(() => { _oublierReleves(); jest.useFakeTimers(); jest.setSystemTime(T0); });
  afterEach(() => jest.useRealTimers());

  it('aujourd\'hui relu après 25 s, les six jours suivants après 30 minutes seulement', async () => {
    const aujourdhui = new Date(T0).toISOString().slice(0, 10);
    const get = jest.fn(async (_url: string, cfg: any) => {
      const date = cfg.params.date as string;
      const r = date === aujourdhui
        ? [rencontre(1, 'NS', T0 + heure)]                       // coup d'envoi dans 1 h
        : [rencontre(2, 'NS', Date.parse(`${date}T15:00:00Z`))];  // dans plus d'un jour
      return { data: { errors: [], response: r } };
    });
    const svc = new ApiFootballService();
    (svc as any).client = { get };
    (svc as any)._hasKey = () => true;
    const appelsDu = (jour: 'aujourdhui' | 'suivants') => get.mock.calls
      .filter(c => (c[1].params.date === aujourdhui) === (jour === 'aujourdhui')).length;

    await svc.getAllUpcomingFixtures();
    expect([appelsDu('aujourdhui'), appelsDu('suivants')]).toEqual([1, 6]);
    jest.setSystemTime(T0 + 60_000);                // une minute plus tard
    await svc.getAllUpcomingFixtures();
    expect([appelsDu('aujourdhui'), appelsDu('suivants')]).toEqual([2, 6]);
    jest.setSystemTime(T0 + 31 * 60_000);           // au-delà de 30 minutes
    const r = await svc.getAllUpcomingFixtures();
    expect([appelsDu('aujourdhui'), appelsDu('suivants')]).toEqual([3, 12]);
    expect(r).toHaveLength(7);
  });
});
