/**
 * Les palmarès individuels : buteurs, passeurs, cartons jaunes et rouges.
 *
 * Seuls les buteurs étaient lus, alors que le plan de l'API publie les quatre
 * au même prix. Chaque palmarès a sa route, son cache, et rend les cartons.
 */
import { ApiFootballInsights, CLASSEMENTS_JOUEURS } from '../services/api_football_insights.service';

function joueur(nom: string, stats: any) {
  return {
    player: { id: 1, name: nom, photo: null },
    statistics: [{ team: { name: 'Lens', logo: null }, games: { appearences: 8 }, ...stats }],
  };
}

function client(reponses: Record<string, any[]>) {
  const appels: string[] = [];
  return {
    appels,
    get: jest.fn(async (chemin: string) => {
      appels.push(chemin);
      return { data: { response: reponses[chemin] ?? [] } };
    }),
  };
}

it('chaque palmarès interroge sa propre route', async () => {
  const c = client({});
  const svc = new ApiFootballInsights(c as any, () => true);
  for (const type of Object.keys(CLASSEMENTS_JOUEURS) as Array<keyof typeof CLASSEMENTS_JOUEURS>) {
    await svc.getTopPlayers(type, 9001, 2026);
  }
  expect(c.appels).toEqual([
    '/players/topscorers', '/players/topassists', '/players/topyellowcards', '/players/topredcards',
  ]);
});

it('les cartons sont rendus, dans l\'ordre de l\'API', async () => {
  const c = client({
    '/players/topyellowcards': [
      joueur('Danso', { cards: { yellow: 6, red: 0 }, goals: { total: 0, assists: 1 } }),
      joueur('Thomasson', { cards: { yellow: 5, red: 1 }, goals: { total: 2, assists: 0 } }),
    ],
  });
  const svc = new ApiFootballInsights(c as any, () => true);
  const jaunes = await svc.getTopPlayers('jaunes', 9002, 2026);
  expect(jaunes?.map((j) => [j.rank, j.name, j.yellowCards, j.redCards]))
    .toEqual([[1, 'Danso', 6, 0], [2, 'Thomasson', 5, 1]]);
});

it('un palmarès gardé en cache ne sert pas l\'autre', async () => {
  const c = client({
    '/players/topscorers':  [joueur('Buteur', { goals: { total: 9, assists: 0 } })],
    '/players/topassists':  [joueur('Passeur', { goals: { total: 1, assists: 7 } })],
  });
  const svc = new ApiFootballInsights(c as any, () => true);
  expect((await svc.getTopPlayers('buteurs', 9003, 2026))?.[0].name).toBe('Buteur');
  expect((await svc.getTopPlayers('passeurs', 9003, 2026))?.[0].name).toBe('Passeur');
  // Le second appel de chaque type vient du cache.
  await svc.getTopPlayers('buteurs', 9003, 2026);
  expect(c.appels.filter((a) => a === '/players/topscorers')).toHaveLength(1);
});

it('les buteurs restent servis à l\'ancienne façon', async () => {
  const c = client({ '/players/topscorers': [joueur('Buteur', { goals: { total: 9, assists: 2 } })] });
  const svc = new ApiFootballInsights(c as any, () => true);
  const b = await svc.getTopScorers(9004, 2026);
  expect(b?.[0]).toMatchObject({ name: 'Buteur', goals: 9, assists: 2, yellowCards: 0, redCards: 0 });
});
