import { EvolutionClassementFootball, numeroJournee, reconstituer } from '../services/evolution_classement.service';
import { _reinitialiser } from '../services/etat_taches';

const ok = (response: any) => ({ data: { errors: [], response } });
const f = (j: number | string, dom: number, ext: number, gh: number | null, ga: number | null, statut = 'FT') => ({
  fixture: { id: Math.random(), status: { short: statut } },
  league: { id: 78, season: 2026, round: typeof j === 'number' ? `Regular Season - ${j}` : j },
  teams: { home: { id: dom, name: 'T' + dom }, away: { id: ext, name: 'T' + ext } },
  goals: { home: gh, away: ga },
});

beforeEach(() => _reinitialiser());

describe('évolution au classement (7 novembre 2026)', () => {
  it('lit le numéro de journée ; une coupe n’en a pas', () => {
    expect(numeroJournee('Regular Season - 12')).toBe(12);
    expect(numeroJournee('Round of 16')).toBeNull();
    expect(numeroJournee(undefined)).toBeNull();
  });

  it('positions après chaque journée : points, puis différence, puis buts', () => {
    const saison = [
      f(1, 1, 2, 2, 0), f(1, 3, 4, 1, 1),           // J1 : 1 gagne, 3-4 nul
      f(2, 2, 3, 3, 0), f(2, 4, 1, 1, 0),           // J2 : 2 et 4 gagnent
      f(3, 1, 3, null, null, 'NS'), f(3, 2, 4, 0, 0), // J3 : un match à jouer
    ];
    const r = reconstituer(saison, 1, 2)!;
    expect(r.equipes).toBe(4);
    // Après J1 : 1 (3 pts), 3 et 4 (1 pt, 0 diff, 1 bp → nom), 2 (0).
    // Après J2 : 4 (4 pts), 1 (3, +1), 2 (3, +1, 3 bp > 2 bp de 1 → 2 devant), 3 (1).
    expect(r.journees).toEqual([
      { journee: 1, domicile: 1, exterieur: 4 },
      { journee: 2, domicile: 3, exterieur: 2 },
      { journee: 3, domicile: 3, exterieur: 2 },
    ]);
  });

  it('une équipe absente de la saison, ou une coupe : rien', () => {
    expect(reconstituer([f(1, 1, 2, 1, 0)], 1, 99)).toBeNull();
    expect(reconstituer([f('Final', 1, 2, 1, 0)], 1, 2)).toBeNull();
  });

  it('une requête pour la saison, gardée en cache ; match de coupe : null sans requête', async () => {
    const c = { get: jest.fn(async () => ok([f(1, 1, 2, 1, 0), f(1, 3, 4, 0, 0)])) };
    const match = { league: { id: 78, season: 2026, round: 'Regular Season - 10' },
      teams: { home: { id: 1 }, away: { id: 2 } } };
    const svc = new EvolutionClassementFootball(c as any, async () => match);
    expect(await svc.get(42)).toEqual({ saison: 2026, equipes: 4,
      journees: [{ journee: 1, domicile: 1, exterieur: 4 }] });
    await svc.get(42);
    expect(c.get).toHaveBeenCalledTimes(1);
    expect(c.get).toHaveBeenCalledWith('/fixtures', { params: { league: 78, season: 2026 } });

    const coupe = new EvolutionClassementFootball(c as any, async () => ({ ...match, league: { ...match.league, round: 'Round of 16' } }));
    expect(await coupe.get(43)).toBeNull();
    expect(c.get).toHaveBeenCalledTimes(1);
  });
});
