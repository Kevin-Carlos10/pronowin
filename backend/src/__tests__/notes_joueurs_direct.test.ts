/**
 * Compositions au style Sofascore (17 octobre 2026) : notes des joueurs en
 * direct aussi, avec cartons et entrée en jeu, et identifiants des joueurs
 * dans les événements.
 */
import { ApiFootballInsights } from '../services/api_football_insights.service';
import { MatchLiveService } from '../services/match_live.service';
import { _reinitialiser } from '../services/etat_taches';

const reply = (response: any[]) => ({ data: { response, errors: [] } });
afterEach(() => _reinitialiser());

it('notes : cartons, remplaçant et capitaine transmis ; joueur sans note écarté', async () => {
  const joueurs = [
    { team: { id: 1 }, players: [
      { player: { id: 10, name: 'J. Foyth', photo: 'p10' },
        statistics: [{ games: { rating: '7.2', minutes: 90, substitute: false, captain: true }, cards: { yellow: 1, red: 0 }, goals: {}, shots: {}, passes: {} }] },
      { player: { id: 11, name: 'N. Saliba', photo: null },
        statistics: [{ games: { rating: '7.0', minutes: 24, substitute: true }, cards: { yellow: 0, red: 0 }, goals: {}, shots: {}, passes: {} }] },
      { player: { id: 12, name: 'Banc', photo: null }, statistics: [{ games: { rating: null } }] },
    ] },
    { team: { id: 2 }, players: [
      { player: { id: 20, name: 'G. Villar', photo: null },
        statistics: [{ games: { rating: '6.4', minutes: 90 }, cards: { yellow: 1, red: 1 }, goals: { total: 0 }, shots: {}, passes: {} }] },
    ] },
  ];
  const get = jest.fn(async () => reply(joueurs));
  const notes = await new ApiFootballInsights({ get } as any, () => true).getPlayerRatings(42, undefined, true);
  expect(notes).toEqual([
    expect.objectContaining({ id: 10, team: 'home', rating: 7.2, yellow: 1, red: 0, substitute: false, captain: true }),
    expect.objectContaining({ id: 11, team: 'home', rating: 7.0, substitute: true, captain: false }),
    expect.objectContaining({ id: 20, team: 'away', rating: 6.4, yellow: 1, red: 1 }),
  ]);
});

it('événements : identifiants du joueur et de l\'entrant', async () => {
  jest.useFakeTimers(); jest.setSystemTime(new Date('2026-10-17T15:00:00Z'));
  const fixture = { fixture: { id: 42 }, teams: { home: { id: 1, name: 'Villarreal' }, away: { id: 2, name: 'Elche' } } };
  const remplacement = { time: { elapsed: 66 }, team: { name: 'Villarreal' }, player: { id: 30, name: 'C. Macià' }, assist: { id: 11, name: 'N. Saliba' }, type: 'subst', detail: 'Substitution 1' };
  const client = { get: jest.fn(async (url: string) => reply(url === '/fixtures' ? [fixture] : url.endsWith('/events') ? [remplacement] : [])) };
  const r = await new MatchLiveService(client as any, () => true).stats(42, 'LIVE');
  expect(r!.events[0]).toMatchObject({ player_id: 30, assist_id: 11 });
  jest.useRealTimers();
});
