/**
 * La fiche d'un joueur : profil, statistiques par compétition, absences et
 * transferts — quatre routes d'API-Football que l'application ne lisait pas.
 */
import { FichesJoueurs, saisonParDefaut, traduireTypeTransfert, versStats } from '../services/fiche_joueur.service';

function client(reponses: (chemin: string, params: any) => any[]) {
  const appels: Array<[string, any]> = [];
  return {
    appels,
    get: jest.fn(async (chemin: string, opts: any) => {
      appels.push([chemin, opts?.params]);
      return { data: { response: reponses(chemin, opts?.params) } };
    }),
  };
}

const profil = (stats: any[]) => [{
  player: { id: 1100, name: 'E. Haaland', firstname: 'Erling', lastname: 'Braut Haaland', age: 26,
    birth: { date: '2000-07-21', place: 'Leeds', country: 'England' }, nationality: 'Norway',
    height: '195 cm', weight: '88 kg', injured: false, photo: 'p.png' },
  statistics: stats,
}];

const ligue = (nom: string, apps: number, extra: any = {}) => ({
  team: { name: 'Manchester City', logo: 't.png' }, league: { name: nom, logo: 'l.png' },
  games: { appearences: apps, lineups: apps, minutes: apps * 85, position: 'Attacker', rating: '7.4285' },
  goals: { total: 9, assists: 2, conceded: 0, saves: null }, cards: { yellow: 1, yellowred: 0, red: 0 },
  shots: { total: 30, on: 18 }, passes: { key: 6, accuracy: '71' }, dribbles: { success: 4 },
  duels: { won: 40 }, penalty: { scored: 2 }, ...extra,
});

it('profil, compétitions jouées triées, absences et transferts', async () => {
  const c = client((chemin) => ({
    '/players':   profil([ligue('UEFA Champions League', 3), ligue('Premier League', 8), ligue('FA Cup', 0)]),
    '/sidelined': [
      { type: 'Hamstring Injury', start: '2025-02-01', end: '2025-02-20' },
      { type: 'Yellow Cards', start: '2026-03-10', end: '2026-03-14' },
    ],
    '/transfers': [{ transfers: [
      { date: '2022-07-01', type: '€ 60M', teams: { out: { name: 'Dortmund' }, in: { name: 'Manchester City' } } },
      { date: '2020-01-01', type: 'Transfer', teams: { out: { name: 'Salzburg' }, in: { name: 'Dortmund' } } },
    ] }],
  } as any)[chemin] ?? []);

  const f = await new FichesJoueurs(c as any, () => true).fiche(1100, 2026);
  if (f === null || f === 'introuvable') throw new Error('fiche attendue');

  expect(f).toMatchObject({ name: 'E. Haaland', age: 26, nationality: 'Norway', birthPlace: 'Leeds, England', season: 2026 });
  // La coupe sans match disparaît ; le championnat, plus joué, passe devant.
  expect(f.stats.map((s) => s.league)).toEqual(['Premier League', 'UEFA Champions League']);
  expect(f.stats[0]).toMatchObject({ rating: 7.43, passAccuracy: 71, goals: 9, yellowCards: 1 });
  // Absences : la plus récente d'abord, traduite, suspensions repérées.
  expect(f.absences[0]).toMatchObject({ suspension: true, debut: '2026-03-10' });
  expect(f.absences[1].suspension).toBe(false);
  expect(f.transferts.map((t) => [t.depuis, t.vers, t.type])).toEqual([
    ['Dortmund', 'Manchester City', '€ 60M'], ['Salzburg', 'Dortmund', 'Transfert'],
  ]);
});

it('sans saison demandée, la précédente quand la courante est vide', async () => {
  const courante = saisonParDefaut();
  const c = client((chemin, params) => {
    if (chemin !== '/players') return [];
    return params.season === courante ? profil([ligue('Ligue 1', 0)]) : profil([ligue('Ligue 1', 30)]);
  });
  const f = await new FichesJoueurs(c as any, () => true).fiche(2200);
  if (f === null || f === 'introuvable') throw new Error('fiche attendue');
  expect(f.season).toBe(courante - 1);
  expect(f.stats[0].appearances).toBe(30);
});

it('un joueur inconnu est « introuvable », et cette réponse est gardée', async () => {
  const c = client(() => []);
  const svc = new FichesJoueurs(c as any, () => true);
  expect(await svc.fiche(3300, 2026)).toBe('introuvable');
  expect(await svc.fiche(3300, 2026)).toBe('introuvable');
  expect(c.appels.filter(([ch]) => ch === '/players')).toHaveLength(1);
});

it('une panne de l\'API rend null, pas une fiche vide', async () => {
  const c = { get: jest.fn(async () => { throw new Error('quota'); }) };
  expect(await new FichesJoueurs(c as any, () => true).fiche(4400, 2026)).toBeNull();
});

it('les types de transfert se lisent en français', () => {
  expect(traduireTypeTransfert('Loan')).toBe('Prêt');
  expect(traduireTypeTransfert('Free')).toBe('Libre');
  expect(traduireTypeTransfert('N/A')).toBe('Transfert');
  expect(traduireTypeTransfert('Back from Loan')).toBe('Retour de prêt');
  expect(traduireTypeTransfert('€ 12.5M')).toBe('€ 12.5M');
});

it('une note absente n\'est pas un zéro', () => {
  expect(versStats({ games: { rating: null, appearences: 1 } }).rating).toBeNull();
});
