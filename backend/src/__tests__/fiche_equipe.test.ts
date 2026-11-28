/**
 * La fiche d'une équipe : club, stade, entraîneur, effectif — /teams, /coachs
 * et /players/squads, que l'application ne lisait pas.
 */
import { FichesEquipes, entraineurActuel } from '../services/fiche_equipe.service';
import { ApiFootballInsights } from '../services/api_football_insights.service';

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

it('club, stade, entraîneur en poste et effectif rangé par poste puis numéro', async () => {
  const c = client({
    '/teams': [{
      team: { id: 116, name: 'Lens', country: 'France', founded: 1906, logo: 'l.png' },
      venue: { name: 'Stade Bollaert-Delelis', city: 'Lens', capacity: 38223, image: 'v.png' },
    }],
    '/coachs': [
      { id: 1, name: 'Ancien', career: [{ team: { id: 116 }, start: '2020-07-01', end: '2024-06-30' }] },
      { id: 2, name: 'Pierre Sage', age: 47, nationality: 'France', career: [{ team: { id: 116 }, start: '2025-07-01', end: null }] },
    ],
    '/players/squads': [{ players: [
      { id: 10, name: 'Attaquant', number: 9, position: 'Attacker' },
      { id: 11, name: 'Gardien', number: 30, position: 'Goalkeeper' },
      { id: 12, name: 'Défenseur B', number: 24, position: 'Defender' },
      { id: 13, name: 'Défenseur A', number: 4, position: 'Defender' },
    ] }],
  });
  const f = await new FichesEquipes(c as any, () => true).fiche(116);
  if (f === null || f === 'introuvable') throw new Error('fiche attendue');

  expect(f).toMatchObject({ name: 'Lens', founded: 1906, venue: { name: 'Stade Bollaert-Delelis', capacity: 38223 } });
  expect(f.coach?.name).toBe('Pierre Sage');
  expect(f.squad.map((j) => j.name)).toEqual(['Gardien', 'Défenseur A', 'Défenseur B', 'Attaquant']);
});

it('une équipe inconnue est « introuvable », gardée en cache', async () => {
  const c = client({});
  const svc = new FichesEquipes(c as any, () => true);
  expect(await svc.fiche(99999)).toBe('introuvable');
  expect(await svc.fiche(99999)).toBe('introuvable');
  expect(c.appels.filter((a) => a === '/teams')).toHaveLength(1);
});

it('sans entraîneur ni effectif publiés, la fiche existe quand même', async () => {
  const c = {
    get: jest.fn(async (chemin: string) => {
      if (chemin === '/teams') return { data: { response: [{ team: { id: 5, name: 'X' }, venue: {} }] } };
      throw new Error('quota');
    }),
  };
  const f = await new FichesEquipes(c as any, () => true).fiche(5);
  if (f === null || f === 'introuvable') throw new Error('fiche attendue');
  expect(f.coach).toBeNull();
  expect(f.squad).toEqual([]);
  expect(f.venue).toBeNull();
});

it("l'entraîneur sans carrière lisible : le premier de la liste", () => {
  expect(entraineurActuel([{ name: 'A' }, { name: 'B' }], 1)?.name).toBe('A');
  expect(entraineurActuel([], 1)).toBeNull();
});

it('le bilan de saison et le système le plus utilisé sont lus', async () => {
  const c = client({
    '/teams/statistics': {
      form: 'WWDLW',
      fixtures: { played: { total: 8 }, wins: { total: 5 }, draws: { total: 2 }, loses: { total: 1 } },
      lineups: [{ formation: '4-4-2', played: 2 }, { formation: '3-4-3', played: 6 }],
      goals: { for: { minute: {}, average: { total: '1.9' } }, against: { minute: {}, average: { total: '0.8' } } },
      clean_sheet: { total: 4 }, failed_to_score: { total: 1 }, penalty: { scored: { total: 2 } },
    } as any,
  });
  const s = await new ApiFootballInsights(c as any, () => true).getTeamSeasonStats(61, 2026, 116);
  expect(s?.bilan).toEqual({ joues: 8, victoires: 5, nuls: 2, defaites: 1 });
  expect(s?.systeme).toBe('3-4-3');
});
