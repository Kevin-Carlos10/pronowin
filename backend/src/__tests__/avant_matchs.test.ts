/**
 * Avant-matchs automatiques (22 octobre 2026) : la veille des grands matchs
 * et des matchs pronostiqués, la place des deux équipes, leur forme, leurs
 * confrontations et les absents — sans jamais dévoiler le pronostic.
 */
import { redigerAvantMatch, type DonneesAvantMatch } from '../services/avant_matchs.service';
import type { MatchRecent } from '../services/forme_recente.service';

const recent = (issue: 'V' | 'N' | 'D', pour: number, contre: number, adversaire: string): MatchRecent =>
  ({ date: '2026-10-18T14:00:00Z', competition: 'Premier League', adversaire, adversaireLogo: null, domicile: true,
    butsPour: pour, butsContre: contre, issue });

const complet: DonneesAvantMatch = {
  domicile: 'Arsenal', exterieur: 'Chelsea', competition: 'Premier League',
  classement: { dom: { rang: 2, points: 17 }, ext: { rang: 5, points: 14 } },
  forme: {
    dom: [recent('V', 2, 0, 'Fulham'), recent('V', 3, 1, 'Everton'), recent('N', 1, 1, 'Brighton'),
      recent('V', 1, 0, 'Wolves'), recent('V', 2, 1, 'Leeds')],
    ext: [recent('D', 0, 2, 'Liverpool'), recent('V', 2, 0, 'Burnley'), recent('N', 0, 0, 'Spurs')],
  },
  h2h: { joues: 5, dom: 3, ext: 0, nuls: 2, derniere: { date: '2026-03-01T16:30:00Z', recevait: 'ext', butsDom: 1, butsExt: 1 } },
  absents: { dom: [{ nom: 'B. Saka', statut: 'incertain' }, { nom: 'D. Rice', statut: 'suspendu' }], ext: [] },
  pronostic: true,
};

describe('la rédaction', () => {
  it('titre, classement, forme, face-à-face, absents, renvoi au pronostic — en français', () => {
    const a = redigerAvantMatch(complet)!;
    expect(a.titre).toBe('Avant-match : Arsenal (2e) reçoit Chelsea (5e)');
    expect(a.resume.split('\n\n')).toEqual([
      'Premier League. Arsenal, 2e avec 17 points, reçoit Chelsea, 5e avec 14 points.',
      'Arsenal : 4 victoires et 1 nul sur ses cinq derniers matchs (dernier : victoire 2-0 contre Fulham). '
        + 'Chelsea : 1 victoire, 1 nul et 1 défaite sur ses trois derniers matchs (dernier : défaite 0-2 contre Liverpool).',
      'Face-à-face (5 dernières rencontres) : 3 victoires d\'Arsenal et 2 nuls. Dernière rencontre : Chelsea 1-1 Arsenal (mars 2026).',
      'Absents ou incertains — Arsenal : B. Saka (incertain) et D. Rice (suspendu) · Chelsea : aucun signalé.',
      'Le pronostic PronoWin de ce match est sur sa fiche.',
    ]);
  });

  it('et en anglais', () => {
    const a = redigerAvantMatch(complet)!;
    expect(a.titreEn).toBe('Preview: Arsenal (2nd) host Chelsea (5th)');
    expect(a.resumeEn.split('\n\n')).toEqual([
      'Premier League. Arsenal, 2nd on 17 points, host Chelsea, 5th on 14 points.',
      'Arsenal: 4 wins and 1 draw in their last five (latest: won 2-0 v Fulham). '
        + 'Chelsea: 1 win, 1 draw and 1 defeat in their last three (latest: lost 0-2 to Liverpool).',
      'Head to head (last 5 meetings): 3 wins for Arsenal and 2 draws. Last meeting: Chelsea 1-1 Arsenal (March 2026).',
      'Missing or doubtful — Arsenal: B. Saka (doubtful) and D. Rice (suspended) · Chelsea: none reported.',
      'PronoWin\'s prediction for this match is on its page.',
    ]);
  });

  it('le pronostic n\'est jamais dévoilé, et aucun mot de pari : le texte s\'affiche aussi sur iPhone', () => {
    const a = redigerAvantMatch(complet)!;
    const tout = [a.titre, a.titreEn, a.resume, a.resumeEn].join(' ');
    expect(tout).not.toMatch(/\b(cotes?|paris?|parier|mises?|bookmaker|odds|bets?|betting|stake)\b/i);
    expect(redigerAvantMatch({ ...complet, pronostic: false })!.resume).not.toContain('pronostic');
  });

  it('sans classement commun : titre sans les rangs', () => {
    const a = redigerAvantMatch({ ...complet, classement: null })!;
    expect(a.titre).toBe('Avant-match : Arsenal – Chelsea');
    expect(a.titreEn).toBe('Preview: Arsenal v Chelsea');
    expect(a.resume.split('\n\n')[0]).toBe('Premier League. Arsenal reçoit Chelsea.');
  });

  it('1er, 1st, 11th, 22nd, 23rd', () => {
    const rangs = (dom: number, ext: number) => redigerAvantMatch({ ...complet,
      classement: { dom: { rang: dom, points: 1 }, ext: { rang: ext, points: 1 } } })!;
    expect(rangs(1, 11).titre).toBe('Avant-match : Arsenal (1er) reçoit Chelsea (11e)');
    expect(rangs(1, 11).titreEn).toBe('Preview: Arsenal (1st) host Chelsea (11th)');
    expect(rangs(22, 23).titreEn).toBe('Preview: Arsenal (22nd) host Chelsea (23rd)');
    expect(rangs(1, 11).resume).toContain('avec 1 point,');
  });

  it('aucune rencontre récente ; absents nombreux ; aucun absent', () => {
    const a = redigerAvantMatch({ ...complet,
      h2h: { joues: 0, dom: 0, ext: 0, nuls: 0, derniere: null },
      absents: { dom: 'ABCDEFGH'.split('').map(l => ({ nom: l, statut: 'absent' as const })), ext: [] } })!;
    expect(a.resume).toContain('Aucune confrontation récente entre les deux équipes.');
    expect(a.resumeEn).toContain('The two sides have not met recently.');
    expect(a.resumeEn).toContain('Unavailable — Arsenal: A, B, C, D, E, F and 2 others · Chelsea: none reported.');
    expect(a.resume).toContain('Absents — Arsenal : A, B, C, D, E, F et 2 autres · Chelsea : aucun signalé.');
    expect(redigerAvantMatch({ ...complet, absents: { dom: [], ext: [] } })!.resume)
      .toContain('Aucun absent signalé pour l\'instant.');
    expect(redigerAvantMatch({ ...complet, absents: null })!.resume).not.toContain('Absents');
  });

  it('sélections nationales : le nom du pays dans chaque langue', () => {
    const a = redigerAvantMatch({ ...complet, domicile: 'Germany', exterieur: 'Belgium', competition: 'World Cup' })!;
    expect(a.titre).toBe('Avant-match : Allemagne (2e) reçoit Belgique (5e)');
    expect(a.titreEn).toBe('Preview: Germany (2nd) host Belgium (5th)');
  });

  it('pas de quoi écrire : au moins deux blocs parmi classement, forme, face-à-face', () => {
    expect(redigerAvantMatch({ ...complet, forme: null, h2h: null })).toBeNull();
    expect(redigerAvantMatch({ ...complet, h2h: null, forme: { dom: complet.forme!.dom, ext: [] } })).toBeNull();
    expect(redigerAvantMatch({ ...complet, classement: null, h2h: null })).toBeNull();
    expect(redigerAvantMatch({ ...complet, classement: null, absents: null })).not.toBeNull();
  });
});

describe('les données du fournisseur', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { donneesAvantMatch } = require('../services/avant_matchs.service');
  afterEach(() => jest.restoreAllMocks());

  const ligne = (teamId: number, teamName: string, rank: number, points: number, groupId = 'g') =>
    ({ teamId, teamName, rank, points, groupId, isMatchTeam: true });
  const match = { externalId: 99, homeTeam: 'Arsenal', awayTeam: 'Chelsea', league: 'Premier League', leagueCode: 'PL',
    matchDate: new Date('2026-10-25T16:30:00Z'), pronosticPublie: false };

  function fournisseur(o: { classement?: any; forme?: any; h2h?: any; absents?: any } = {}) {
    jest.spyOn(apiFootballService, 'getStandings').mockResolvedValue(o.classement ?? { status: 'available', season: 2026,
      rows: [ligne(42, 'Arsenal', 2, 17), ligne(49, 'Chelsea', 5, 14), { ...ligne(40, 'Liverpool', 1, 20), isMatchTeam: false }] });
    jest.spyOn(apiFootballService, 'getFormeRecente').mockResolvedValue(o.forme ?? { home: [], away: [] });
    jest.spyOn(apiFootballService, 'getH2H').mockResolvedValue(o.h2h !== undefined ? o.h2h : {
      aggregates: { numberOfMatches: 2, homeTeam: { id: 42, name: 'Arsenal', wins: 1, draws: 1, losses: 0 },
        awayTeam: { id: 49, name: 'Chelsea', wins: 0, draws: 1, losses: 1 } },
      matches: [
        { utcDate: '2025-12-01T20:00:00Z', status: 'FINISHED', homeTeam: { id: 42 }, awayTeam: { id: 49 }, score: { fullTime: { home: 2, away: 0 } } },
        { utcDate: '2026-03-01T16:30:00Z', status: 'FINISHED', homeTeam: { id: 49 }, awayTeam: { id: 42 }, score: { fullTime: { home: 3, away: 1 } } },
        { utcDate: '2026-10-25T16:30:00Z', status: 'SCHEDULED', homeTeam: { id: 42 }, awayTeam: { id: 49 }, score: { fullTime: { home: null, away: null } } },
      ] });
    jest.spyOn(apiFootballService, 'getInjuries').mockResolvedValue(o.absents !== undefined ? o.absents : [
      { name: 'B. Saka', team: 'home', type: 'Questionable', reason: 'Blessure', photo: null, suspension: false },
      { name: 'D. Rice', team: 'home', type: 'Missing Fixture', reason: 'Suspendu', photo: null, suspension: true },
      { name: 'R. James', team: 'away', type: 'Missing Fixture', reason: 'Blessure au genou', photo: null, suspension: false },
    ]);
  }

  it('les rangs par identifiant d\'équipe ; la dernière rencontre vue de nos deux équipes ; les absents rangés', async () => {
    fournisseur();
    const d = await donneesAvantMatch(match);
    expect(d.classement).toEqual({ dom: { rang: 2, points: 17 }, ext: { rang: 5, points: 14 } });
    // Mars 2026 : Chelsea recevait, et l'a emporté 3-1.
    expect(d.h2h).toEqual({ joues: 2, dom: 1, ext: 0, nuls: 1,
      derniere: { date: '2026-03-01T16:30:00Z', recevait: 'ext', butsDom: 1, butsExt: 3 } });
    expect(d.absents).toEqual({
      dom: [{ nom: 'B. Saka', statut: 'incertain' }, { nom: 'D. Rice', statut: 'suspendu' }],
      ext: [{ nom: 'R. James', statut: 'absent' }],
    });
    expect(apiFootballService.getH2H).toHaveBeenCalledWith('Arsenal', 'Chelsea', '2026-10-25', 5, 99);
  });

  it('deux groupes différents (Coupe du monde) : pas de rangs', async () => {
    fournisseur({ classement: { status: 'available', season: 2026,
      rows: [ligne(42, 'Arsenal', 1, 9, 'A'), ligne(49, 'Chelsea', 2, 6, 'B')] } });
    expect((await donneesAvantMatch(match)).classement).toBeNull();
  });

  it('match inconnu du fournisseur : rien', async () => {
    fournisseur({ classement: { status: 'unavailable', rows: [], season: null }, h2h: null });
    jest.spyOn(apiFootballService, 'getFormeRecente').mockResolvedValue(null);
    expect(await donneesAvantMatch(match)).toBeNull();
  });
});

describe('la publication', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const service = require('../services/avant_matchs.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');

  const MAINTENANT = new Date(Date.UTC(2026, 9, 24, 12, 0, 0));
  const match = (id: string, heuresAvant: number, prono: boolean) => ({
    id, externalId: 1, homeTeam: 'Arsenal', awayTeam: 'Chelsea', league: 'Premier League', leagueCode: 'PL',
    matchDate: new Date(MAINTENANT.getTime() + heuresAvant * 3600_000), pronostic: prono ? { isPublished: true } : null,
  });
  let crees: any[], lecture: any;

  beforeEach(() => {
    crees = [];
    service._oublierEssais();
    jest.spyOn(prisma.resumeMatch, 'create').mockImplementation(async ({ data }: any) => { crees.push(data); return data; });
    jest.spyOn(apiFootballService, 'getStandings').mockResolvedValue({ status: 'available', season: 2026, rows: [
      { teamId: 42, teamName: 'Arsenal', rank: 2, points: 17, groupId: 'g', isMatchTeam: true },
      { teamId: 49, teamName: 'Chelsea', rank: 5, points: 14, groupId: 'g', isMatchTeam: true }] });
    jest.spyOn(apiFootballService, 'getFormeRecente').mockResolvedValue({ home: [recent('V', 1, 0, 'Fulham')], away: [recent('N', 0, 0, 'Spurs')] });
    jest.spyOn(apiFootballService, 'getH2H').mockResolvedValue(null);
    jest.spyOn(apiFootballService, 'getInjuries').mockResolvedValue(null);
  });
  afterEach(() => jest.restoreAllMocks());

  async function publier(matchs: any[], quand = MAINTENANT) {
    jest.spyOn(prisma.match, 'findMany').mockImplementation(async (args: any) => { lecture = args; return matchs; });
    return service.publierAvantMatchs(quand);
  }

  it('matchs pronostiqués ou des grandes compétitions, coup d\'envoi dans 1 h à 30 h, sans avant-match', async () => {
    expect(await publier([match('m1', 20, false)])).toEqual({ publies: 1 });
    expect(lecture.where).toEqual({
      status: 'SCHEDULED', source: 'API_FOOTBALL', articles: { none: { genre: 'avant_match' } },
      matchDate: { gt: new Date(MAINTENANT.getTime() + 3600_000), lte: new Date(MAINTENANT.getTime() + 30 * 3600_000) },
      OR: [
        { pronostic: { publicationRecordedAt: { not: null } } },
        { leagueCode: { in: ['PL', 'PD', 'SA', 'BL1', 'FL1', 'CL', 'WC'] } },
      ],
    });
    expect(lecture.orderBy).toEqual({ matchDate: 'asc' });
    expect(crees[0]).toMatchObject({ matchId: 'm1', genre: 'avant_match', ligue: 'Premier League',
      titre: 'Avant-match : Arsenal (2e) reçoit Chelsea (5e)' });
    expect(crees[0].resume).not.toContain('pronostic');
  });

  it('les matchs pronostiqués d\'abord, quatre par passage ; le pronostic publié est signalé', async () => {
    const sans = [1, 2, 3, 4].map(i => match(`g${i}`, 2 + i, false));
    expect(await publier([...sans, match('p1', 25, true)])).toEqual({ publies: 4 });
    expect(crees.map(c => c.matchId)).toEqual(['p1', 'g1', 'g2', 'g3']);
    expect(crees[0].resume).toContain('Le pronostic PronoWin de ce match est sur sa fiche.');
  });

  it('pas de quoi écrire : on réessaie deux heures plus tard, pas avant', async () => {
    const forme = jest.spyOn(apiFootballService, 'getFormeRecente').mockResolvedValue(null);
    expect(await publier([match('m1', 20, false)])).toEqual({ publies: 0 });
    await publier([match('m1', 20, false)], new Date(MAINTENANT.getTime() + 90 * 60_000));
    expect(forme).toHaveBeenCalledTimes(1);
    forme.mockResolvedValue({ home: [recent('V', 1, 0, 'Fulham')], away: [recent('N', 0, 0, 'Spurs')] });
    expect(await publier([match('m1', 18, false)], new Date(MAINTENANT.getTime() + 2 * 3600_000))).toEqual({ publies: 1 });
  });
});

describe('au format des actualités', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { avantMatchsPourActualites } = require('../services/avant_matchs.service');
  afterEach(() => jest.restoreAllMocks());

  it('jusqu\'au coup d\'envoi, sans ceux qu\'on a retirés ; type « resume_match » pour les versions installées, sans score', async () => {
    const maintenant = new Date('2026-10-24T12:00:00Z');
    const lecture = jest.spyOn(prisma.resumeMatch, 'findMany').mockResolvedValue([{
      id: 'a1', matchId: 'm1', genre: 'avant_match', titre: 'Avant-match : Arsenal (2e) reçoit Chelsea (5e)', titreEn: 'Preview', resume: 'R', resumeEn: 'R',
      ligue: 'Premier League', creeLe: new Date('2026-10-24T09:00:00Z'),
      match: { homeTeamLogo: 'https://media.api-sports.io/football/teams/42.png', awayTeamLogo: null, hasPublishedPronostic: false },
    }]);
    const [a] = await avantMatchsPourActualites(6, maintenant);
    expect((lecture.mock.calls[0][0] as any).where).toEqual({
      genre: 'avant_match', masque: false, match: { matchDate: { gt: maintenant }, status: 'SCHEDULED' } });
    expect(a).toMatchObject({ id: 'avant_match_a1', type: 'resume_match', genre: 'avant_match', match_id: 'm1',
      score: null, image_url: null, logo_domicile: 'https://media.api-sports.io/football/teams/42.png' });
  });
});
