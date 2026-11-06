/**
 * Alertes des matchs suivis, au complet comme sur Sofascore (20 octobre 2026) :
 * mi-temps, cartons rouges et compositions officielles, en plus du coup
 * d'envoi, des buts et du résultat.
 */
import {
  messageCartonRouge, messageMiTemps, releverEvenements, _oublierEtatsDuDirect,
} from '../services/alertes_direct';
import type { AFFixture } from '../services/api_football.service';

const T0 = Date.UTC(2026, 9, 20, 15, 0, 0);
type Rouge = [minute: number, camp: 'dom' | 'ext', joueur: string, detail?: string];

function rencontre(statut: string, score: [number, number], rouges: Rouge[] = []): AFFixture {
  return {
    fixture: { id: 1, date: '2026-10-20T14:00:00+00:00', status: { short: statut, elapsed: statut === 'HT' ? 45 : 30, extra: null } },
    league: { id: 39, name: 'Premier League', logo: null },
    teams: { home: { id: 42, name: 'Arsenal', logo: null }, away: { id: 49, name: 'Chelsea', logo: null } },
    goals: { home: score[0], away: score[1] },
    events: [
      { time: { elapsed: 12, extra: null }, team: { id: 42 }, player: { name: 'B. Saka' }, type: 'Card', detail: 'Yellow Card' },
      ...rouges.map(([m, c, j, d]) => ({
        time: { elapsed: m, extra: null }, team: { id: c === 'dom' ? 42 : 49 }, player: { name: j }, type: 'Card', detail: d ?? 'Red Card' })),
    ],
  };
}
const equipes = { dom: 'Arsenal', ext: 'Chelsea' };

describe('mi-temps et cartons rouges dans le direct', () => {
  beforeEach(() => _oublierEtatsDuDirect());

  it('premier relevé : référence, rien d\'annoncé', () => {
    expect(releverEvenements([rencontre('HT', [1, 0], [[30, 'ext', 'R. James']])], T0).size).toBe(0);
  });

  it('la pause sonne : mi-temps annoncée une fois', () => {
    releverEvenements([rencontre('1H', [1, 0])], T0);
    const c = releverEvenements([rencontre('HT', [1, 0])], T0 + 15_000);
    expect(c.get(1)).toMatchObject({ miTemps: true, rouges: [] });
    expect(releverEvenements([rencontre('HT', [1, 0])], T0 + 30_000).size).toBe(0);
    // La reprise n'est pas une mi-temps.
    expect(releverEvenements([rencontre('2H', [1, 0])], T0 + 45_000).size).toBe(0);
  });

  it('un carton rouge apparaît : lui seul, pas les cartons jaunes', () => {
    releverEvenements([rencontre('2H', [1, 0])], T0);
    const c = releverEvenements([rencontre('2H', [1, 0], [[54, 'ext', 'R. James']])], T0 + 15_000);
    expect(c.get(1)!.rouges.map(e => e.player?.name)).toEqual(['R. James']);
    expect(releverEvenements([rencontre('2H', [1, 0], [[54, 'ext', 'R. James']])], T0 + 30_000).size).toBe(0);
  });

  it('les textes, en français et en anglais', () => {
    const f = rencontre('2H', [1, 0], [[54, 'ext', 'R. James'], [70, 'dom', 'D. Rice', 'Second Yellow card']]);
    expect(messageMiTemps(rencontre('HT', [1, 0]), equipes, 'fr')).toEqual({ title: 'Mi-temps', body: 'Arsenal 1-0 Chelsea' });
    expect(messageMiTemps(rencontre('HT', [1, 0]), equipes, 'en').title).toBe('Half-time');
    expect(messageCartonRouge(f, f.events![1], equipes, 'fr'))
      .toEqual({ title: 'Carton rouge pour Chelsea', body: 'R. James 54\' · Arsenal 1-0 Chelsea' });
    expect(messageCartonRouge(f, f.events![2], equipes, 'fr').body).toBe('D. Rice (2e jaune) 70\' · Arsenal 1-0 Chelsea');
    expect(messageCartonRouge(f, f.events![2], equipes, 'en'))
      .toEqual({ title: 'Red card for Arsenal', body: 'D. Rice (second yellow) 70\' · Arsenal 1-0 Chelsea' });
  });
});

describe('dans la synchronisation des scores', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { NotificationService } = require('../services/notification.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { PronosticsService, _oublierDirectPrecedent } = require('../services/pronostics.service');

  let envois: any[];
  beforeEach(() => {
    _oublierDirectPrecedent();
    envois = [];
    jest.spyOn(NotificationService.prototype, 'sendToUser').mockImplementation(async (...a: any[]) => {
      envois.push({ userId: a[0], ...a[1] }); return { success: true };
    });
    jest.spyOn(prisma.match, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue({
      id: 'm1', externalId: 1, status: 'LIVE', homeTeam: 'Arsenal', awayTeam: 'Chelsea',
      homeScore: 1, awayScore: 0, homeScoreHT: null, awayScoreHT: null, elapsedMinutes: 30,
      matchDate: new Date('2026-10-20T14:00:00+00:00') });
    jest.spyOn(prisma.match, 'update').mockResolvedValue({});
    jest.spyOn(prisma.pronostic, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue({ id: 'p1' });
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([{ userId: 'u1' }]);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([]);
  });
  afterEach(() => jest.restoreAllMocks());

  async function cycle(f: AFFixture) {
    jest.spyOn(apiFootballService, 'getLiveFixtures').mockResolvedValue([f]);
    jest.spyOn(apiFootballService, 'getAllLiveAndRecentFixtures').mockResolvedValue([f]);
    await new PronosticsService().syncMatchScores();
  }

  it('carton rouge puis mi-temps : une alerte chacun, vers la fiche', async () => {
    await cycle(rencontre('1H', [1, 0]));
    await cycle(rencontre('1H', [1, 0], [[40, 'ext', 'R. James']]));
    await cycle(rencontre('HT', [1, 0], [[40, 'ext', 'R. James']]));
    expect(envois.map(e => e.title)).toEqual(['Carton rouge pour Chelsea', 'Mi-temps']);
    expect(envois[1]).toMatchObject({ body: 'Arsenal 1-0 Chelsea', titleEn: 'Half-time',
      data: { type: 'match', deep_link: '/pronostics/p1' } });
  });
});

describe('compositions officielles', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { annoncerCompositions, _oublierCompositionsAnnoncees } = require('../services/alertes_compositions.service');

  const MAINTENANT = new Date(Date.UTC(2026, 9, 20, 18, 0, 0));
  let envois: any[];
  let lecture: any;
  const notifSvc = { sendToUser: async (userId: string, p: any) => { envois.push({ userId, ...p }); return {}; } } as any;
  const compo = (available: boolean) => ({ available,
    home: available ? { formation: '4-3-3' } : null, away: available ? { formation: '4-2-3-1' } : null });

  beforeEach(() => {
    _oublierCompositionsAnnoncees();
    envois = [];
    jest.spyOn(prisma.match, 'findMany').mockImplementation(async (a: any) => { lecture = a; return [{
      id: 'm1', externalId: 7, homeTeam: 'Arsenal', awayTeam: 'Chelsea',
      matchDate: new Date(MAINTENANT.getTime() + 55 * 60_000), pronostic: { id: 'p1' } }]; });
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue(null);
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([{ userId: 'u1' }]);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([{ bankroll: { userId: 'u2' } }]);
  });
  afterEach(() => jest.restoreAllMocks());

  it('pas encore publiées : rien ; publiées : une alerte par suiveur, une seule fois', async () => {
    const lineups = jest.spyOn(apiFootballService, 'getLineups').mockResolvedValue(compo(false));
    expect(await annoncerCompositions(MAINTENANT, notifSvc)).toEqual({ annonces: 0 });
    expect(envois).toEqual([]);
    // Seuls les matchs suivis qui commencent dans l'heure sont lus.
    expect(lecture.where.matchDate).toEqual({
      gte: new Date(MAINTENANT.getTime() - 10 * 60_000), lte: new Date(MAINTENANT.getTime() + 65 * 60_000) });
    expect(lecture.where.OR).toHaveLength(2);

    lineups.mockResolvedValue(compo(true));
    expect(await annoncerCompositions(MAINTENANT, notifSvc)).toEqual({ annonces: 1 });
    expect(envois.map(e => e.userId).sort()).toEqual(['u1', 'u2']);
    expect(envois[0]).toMatchObject({
      title: 'Compositions officielles',
      body: 'Arsenal (4-3-3) – Chelsea (4-2-3-1) : les onze de départ sont connus.',
      titleEn: 'Official line-ups',
      data: { type: 'match', deep_link: '/pronostics/p1', match_id: 'm1' },
    });
    expect(await annoncerCompositions(MAINTENANT, notifSvc)).toEqual({ annonces: 0 });
    expect(envois).toHaveLength(2);
  });

  it('déjà annoncées avant un redémarrage : l\'historique des notifications fait foi, sans appel', async () => {
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue({ id: 'n1' });
    const lineups = jest.spyOn(apiFootballService, 'getLineups').mockResolvedValue(compo(true));
    expect(await annoncerCompositions(MAINTENANT, notifSvc)).toEqual({ annonces: 0 });
    expect(lineups).not.toHaveBeenCalled();
  });
});
