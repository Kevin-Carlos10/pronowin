/**
 * Un pronostic Premium reste Premium après le match (décision de
 * l'utilisateur du 17 octobre 2026, option « visible mais verrouillé »).
 *
 * Le non-abonné voit dans l'historique qu'il y a eu un pronostic Premium et
 * son résultat — gagné comme perdu —, mais ni le choix, ni la cote, ni la
 * confiance. L'analyse et les commentaires d'un pronostic Premium restent
 * réservés aux abonnés après le coup de sifflet ; ceux d'un pronostic gratuit
 * s'ouvrent à tous.
 */
jest.mock('../lib/prisma', () => ({
  prisma: {
    user:      { findUnique: jest.fn() },
    pronostic: { findMany: jest.fn(), findUnique: jest.fn() },
    match:     { findUnique: jest.fn() },
  },
}));

import { prisma } from '../lib/prisma';
import { getHistory, LIBELLE_PREMIUM_VERROUILLE } from '../controllers/pronostics.controller';
import { premiumSaufMatchTermine } from '../middleware/auth.middleware';

const match = {
  id: 'm', league: 'Premier League', leagueCode: 'PL', homeTeam: 'Brentford', awayTeam: 'Liverpool',
  homeTeamLogo: null, awayTeamLogo: null, homeScore: 0, awayScore: 2, matchDate: new Date('2026-10-17T14:00:00Z'),
};
const prono = (id: string, isPremium: boolean, result: string) => ({
  id, isPublished: true, publicationRecordedAt: new Date('2026-10-17T10:00:00Z'),
  predictionLabel: 'Liverpool gagne', predictionType: 'win2', oddsRecommended: 1.62,
  confidenceScore: 4, confidencePct: 75, isPremium, result, match,
});
const historique = [
  prono('vip-gagne', true, 'WIN'),
  prono('vip-perdu', true, 'LOSS'),
  prono('gratuit', false, 'LOSS'),
];

const abonne = { subscriptionPlan: 'premium', subscriptionExpiresAt: new Date(Date.now() + 86_400_000) };
const gratuit = { subscriptionPlan: 'free', subscriptionExpiresAt: null };

function reponse() {
  const r: any = { statut: 200, corps: undefined };
  r.status = jest.fn((c: number) => { r.statut = c; return r; });
  r.json = jest.fn((c: any) => { r.corps = c; return r; });
  return r;
}

describe('historique des pronostics Premium', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (prisma.pronostic.findMany as jest.Mock).mockResolvedValue(historique);
  });

  it('non-abonné : tous les résultats, mais aucun choix Premium', async () => {
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(gratuit);
    const res = reponse();
    await getHistory({ userId: 'u', query: {} } as any, res);
    const parId = Object.fromEntries(res.corps.map((e: any) => [e.id, e]));

    // Gagné comme perdu : rien n'est retiré de l'historique.
    expect(res.corps.map((e: any) => [e.id, e.result])).toEqual([
      ['vip-gagne', 'WIN'], ['vip-perdu', 'LOSS'], ['gratuit', 'LOSS'],
    ]);
    for (const id of ['vip-gagne', 'vip-perdu']) {
      expect(parId[id]).toMatchObject({
        locked: true, isPremium: true,
        predictionLabel: LIBELLE_PREMIUM_VERROUILLE, predictionType: null,
        oddsRecommended: null, confidenceScore: null, confidencePct: null,
      });
      expect(JSON.stringify(parId[id])).not.toContain('Liverpool gagne');
    }
    expect(parId.gratuit).toMatchObject({ locked: false, predictionLabel: 'Liverpool gagne', oddsRecommended: 1.62 });
  });

  it('invité : même historique verrouillé', async () => {
    const res = reponse();
    await getHistory({ query: {} } as any, res);
    expect(res.corps.filter((e: any) => e.locked).map((e: any) => e.id)).toEqual(['vip-gagne', 'vip-perdu']);
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });

  it('abonné : tout en clair', async () => {
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(abonne);
    const res = reponse();
    await getHistory({ userId: 'u', query: {} } as any, res);
    expect(res.corps.every((e: any) => e.locked === false && e.predictionLabel === 'Liverpool gagne')).toBe(true);
  });
});

describe('analyse et commentaires après le match', () => {
  beforeEach(() => jest.clearAllMocks());

  async function passer(pronostic: any, utilisateur: any) {
    (prisma.pronostic.findUnique as jest.Mock).mockResolvedValue(pronostic);
    (prisma.user.findUnique as jest.Mock).mockResolvedValue(utilisateur);
    const res = reponse();
    const next = jest.fn();
    await premiumSaufMatchTermine({ params: { id: 'p' }, userId: 'u' } as any, res, next);
    return { ouvert: next.mock.calls.length === 1, statut: res.statut };
  }

  it('pronostic gratuit terminé : ouvert à tous', async () => {
    expect((await passer({ isPremium: false, match: { status: 'FINISHED' } }, gratuit)).ouvert).toBe(true);
  });

  it('pronostic Premium terminé : réservé aux abonnés', async () => {
    expect(await passer({ isPremium: true, match: { status: 'FINISHED' } }, gratuit)).toEqual({ ouvert: false, statut: 403 });
    expect((await passer({ isPremium: true, match: { status: 'FINISHED' } }, abonne)).ouvert).toBe(true);
  });

  it('avant le match : réservé aux abonnés, gratuit ou non', async () => {
    expect((await passer({ isPremium: false, match: { status: 'SCHEDULED' } }, gratuit)).statut).toBe(403);
  });
});
