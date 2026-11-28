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
  id: 'm1', homeTeam: 'Arsenal', awayTeam: 'Chelsea', status, source, externalId: 4242, homeScore: 1, awayScore: 0,
  matchDate: new Date(maintenant.getTime() + dansMin * 60_000),
});
const pari = (extra: Record<string, unknown> = {}, prefs: unknown = null, m = match()) => ({
  id: 'b1', stakedAmount: 1000, oddsUsed: 2, coteBookmaker: null, result: null, couvertureNotifieeLe: null,
  couvertureAlertes: 0, couvertureEnregistree: null,
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
  jest.spyOn(prisma.bankrollCombine, 'findMany').mockResolvedValue([]);
  jest.spyOn(prisma.bankrollCombine, 'updateMany').mockResolvedValue({ count: 1 });
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
    // La minute et le score du direct (27 novembre 2026).
    expect(message.body).toContain('Arsenal – Chelsea, 20e minute, 1-0');
    // L'autre façon de couvrir : récupérer sa mise.
    expect(message.body).toContain('Ou 334');
    expect(message.body).toContain('récupérer ta mise');
    expect(message.data).toEqual({ type: 'couverture', deep_link: '/pronostics/p1' });
    // L'action d'abord : sur l'écran verrouillé, seule la première ligne se lit.
    expect(message.body.startsWith('Mise 500')).toBe(true);
    expect(message.body).toContain('sur « Moins de 2,5 buts » à 4.00');
    // La mise concernée : plusieurs pronostics peuvent porter sur le même match.
    expect(message.body).toContain('Ta mise : « Plus de 2,5 buts »');
    expect(message.body).toContain('si ta sélection passe');
    // La seconde alerte de cette mise remplacera celle-ci sur le téléphone.
    expect(message.regroupement).toBe('couverture-b1');
    // Marquée avant l'envoi, et seulement si personne ne l'a fait entre-temps.
    const marque = (prisma.bankrollBet.updateMany as jest.Mock).mock.calls[0][0];
    expect(marque.where).toEqual({ id: 'b1', couvertureAlertes: 0 });
    // 50 % atteint, pas 80 % : la première alerte seulement.
    expect(marque.data.couvertureAlertes).toBe(1);
  });

  it('une seconde alerte quand la couverture atteint 80 % ; jamais une troisième', async () => {
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct(10) as any);   // 80 % du gain
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({ couvertureAlertes: 1 })] as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
    expect(envoi.mock.calls[0][1].title).toContain('Couverture encore meilleure');
    expect((prisma.bankrollBet.updateMany as jest.Mock).mock.calls[0][0].data.couvertureAlertes).toBe(2);

    // Déjà à 1 et toujours sous 80 % : rien de nouveau.
    envoi.mockClear();
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    (prisma.bankrollBet.findMany as jest.Mock).mockResolvedValue([pari({ couvertureAlertes: 1 })]);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(0);
  });

  it('un combiné qui n\'attend plus que sa dernière sélection : couvert contre son gain entier', async () => {
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([]);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    (prisma.bankrollCombine.findMany as jest.Mock).mockResolvedValue([{
      id: 'c1', stakedAmount: 500, result: null, couvertureAlertes: 0,
      bankroll: { currency: 'XOF', userId: 'u1', user: { notificationPrefs: null } },
      selections: [
        { id: 's1', pronosticId: 'px', cote: 2, result: 'WIN', annulee: false, pronostic: null },
        { id: 's2', pronosticId: 'p1', cote: 2, result: null, annulee: false, pronostic: pari().pronostic },
      ],
    }]);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
    const [, message] = envoi.mock.calls[0];
    // 500 F à 2 × 2 = 4 ; l'inverse à 4 : 500 F dessus, +1 000 F garantis.
    expect(message.title).toMatch(/^Couvre ton combiné : \+1\s000 .+ garantis$/);
    expect(message.data).toEqual({ type: 'couverture', deep_link: '/bankroll/combine/c1' });
    expect(message.body).toContain('Ton combiné n’attend plus que « Plus de 2,5 buts »');
    expect(message.body).toContain('si ton combiné passe');
    expect(message.regroupement).toBe('couverture-c1');
    expect((prisma.bankrollCombine.updateMany as jest.Mock).mock.calls[0][0].where).toEqual({ id: 'c1', couvertureAlertes: 0 });
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

  it('dans la dernière heure : une lecture toutes les dix minutes', async () => {
    const m = match('SCHEDULED', 50);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({}, null, m)] as any);
    const lecture = jest.spyOn(apiFootballService, 'getOdds1xBet').mockResolvedValue({
      source: '1xBet', options: [],
      markets: [{ name: 'Goals Over/Under', values: [{ value: 'Over 2.5', odd: 1.4 }, { value: 'Under 2.5', odd: 2.9 }] }],
    } as any);
    await surveillerCouvertures(maintenant, notif());
    await surveillerCouvertures(new Date(maintenant.getTime() + 9 * 60_000), notif());
    expect(lecture).toHaveBeenCalledTimes(1);
    await surveillerCouvertures(new Date(maintenant.getTime() + 11 * 60_000), notif());
    expect(lecture).toHaveBeenCalledTimes(2);
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

describe('le texte des alertes (27 novembre 2026)', () => {
  it('une ligne entière : pas de « quel que soit le résultat », le remboursement est dit', async () => {
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue(
      [pari({ pronostic: { ...pari().pronostic, marketValue: 'Over 2' } })] as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue({
      fixtureId: 4242, elapsed: 20, stale: false,
      markets: [{ key: 'over/under line', name: 'Plus/Moins', values: [{ value: 'Under', odd: 4, ligne: '2', labels: { fr: '', en: '' } }] }],
    } as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
    const [, message] = envoi.mock.calls[0];
    expect(message.title).toContain('sans perte possible');
    expect(message.title).not.toContain('garantis');
    expect(message.body).not.toContain('quel que soit le résultat');
    expect(message.body).toContain('ou les deux mises remboursées s\'il y a exactement 2 buts');
    expect(message.bodyEn).toContain('or both stakes refunded if there are exactly 2 goals');
  });

  it('avant le match : la notification le dit', async () => {
    const m = match('SCHEDULED', 90);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([pari({}, null, m)] as any);
    jest.spyOn(apiFootballService, 'getOdds1xBet').mockResolvedValue({
      source: '1xBet', options: [],
      markets: [{ name: 'Goals Over/Under', values: [{ value: 'Over 2.5', odd: 1.4 }, { value: 'Under 2.5', odd: 4.2 }] }],
    } as any);
    expect((await surveillerCouvertures(maintenant, notif())).alertes).toBe(1);
    const [, message] = envoi.mock.calls[0];
    expect(message.body).toContain('Arsenal – Chelsea, avant le match.');
    expect(message.bodyEn).toContain('Arsenal – Chelsea, before kick-off.');
  });
});

describe('la fiche : les deux façons de couvrir (27 novembre 2026)', () => {
  it('gain égal et mise remboursée, la mise à couvrir et sa couverture enregistrée', async () => {
    jest.spyOn(prisma.bankrollBet, 'findFirst').mockResolvedValue(pari() as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    expect(await couverturePourAbonne('u1', 'p1', maintenant)).toMatchObject({
      pari_id: 'b1', enregistree: null, minute: 20, remboursable: false, note_remboursement_fr: null,
      selection_fr: 'Plus de 2,5 buts',
      strategies: {
        gain_egal:       { mise: 500, gain_garanti: 500, si_selection: 500, si_inverse: 500 },
        mise_remboursee: { mise: 334, si_selection: 666, si_inverse: 2 },
      },
    });
  });

  it('une ligne entière : la fiche dit quand les deux mises sont remboursées', async () => {
    jest.spyOn(prisma.bankrollBet, 'findFirst').mockResolvedValue(
      pari({ pronostic: { ...pari().pronostic, marketValue: 'Over 2' } }) as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue({
      fixtureId: 4242, elapsed: 20, stale: false,
      markets: [{ key: 'over/under line', name: 'Plus/Moins', values: [{ value: 'Under', odd: 4, ligne: '2', labels: { fr: '', en: '' } }] }],
    } as any);
    expect(await couverturePourAbonne('u1', 'p1', maintenant)).toMatchObject({
      disponible: true, remboursable: true, inverse_fr: 'Moins de 2 buts',
      note_remboursement_fr: 'S’il y a exactement 2 buts, les deux mises sont remboursées : ni gain ni perte.'.replace('’', "'"),
    });
  });
});
