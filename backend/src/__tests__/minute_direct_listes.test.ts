/**
 * La minute de jeu dans la liste de tous les matchs (8 novembre 2026).
 *
 * L'application n'affichait que « En direct » là où Sofascore donne « 67' » :
 * la liste ne transmettait pas `elapsedMinutes`, que la synchronisation des
 * scores tient pourtant à jour.
 */
jest.mock('../lib/prisma', () => {
  const mockMatchFindMany  = jest.fn().mockResolvedValue([]);
  return {
    prisma: {
      pronostic:        { findMany: jest.fn() },
      match:            { findMany: mockMatchFindMany },
      user:             { findUnique: jest.fn().mockResolvedValue(null) },
      leagueVisibility: { findMany: jest.fn().mockResolvedValue([]) },
    },
    _mocks: { mockMatchFindMany },
  };
});

import { PronosticsService } from '../services/pronostics.service';
const { _mocks } = require('../lib/prisma');

const match = (status: string, elapsedMinutes: number | null) => ({
  id: `m-${status}`, league: 'La Liga', leagueCode: 'ES1',
  homeTeam: 'Real Sociedad', awayTeam: 'Rayo Vallecano', homeTeamLogo: null, awayTeamLogo: null,
  matchDate: new Date('2026-11-08T15:15:00Z'), status, elapsedMinutes,
  homeScore: 1, awayScore: 0, homeFormPoints: 7, awayFormPoints: 5,
  pronostic: null,
});

describe('minute de jeu dans la liste des matchs', () => {
  it('en direct : la minute ; sinon rien, même si la base en garde une', async () => {
    _mocks.mockMatchFindMany.mockResolvedValue([match('LIVE', 67), match('FINISHED', 90)]);
    const { data } = await new PronosticsService().getAllMatches({ limit: 20 });
    expect(data.map((m: any) => [m.status, m.elapsed])).toEqual([['live', 67], ['finished', null]]);
  });
});
