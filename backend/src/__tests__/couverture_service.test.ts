/**
 * L'alerte de couverture (26 novembre 2026) : une notification par mise, dès
 * que miser sur l'inverse garantit le seuil choisi du gain potentiel.
 */
import { prisma } from '../lib/prisma';
import { apiFootballInsights, apiFootballService } from '../services/api_football.service';
import {
  _oublierLecturesAvantMatch, couverturePourAbonne, surveillerCouvertures,
} from '../services/couverture.service';

const maintenant = new Date(Date.UTC(2026, 10, 26, 18, 0));
const match = (status = 'LIVE', dansMin = -20, source = 'API_FOOTBALL') => ({
  id: 'm1', homeTeam: 'Arsenal', awayTeam: 'Chelsea', status, source, externalId: 4242,
  matchDate: new Date(maintenant.getTime() + dansMin * 60_000),
});
const pari = (extra: Record<string, unknown> = {}, prefs: unknown = null, m = match()) => ({
  id: 'b1', stakedAmount: 1000, oddsUsed: 2, coteBookmaker: null, result: null, couvertureNotifieeLe: null,
  bankroll: { currency: 'XOF', userId: 'u1', user: { notificationPrefs: prefs } },
  pronostic: { id: 'p1', predictionType: 'other', marketName: 'Goals Over/Under', marketValue: 'Over 2.5', match: m },
  ...extra,
});
const direct = (sousLigne = 4.0) => ({
  fixtureId: 4242, elapsed: 20, stale: false,
  markets: [{ key: 'over/under line', name: 'Plus/Moins', values: [
    { value: 'Over', odd: 1.25, ligne: '2.5', labels: { fr: '', en: '' } },
    { value: 'Under', odd: sousLigne, ligne: '2.5', labels: { fr: '', en: '' } },
  ] }],
});

let envoi: jest.Mock;
const notif = () => ({ sendToUser: envoi }) as any;

beforeEach(() => {
  _oublierLecturesAvantMatch();
  envoi = jest.fn(async () => ({ success: true }));
  jest.spyOn(prisma.bankrollBet, 'updateMany').mockResolvedValue({ count: 1 });
});
afterEach(() => jest.restoreAllMocks());

describe('la surveillance', () => {
  it('en direct : Moins de 2,5 à 4,00 — « mise 500 F dessus, +500 F garantis », une fois', async () => {
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari()] as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);

    expect(await surveillerCouvertures(maintenant, notif())).toEqual({ examinees: 1, alertes: 1 });
    const [userId, message, categorie] = envoi.mock.calls[0];
    expect(userId).toBe('u1');
    expect(categorie).toBe('couverture');
    expect(message.title).toContain('+500');
    expect(message.body).toContain('Moins de 2,5 buts');
    expect(message.body).toContain('Mise 500');
    expect(message.body).toContain('Vérifie la cote proposée avant de miser');
    expect(message.data).toEqual({ type: 'couverture', deep_link: '/pronostics/p1' });
    // Marquée avant l'envoi, et seulement si personne ne l'a fait entre-temps.
    expect((prisma.bankrollBet.updateMany as jest.Mock).mock.calls[0][0].where).toEqual({ id: 'b1', couvertureNotifieeLe: null });
  });

  it('sous le seuil, pas d\'alerte ; au seuil de 30 % choisi, si', async () => {
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct(3.5) as any);   // 43 % du gain
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari()] as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(0);
    (prisma.bankrollBet.findMany as jest.Mock).mockResolvedValue([pari({}, { seuil_couverture: 30 })]);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
  });

  it('la cote obtenue chez le bookmaker compte : à 2,40, le même mouvement atteint la moitié', async () => {
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct(3.5) as any);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({ coteBookmaker: 2.4 })] as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
  });

  it('alertes coupées dans les réglages, ou déjà envoyée par un autre passage : rien', async () => {
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({}, { couverture: false })] as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(0);

    (prisma.bankrollBet.findMany as jest.Mock).mockResolvedValue([pari()]);
    (prisma.bankrollBet.updateMany as jest.Mock).mockResolvedValue({ count: 0 });
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(0);
    expect(envoi).not.toHaveBeenCalled();
  });

  it('avant le match : une lecture par demi-heure, dans les six dernières heures', async () => {
    const m = match('SCHEDULED', 90);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({}, null, m)] as any);
    const lecture = jest.spyOn(apiFootballService, 'getOdds1xBet').mockResolvedValue({
      source: '1xBet', options: [],
      markets: [{ name: 'Goals Over/Under', values: [{ value: 'Over 2.5', odd: 1.4 }, { value: 'Under 2.5', odd: 2.9 }] }],
    } as any);
    await surveillerCouvertures(maintenant, notif());
    await surveillerCouvertures(new Date(maintenant.getTime() + 10 * 60_000), notif());
    expect(lecture).toHaveBeenCalledTimes(1);
    await surveillerCouvertures(new Date(maintenant.getTime() + 31 * 60_000), notif());
    expect(lecture).toHaveBeenCalledTimes(2);
  });

  it('un match d\'une autre source : son identifiant n\'est pas celui d\'API-Football', async () => {
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({}, null, match('LIVE', -20, 'FOOTBALL_DATA'))] as any);
    const live = jest.spyOn(apiFootballInsights, 'getLiveOdds');
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(0);
    expect(live).not.toHaveBeenCalled();
  });
});

describe('la fiche du match', () => {
  it('la couverture de sa mise, maintenant', async () => {
    jest.spyOn(prisma.bankrollBet, 'findFirst').mockResolvedValue(pari() as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    expect(await couverturePourAbonne('u1', 'p1', maintenant)).toMatchObject({
      disponible: true, mise: 1000, cote: 2, devise: 'XOF', seuil: 50,
      inverse_fr: 'Moins de 2,5 buts', cote_inverse: 4, mise_couverture: 500, gain_garanti: 500,
      gain_potentiel: 1000, seuil_atteint: true, source: 'direct',
    });
  });

  it('sans mise, sans marché couvrable, sans cote : dit pourquoi', async () => {
    jest.spyOn(prisma.bankrollBet, 'findFirst').mockResolvedValue(null);
    expect(await couverturePourAbonne('u1', 'p1', maintenant)).toEqual({ disponible: false, raison: 'aucune_mise' });

    (prisma.bankrollBet.findFirst as jest.Mock).mockResolvedValue(
      pari({ pronostic: { ...pari().pronostic, marketName: 'Exact Score', marketValue: '2:1' } }));
    expect(await couverturePourAbonne('u1', 'p1', maintenant)).toMatchObject({ disponible: false, raison: 'marche' });

    (prisma.bankrollBet.findFirst as jest.Mock).mockResolvedValue(pari());
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(null);
    expect(await couverturePourAbonne('u1', 'p1', maintenant))
      .toMatchObject({ disponible: false, raison: 'cote', inverse_fr: 'Moins de 2,5 buts', mise: 1000 });
  });
});
