import { FormeRecenteFootball, matchRecent } from '../services/forme_recente.service';
import { ClassementsFootball } from '../services/classements_football.service';
import { _reinitialiser } from '../services/etat_taches';

const ok = (response: any) => ({ data: { errors: [], response } });
const fixture = { fixture: { id: 42 }, league: { id: 39, season: 2026 },
  teams: { home: { id: 3, name: 'Home' }, away: { id: 4, name: 'Away' } } };
const joue = (id: number, ts: number, statut: string, home: number, away: number, gh: number | null, ga: number | null,
  vainqueur: 'home' | 'away' | null = gh == null || ga == null || gh === ga ? null : gh > ga ? 'home' : 'away') => ({
  fixture: { id, timestamp: ts, date: new Date(ts * 1000).toISOString(), status: { short: statut } },
  league: { name: 'Premier League' },
  teams: { home: { id: home, name: 'T' + home, logo: 'l' + home, winner: vainqueur === 'home' ? true : vainqueur === 'away' ? false : null },
           away: { id: away, name: 'T' + away, logo: 'l' + away, winner: vainqueur === 'away' ? true : vainqueur === 'home' ? false : null } },
  goals: { home: gh, away: ga },
});
beforeEach(() => _reinitialiser());

it('un match vu de chaque côté : domicile, adversaire, buts pour et contre', () => {
  const m = joue(1, 100, 'FT', 3, 7, 2, 1);
  expect(matchRecent(m, 3)).toMatchObject({ domicile: true, adversaire: 'T7', butsPour: 2, butsContre: 1, issue: 'V' });
  expect(matchRecent(m, 7)).toMatchObject({ domicile: false, adversaire: 'T3', adversaireLogo: 'l3', butsPour: 1, butsContre: 2, issue: 'D' });
  expect(matchRecent(m, 99)).toBeNull();
});

it('aux tirs au but, le vainqueur désigné compte, pas le score', () => {
  const m = joue(1, 100, 'PEN', 3, 7, 1, 1, 'away');
  expect(matchRecent(m, 7)?.issue).toBe('V');
  expect(matchRecent(m, 3)?.issue).toBe('D');
  expect(matchRecent(joue(2, 100, 'FT', 3, 7, 0, 0), 3)?.issue).toBe('N');
});

it('cinq derniers terminés, du plus récent au plus ancien, sans le match lui-même', async () => {
  const domicile = [
    joue(42, 900, 'FT', 3, 4, 1, 0),        // le match de la fiche : écarté
    joue(10, 800, 'PST', 3, 8, null, null), // reporté : écarté
    ...[1, 2, 3, 4, 5, 6].map(i => joue(100 + i, i * 100, 'FT', 3, 20 + i, i % 3, 1)),
  ];
  const c = { get: jest.fn(async (_p: string, { params }: any) => ok(params.team === 3 ? domicile : [joue(200, 50, 'AET', 9, 4, 2, 3)])) };
  const forme = await new FormeRecenteFootball(c as any, async () => fixture).get(42);
  expect(c.get).toHaveBeenCalledWith('/fixtures', { params: { team: 3, last: 10 } });
  expect(forme?.home.map(m => m.adversaire)).toEqual(['T26', 'T25', 'T24', 'T23', 'T22']);
  expect(forme?.home.map(m => m.issue)).toEqual(['D', 'V', 'N', 'D', 'V']);
  expect(forme?.away).toEqual([expect.objectContaining({ adversaire: 'T9', domicile: false, issue: 'V' })]);

  // Mis en cache : la fiche rouverte ne coûte aucune requête.
  await new FormeRecenteFootball(c as any, async () => fixture).get(42);
  expect(c.get).toHaveBeenCalledTimes(2);
});

it('match inconnu ou fournisseur en panne : null, que la fiche masque', async () => {
  const c = { get: jest.fn(async () => { throw Error('offline'); }) };
  expect(await new FormeRecenteFootball(c as any, async () => null).get(42)).toBeNull();
  expect(c.get).not.toHaveBeenCalled();
  expect(await new FormeRecenteFootball(c as any, async () => fixture).get(42)).toBeNull();
});

it('classement : bilans à domicile et à l’extérieur, points recomptés', async () => {
  const ligne = { rank: 1, team: { id: 3, name: 'Home' }, group: 'Premier League', points: 13, goalsDiff: 5,
    all: { played: 6, win: 4, draw: 1, lose: 1, goals: { for: 11, against: 6 } },
    home: { played: 3, win: 3, draw: 0, lose: 0, goals: { for: 7, against: 1 } },
    away: { played: 3, win: 1, draw: 1, lose: 1, goals: { for: 4, against: 5 } } };
  const seasons = [{ year: 2026, start: '2026-08-01', end: '2027-05-31', coverage: { standings: true } }];
  const c = { get: jest.fn(async (path: string) => ok(path === '/leagues'
    ? [{ league: { id: 39 }, seasons }]
    : [{ league: { id: 39, season: 2026, standings: [[ligne]] } }])) };
  const r = await new ClassementsFootball(c as any, async () => fixture).get({ fixtureId: 42, matchDate: new Date('2026-10-08') });
  expect(r.rows[0]).toMatchObject({
    goalsFor: 11, goalsAgainst: 6,
    home: { played: 3, win: 3, draw: 0, lose: 0, goalsFor: 7, goalsAgainst: 1, points: 9 },
    away: { played: 3, win: 1, draw: 1, lose: 1, goalsFor: 4, goalsAgainst: 5, points: 4 },
  });
});
