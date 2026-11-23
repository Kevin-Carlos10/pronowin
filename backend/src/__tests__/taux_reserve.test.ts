/**
 * Le taux de réussite, réservé aux abonnés Premium (23 novembre 2026).
 *
 * Partout : l'accueil, la page Performance, le bilan du mur Premium et de la
 * vitrine. Un invité, un compte gratuit, un Premium échu ne reçoivent ni le
 * taux ni les comptes qui le donnent ; la série en cours, les publiés du jour
 * et les matchs à venir restent.
 */
jest.mock('../lib/prisma', () => ({ prisma: {
  user: { findUnique: jest.fn() },
  pronostic: { count: jest.fn(), findMany: jest.fn() },
} }));
jest.mock('../services/pronostics.service');
jest.mock('../services/notification.service');
jest.mock('../services/football_data.service');
jest.mock('../services/api_football.service', () => ({
  apiFootballService: {}, apiFootballInsights: {}, fichesJoueurs: {}, fichesEquipes: {},
  LEAGUE_INFO: () => null, saisonCourante: () => 2026,
}));
import { prisma } from '../lib/prisma';
import { PronosticsService } from '../services/pronostics.service';
import { cache, CACHE_KEYS } from '../services/cache.service';
import { getBilanPremium, getPerformance, getPublicStats } from '../controllers/pronostics.controller';
import { voitLeTaux } from '../services/taux_reserve';

const response = () => { const r: any = { json: jest.fn() }; r.status = jest.fn(() => r); return r; };
const demain = new Date(Date.now() + 86_400_000);
const hier   = new Date(Date.now() - 86_400_000);

const compte = (plan: string | null, echeance: Date | null = null) =>
  (prisma.user.findUnique as jest.Mock).mockResolvedValue(plan ? { subscriptionPlan: plan, subscriptionExpiresAt: echeance } : null);

beforeEach(() => {
  jest.clearAllMocks();
  cache.del(CACHE_KEYS.publicStats);
  cache.del(CACHE_KEYS.bilanPremium(30));
  (PronosticsService.prototype.getPublicStats as jest.Mock).mockResolvedValue(
    { winRate: 84, streak: 4, totalFinished: 50, wins: 42, publishedToday: 3, upcoming: 7 });
  // 17 gagnés, 3 perdus : 85 %, annonçable.
  (prisma.pronostic.count as jest.Mock).mockImplementation(async ({ where }: any) => where.result === 'WIN' ? 17 : 3);
  (prisma.pronostic.findMany as jest.Mock).mockResolvedValue([]);
});

describe('qui voit le taux', () => {
  it('un Premium en cours, ou sans échéance', async () => {
    compte('premium', demain); expect(await voitLeTaux('u')).toBe(true);
    compte('premium', null);   expect(await voitLeTaux('u')).toBe(true);
  });

  it('ni un invité, ni un compte gratuit, ni un Premium échu, ni un compte introuvable', async () => {
    expect(await voitLeTaux(undefined)).toBe(false);
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    compte('free');            expect(await voitLeTaux('u')).toBe(false);
    compte('premium', hier);   expect(await voitLeTaux('u')).toBe(false);
    compte(null);              expect(await voitLeTaux('u')).toBe(false);
  });
});

describe('les chiffres de l\'accueil', () => {
  it('compte gratuit : sans le taux ni ses comptes ; le reste demeure', async () => {
    compte('free');
    const r = response(); await getPublicStats({ userId: 'u' } as any, r);
    expect(r.json).toHaveBeenCalledWith(
      { winRate: null, streak: 4, totalFinished: null, wins: null, publishedToday: 3, upcoming: 7 });
  });

  it('Premium : tout ; et le cache partagé ne laisse pas fuir le taux vers le suivant', async () => {
    compte('premium', demain);
    const r = response(); await getPublicStats({ userId: 'p' } as any, r);
    expect(r.json.mock.calls[0][0]).toMatchObject({ winRate: 84, wins: 42, totalFinished: 50 });

    compte('free');
    const r2 = response(); await getPublicStats({ userId: 'u' } as any, r2);
    expect(r2.json.mock.calls[0][0]).toMatchObject({ winRate: null, wins: null, totalFinished: null });
    // Servi du cache : le service n'a calculé qu'une fois.
    expect(PronosticsService.prototype.getPublicStats).toHaveBeenCalledTimes(1);
  });
});

describe('la page Performance', () => {
  it('invité ou compte gratuit : refus Premium, et rien n\'est calculé', async () => {
    for (const req of [{}, { userId: 'u' }]) {
      compte('free');
      const r = response(); await getPerformance({ query: {}, ...req } as any, r);
      expect(r.status).toHaveBeenCalledWith(403);
      expect(r.json).toHaveBeenCalledWith(expect.objectContaining({ code: 'PREMIUM_REQUIRED' }));
    }
    expect(prisma.pronostic.findMany).not.toHaveBeenCalled();
  });

  it('Premium : le bilan', async () => {
    compte('premium', demain);
    const r = response(); await getPerformance({ query: {}, userId: 'p' } as any, r);
    expect(r.status).not.toHaveBeenCalled();
    expect(r.json.mock.calls[0][0]).toHaveProperty('win_rate');
  });
});

describe('le bilan du mur Premium et de la vitrine', () => {
  it('invité (la vitrine) ou compte gratuit : rien d\'annonçable, ni taux ni comptes', async () => {
    for (const req of [{}, { userId: 'u' }]) {
      compte('free');
      const r = response(); await getBilanPremium({ query: {}, ...req } as any, r);
      expect(r.json).toHaveBeenCalledWith(expect.objectContaining({
        affichable: false, taux_reussite: null, gagnes: null, perdus: null, pronostics_tranches: null,
        reserve_premium: true,
      }));
    }
    expect(prisma.pronostic.count).not.toHaveBeenCalled();
  });

  it('Premium : le bilan réel', async () => {
    compte('premium', demain);
    const r = response(); await getBilanPremium({ query: {}, userId: 'p' } as any, r);
    expect(r.json).toHaveBeenCalledWith(expect.objectContaining({ affichable: true, taux_reussite: 85, gagnes: 17 }));
  });
});
