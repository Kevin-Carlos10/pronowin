/**
 * Résumés automatiques des matchs terminés (18 octobre 2026) : un contenu à
 * nous pour les actualités de l'accueil, écrit seulement quand il est sûr.
 */
import { redigerResume, type ContexteResume } from '../services/resumes_match.service';

const DOM = 168, EXT = 160;
type But = [minute: number, camp: 'dom' | 'ext', joueur: string, detail?: string, extra?: number];

function fiche(o: {
  statut?: string; score: [number, number]; mt?: [number, number]; tab?: [number, number];
  buts?: But[]; rouges?: Array<[number, 'dom' | 'ext', string]>;
  stats?: Record<string, [string | number, string | number]>; notes?: Array<[string, string]>;
}) {
  const equipe = (c: 'dom' | 'ext') => ({ id: c === 'dom' ? DOM : EXT });
  return {
    fixture: { id: 1, status: { short: o.statut ?? 'FT' } },
    teams: { home: { id: DOM, name: 'Bayer Leverkusen' }, away: { id: EXT, name: 'SC Freiburg' } },
    goals: { home: o.score[0], away: o.score[1] },
    score: {
      halftime: o.mt ? { home: o.mt[0], away: o.mt[1] } : { home: null, away: null },
      penalty: o.tab ? { home: o.tab[0], away: o.tab[1] } : { home: null, away: null },
    },
    events: [
      ...(o.buts ?? []).map(([m, c, j, detail, extra]) => ({
        time: { elapsed: m, extra: extra ?? null }, team: equipe(c), player: { name: j },
        type: 'Goal', detail: detail ?? 'Normal Goal', comments: null })),
      ...(o.rouges ?? []).map(([m, c, j]) => ({
        time: { elapsed: m, extra: null }, team: equipe(c), player: { name: j }, type: 'Card', detail: 'Red Card' })),
    ],
    statistics: o.stats ? (['dom', 'ext'] as const).map((c, i) => ({
      team: equipe(c),
      statistics: Object.entries(o.stats!).map(([type, v]) => ({ type, value: v[i] })),
    })) : [],
    players: o.notes ? [{ team: equipe('dom'), players: o.notes.map(([nom, note]) => ({
      player: { name: nom }, statistics: [{ games: { rating: note } }] })) }] : [],
  };
}

const ctx: ContexteResume = {
  domicile: 'Bayer Leverkusen', exterieur: 'SC Freiburg',
  pronostic: { libelle: 'Victoire Bayer Leverkusen', libelleEn: 'Bayer Leverkusen to win', vip: false, resultat: 'WIN' },
};

describe('le résumé', () => {
  // Bayer Leverkusen 2-1 SC Freiburg, 18 octobre 2026 (relevé réel).
  const reel = fiche({
    score: [2, 1], mt: [1, 1],
    buts: [[14, 'ext', 'Derry Lionel Scherhant'], [19, 'dom', 'Ibrahim Maza'], [76, 'dom', 'Patrik Schick']],
    stats: { 'Ball Possession': ['58%', '42%'], 'Total Shots': [14, 9], 'Shots on Goal': [6, 3] },
    notes: [['P. Schick', '8.66'], ['I. Maza', '8.54'], ['Remplaçant', '0']],
  });

  it('titre, buts, statistiques, homme du match, pronostic — en français', () => {
    const r = redigerResume(reel, ctx)!;
    expect(r.titre).toBe('Bayer Leverkusen s\'impose face à SC Freiburg (2-1)');
    expect(r.resume.split('\n\n')).toEqual([
      'Score à la mi-temps : 1-1.',
      'Buts — Bayer Leverkusen : Ibrahim Maza (19\'), Patrik Schick (76\') · SC Freiburg : Derry Lionel Scherhant (14\').',
      'Statistiques : possession 58 % – 42 %, tirs 14 – 9, tirs cadrés 6 – 3.',
      'Homme du match : P. Schick (8,7).',
      'Pronostic PronoWin : « Victoire Bayer Leverkusen » — gagnant.',
    ]);
  });

  it('et en anglais', () => {
    const r = redigerResume(reel, ctx)!;
    expect(r.titreEn).toBe('Bayer Leverkusen beat SC Freiburg 2-1');
    expect(r.resumeEn).toContain('Goals — Bayer Leverkusen: Ibrahim Maza (19\'), Patrik Schick (76\') · SC Freiburg: Derry Lionel Scherhant (14\').');
    expect(r.resumeEn).toContain('Player of the match: P. Schick (8.7).');
    expect(r.resumeEn).toContain('PronoWin prediction: "Bayer Leverkusen to win" — won.');
  });

  it('pronostic VIP : le résultat, jamais le choix', () => {
    const r = redigerResume(reel, { ...ctx, pronostic: { ...ctx.pronostic!, vip: true, resultat: 'LOSS' } })!;
    expect(r.resume).toContain('Pronostic VIP PronoWin : perdant.');
    expect(r.resume).not.toContain('Victoire Bayer Leverkusen');
    expect(r.resumeEn).toContain('PronoWin VIP prediction: lost.');
  });

  it('aucun mot de pari : le texte s\'affiche aussi sur iPhone', () => {
    const r = redigerResume(reel, ctx)!;
    for (const t of [r.titre, r.resume, r.titreEn, r.resumeEn]) {
      expect(t).not.toMatch(/\b(cote|cotes|pari|paris|mise|miser|bookmaker|odds|bet|stake)\b/i);
    }
  });

  it('victoire à l\'extérieur, remontée, large victoire, nuls', () => {
    expect(redigerResume(fiche({ score: [0, 2] }), ctx)!.titre).toBe('SC Freiburg s\'impose chez Bayer Leverkusen (0-2)');
    expect(redigerResume(fiche({ score: [0, 2] }), ctx)!.titreEn).toBe('SC Freiburg win 2-0 at Bayer Leverkusen');
    expect(redigerResume(fiche({ score: [2, 1], mt: [0, 1] }), ctx)!.titre).toBe('Bayer Leverkusen renverse SC Freiburg (2-1)');
    expect(redigerResume(fiche({ score: [4, 0], mt: [2, 0] }), ctx)!.titre).toBe('Bayer Leverkusen s\'impose largement face à SC Freiburg (4-0)');
    expect(redigerResume(fiche({ score: [1, 1] }), ctx)!.titre).toBe('Bayer Leverkusen et SC Freiburg dos à dos (1-1)');
    expect(redigerResume(fiche({ score: [0, 0] }), ctx)!.titreEn).toBe('Goalless draw between Bayer Leverkusen and SC Freiburg');
  });

  it('prolongation et tirs au but', () => {
    expect(redigerResume(fiche({ statut: 'AET', score: [2, 1] }), ctx)!.titre)
      .toBe('Bayer Leverkusen s\'impose après prolongation face à SC Freiburg (2-1)');
    const tab = redigerResume(fiche({ statut: 'PEN', score: [1, 1], tab: [4, 5] }), ctx)!;
    expect(tab.titre).toBe('SC Freiburg l\'emporte aux tirs au but face à Bayer Leverkusen (1-1, 4-5 t.a.b.)');
    expect(tab.titreEn).toBe('SC Freiburg win on penalties against Bayer Leverkusen (1-1, 4-5 pens)');
  });

  it('doublé et triplé dans le titre', () => {
    const double = fiche({ score: [2, 0], buts: [[10, 'dom', 'Patrik Schick'], [80, 'dom', 'Patrik Schick', 'Penalty']] });
    const r = redigerResume(double, ctx)!;
    expect(r.titre).toBe('Bayer Leverkusen s\'impose face à SC Freiburg (2-0), doublé de Patrik Schick');
    expect(r.titreEn).toBe('Bayer Leverkusen beat SC Freiburg 2-0, Patrik Schick scores twice');
    expect(r.resume).toContain('Patrik Schick (10\'), Patrik Schick (pen., 80\')');
    const triple = fiche({ score: [3, 0], buts: [[10, 'dom', 'Schick'], [20, 'dom', 'Schick'], [90, 'dom', 'Schick', undefined, 2]] });
    expect(redigerResume(triple, ctx)!.titreEn).toBe('Bayer Leverkusen thrash SC Freiburg 3-0, hat-trick for Schick');
    expect(redigerResume(triple, ctx)!.resume).toContain('(90+2\')');
  });

  it('doublé dans l\'équipe battue : « malgré », pour ne pas le donner au vainqueur', () => {
    // Sporting CP 2-3 Lask Linz, 21 octobre 2026 : le titre disait « Lask Linz
    // s'impose chez Sporting CP (2-3), doublé de Luis Suárez ».
    const perdant = fiche({ score: [2, 3], buts: [[12, 'ext', 'A'], [30, 'dom', 'Luis Suárez'],
      [55, 'ext', 'B'], [70, 'dom', 'Luis Suárez'], [88, 'ext', 'C']] });
    const r = redigerResume(perdant, ctx)!;
    expect(r.titre).toBe('SC Freiburg s\'impose chez Bayer Leverkusen (2-3), malgré le doublé de Luis Suárez');
    expect(r.titreEn).toBe('SC Freiburg win 3-2 at Bayer Leverkusen, despite Luis Suárez scoring twice');
    // Deux doublés : celui du vainqueur.
    const deux = fiche({ score: [2, 3], buts: [[12, 'ext', 'Grifo'], [30, 'dom', 'Luis Suárez'],
      [55, 'ext', 'Grifo'], [70, 'dom', 'Luis Suárez'], [88, 'ext', 'C']] });
    expect(redigerResume(deux, ctx)!.titre).toBe('SC Freiburg s\'impose chez Bayer Leverkusen (2-3), doublé de Grifo');
    // Match nul : pas de vainqueur, pas de « malgré ».
    const nul = fiche({ score: [2, 2], buts: [[30, 'dom', 'Luis Suárez'], [40, 'ext', 'A'], [50, 'ext', 'B'], [70, 'dom', 'Luis Suárez']] });
    expect(redigerResume(nul, ctx)!.titre).toBe('Bayer Leverkusen et SC Freiburg dos à dos (2-2), doublé de Luis Suárez');
  });

  it('but contre son camp : rangé du côté de l\'équipe qui en profite, quelle que soit la lecture du fournisseur', () => {
    // Rattaché à l'équipe du joueur (Freiburg), il profite à Leverkusen.
    const a = redigerResume(fiche({ score: [1, 0], buts: [[11, 'ext', 'L. Kübler', 'Own Goal']] }), ctx)!;
    expect(a.resume).toContain('Buts — Bayer Leverkusen : L. Kübler (c.s.c., 11\').');
    // Rattaché à l'équipe qui en profite.
    const b = redigerResume(fiche({ score: [1, 0], buts: [[11, 'dom', 'L. Kübler', 'Own Goal']] }), ctx)!;
    expect(b.resume).toContain('Buts — Bayer Leverkusen : L. Kübler (c.s.c., 11\').');
  });

  it('événements incomplets : pas de liste de buteurs inventée', () => {
    const r = redigerResume(fiche({ score: [2, 1], buts: [[19, 'dom', 'Ibrahim Maza']] }), ctx)!;
    expect(r.resume).not.toContain('Buts');
    expect(r.titre).toBe('Bayer Leverkusen s\'impose face à SC Freiburg (2-1)');
  });

  it('exclusion', () => {
    const r = redigerResume(fiche({ score: [1, 0], rouges: [[54, 'ext', 'M. Eggestein']] }), ctx)!;
    expect(r.resume).toContain('Exclusion : M. Eggestein (SC Freiburg, 54\').');
  });

  it('match pas encore terminé, ou score différent de la base : pas de résumé', () => {
    expect(redigerResume(fiche({ statut: '2H', score: [2, 1] }), ctx)).toBeNull();
    expect(redigerResume(reel, ctx, { dom: 2, ext: 2 })).toBeNull();
    expect(redigerResume(reel, ctx, { dom: 2, ext: 1 })).not.toBeNull();
  });

  it('sélections nationales : le nom du pays dans chaque langue', () => {
    const r = redigerResume(fiche({ score: [1, 0] }), { domicile: 'Belgium', exterieur: 'Germany' })!;
    expect(r.titre).toBe('Belgique s\'impose face à Allemagne (1-0)');
    expect(r.titreEn).toBe('Belgium beat Germany 1-0');
  });
});

describe('la publication', () => {
  // Base simulée : les méthodes Prisma ne se typent pas comme de simples promesses.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { publierResumes, _oublierEssais } = require('../services/resumes_match.service');

  const MAINTENANT = new Date(Date.UTC(2026, 9, 18, 20, 0, 0));
  const match = (id: string, heuresAvant: number, prono: any) => ({
    id, externalId: 1, homeTeam: 'Bayer Leverkusen', awayTeam: 'SC Freiburg', league: 'Bundesliga',
    homeScore: 2, awayScore: 1, matchDate: new Date(MAINTENANT.getTime() - heuresAvant * 3600_000), pronostic: prono,
  });
  const prono = (o: any = {}) => ({ predictionLabel: 'Les deux équipes marquent', predictionLabelEn: null,
    isPremium: false, result: 'WIN', publicationRecordedAt: new Date('2026-10-18T09:00:00Z'), ...o });
  let crees: any[];
  let lecture: any;

  beforeEach(() => {
    crees = [];
    _oublierEssais();
    jest.spyOn(prisma.resumeMatch, 'create').mockImplementation(async ({ data }: any) => { crees.push(data); return data; });
    jest.spyOn(apiFootballService.httpClient, 'get').mockResolvedValue({ data: { response: [fiche({ score: [2, 1], mt: [1, 1] })] } });
  });
  afterEach(() => jest.restoreAllMocks());

  async function publier(matchs: any[], quand = MAINTENANT) {
    jest.spyOn(prisma.match, 'findMany').mockImplementation(async (args: any) => { lecture = args; return matchs; });
    return publierResumes(quand);
  }

  it('matchs pronostiqués ou des grandes compétitions, terminés depuis 2 h à 48 h, sans résumé ; libellé traduit en anglais', async () => {
    expect(await publier([match('m1', 3, prono())])).toEqual({ publies: 1 });
    expect(lecture.where).toEqual({
      status: 'FINISHED', source: 'API_FOOTBALL', resume: null,
      matchDate: { gte: new Date(MAINTENANT.getTime() - 48 * 3600_000), lte: new Date(MAINTENANT.getTime() - 2 * 3600_000) },
      OR: [
        { pronostic: { publicationRecordedAt: { not: null } } },
        { leagueCode: { in: ['PL', 'PD', 'SA', 'BL1', 'FL1', 'CL', 'WC'] } },
      ],
    });
    expect(crees[0]).toMatchObject({ matchId: 'm1', ligue: 'Bundesliga', titre: 'Bayer Leverkusen s\'impose face à SC Freiburg (2-1)' });
    expect(crees[0].resumeEn).toContain('PronoWin prediction: "Both Teams Score" — won.');
  });

  it('pronostic pas encore réglé : on attend, jusqu\'à 6 h après le coup d\'envoi', async () => {
    expect(await publier([match('m1', 3, prono({ result: null }))])).toEqual({ publies: 0 });
    expect(await publier([match('m1', 7, prono({ result: null }))])).toEqual({ publies: 1 });
    expect(crees[0].resume).not.toContain('Pronostic');
  });

  it('fiche du fournisseur pas encore à jour (score différent) : rien, on réessaiera 30 minutes plus tard', async () => {
    const get = jest.spyOn(apiFootballService.httpClient, 'get')
      .mockResolvedValue({ data: { response: [fiche({ statut: 'FT', score: [1, 1] })] } });
    expect(await publier([match('m1', 3, prono())])).toEqual({ publies: 0 });
    const plusTard = (min: number) => new Date(MAINTENANT.getTime() + min * 60_000);
    await publier([match('m1', 3, prono())], plusTard(10));
    await publier([match('m1', 3, prono())], plusTard(20));
    expect(get).toHaveBeenCalledTimes(1);
    get.mockResolvedValue({ data: { response: [fiche({ score: [2, 1], mt: [1, 1] })] } });
    expect(await publier([match('m1', 3, prono())], plusTard(30))).toEqual({ publies: 1 });
    expect(get).toHaveBeenCalledTimes(2);
  });

  it('fournisseur injoignable : même délai avant de réessayer', async () => {
    const get = jest.spyOn(apiFootballService.httpClient, 'get').mockRejectedValue(new Error('ECONNRESET'));
    await publier([match('m1', 3, prono())]);
    await publier([match('m1', 3, prono())], new Date(MAINTENANT.getTime() + 10 * 60_000));
    expect(get).toHaveBeenCalledTimes(1);
  });

  it('grand match sans pronostic : résumé, sans paragraphe de pronostic', async () => {
    expect(await publier([match('m1', 3, null)])).toEqual({ publies: 1 });
    expect(crees[0].titre).toBe('Bayer Leverkusen s\'impose face à SC Freiburg (2-1)');
    expect(crees[0].resume).not.toContain('Pronostic');
    expect(crees[0].resumeEn).not.toContain('prediction');
  });

  it('pronostic resté en brouillon : jamais dit, ni attendu', async () => {
    const brouillon = prono({ publicationRecordedAt: null, result: null, predictionLabel: 'Victoire SC Freiburg' });
    expect(await publier([match('m1', 3, brouillon)])).toEqual({ publies: 1 });
    expect(crees[0].resume).not.toContain('Pronostic');
    expect(crees[0].resume).not.toContain('Victoire SC Freiburg');
  });

  it('les matchs pronostiqués d\'abord, cinq essais par passage', async () => {
    const sans = [1, 2, 3, 4, 5, 6].map(i => match(`g${i}`, 3, null));
    const avec = [match('p1', 4, prono()), match('p2', 5, prono())];
    // La base les rend par date : les grands matchs sans pronostic, plus récents, en tête.
    expect(await publier([...sans, ...avec])).toEqual({ publies: 5 });
    expect(crees.map(c => c.matchId)).toEqual(['p1', 'p2', 'g1', 'g2', 'g3']);
  });

  it('un pronostic en attente de règlement ne prend pas la place des autres', async () => {
    const attente = [1, 2, 3, 4, 5].map(i => match(`p${i}`, 3, prono({ result: null })));
    expect(await publier([...attente, match('g1', 3, null)])).toEqual({ publies: 1 });
    expect(crees.map(c => c.matchId)).toEqual(['g1']);
  });
});

describe('au format des actualités', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { resumesPourActualites } = require('../services/resumes_match.service');
  afterEach(() => jest.restoreAllMocks());

  it('les logos et le score du match, pour le visuel de la carte', async () => {
    jest.spyOn(prisma.resumeMatch, 'findMany').mockResolvedValue([{
      id: 'r1', matchId: 'm1', titre: 'T', titreEn: 'T', resume: 'R', resumeEn: 'R', ligue: 'Ligue 1',
      creeLe: new Date('2026-10-18T16:44:00Z'),
      match: { homeTeamLogo: 'https://media.api-sports.io/football/teams/77.png',
        awayTeamLogo: 'https://media.api-sports.io/football/teams/81.png', homeScore: 2, awayScore: 5 },
    }]);
    const [a] = await resumesPourActualites();
    expect(a).toMatchObject({ id: 'resume_r1', type: 'resume_match', match_id: 'm1', image_url: null, score: '2-5',
      logo_domicile: 'https://media.api-sports.io/football/teams/77.png',
      logo_exterieur: 'https://media.api-sports.io/football/teams/81.png' });
  });

  it('s\'il faut choisir, les résumés des matchs pronostiqués ; puis l\'ordre des dates', async () => {
    const r = (id: string, heure: number, prono: boolean) => ({
      id, matchId: id, titre: id, titreEn: id, resume: 'R', resumeEn: 'R', ligue: 'Ligue 1',
      creeLe: new Date(Date.UTC(2026, 9, 21, heure)),
      match: { homeTeamLogo: null, awayTeamLogo: null, homeScore: 1, awayScore: 0, hasPublishedPronostic: prono },
    });
    const lecture = jest.spyOn(prisma.resumeMatch, 'findMany').mockResolvedValue([
      r('g1', 23, false), r('g2', 22, false), r('p1', 21, true), r('g3', 20, false), r('p2', 19, true)]);
    const choisis = await resumesPourActualites(3);
    expect((lecture.mock.calls[0][0] as any).take).toBe(9);
    expect(choisis.map((a: any) => a.match_id)).toEqual(['g1', 'p1', 'p2']);
  });
});
