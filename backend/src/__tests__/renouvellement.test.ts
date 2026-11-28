/**
 * Renouveler en un geste (23 novembre 2026) : le rappel d'échéance mène à
 * l'étape de paiement de la formule de l'abonné, plus à l'onglet Compte.
 */
import { prisma } from '../lib/prisma';
import { NotificationService } from '../services/notification.service';
import { SubscriptionService } from '../services/subscription.service';
import { derniersAbonnements, formuleDe, lienRenouvellement } from '../services/renouvellement.service';

const jour = 86_400_000;
const t0 = new Date('2026-11-01T00:00:00Z');
const apres = (j: number) => new Date(t0.getTime() + j * jour);

afterEach(() => jest.restoreAllMocks());

describe('la formule et son lien', () => {
  it('30 jours : le mois ; 365 jours : l\'année', () => {
    expect(formuleDe(t0, apres(30))).toBe('premium_monthly');
    expect(formuleDe(t0, apres(31))).toBe('premium_monthly');
    expect(formuleDe(t0, apres(365))).toBe('premium_annual');
  });

  it('le lien mène au paiement de la formule ; à l\'offre si on l\'ignore', () => {
    expect(lienRenouvellement('premium_annual')).toBe('/compte/activer-premium?renouveler=premium_annual');
    expect(lienRenouvellement(null)).toBe('/compte/activer-premium');
  });

  it('le dernier abonnement de chacun, en une requête ; une boutique se reconnaît', async () => {
    const requete = jest.spyOn(prisma.subscription, 'findMany').mockResolvedValue([
      { userId: 'a', startDate: apres(365), endDate: apres(395), paymentMethod: 'geniuspay' },
      { userId: 'a', startDate: t0, endDate: apres(365), paymentMethod: 'orange_money' },
      { userId: 'b', startDate: t0, endDate: apres(30), paymentMethod: 'iap_apple' },
    ] as any);
    const derniers = await derniersAbonnements(['a', 'b']);
    expect(derniers.get('a')).toEqual({ formule: 'premium_monthly', boutique: false });
    expect(derniers.get('b')).toEqual({ formule: 'premium_monthly', boutique: true });
    expect(requete.mock.calls[0][0]).toMatchObject({
      where: { userId: { in: ['a', 'b'] }, plan: 'premium' }, orderBy: { endDate: 'desc' } });
    expect(await derniersAbonnements([])).toEqual(new Map());
  });
});

describe('le rappel avant l\'échéance', () => {
  it('lien vers le paiement de la formule ; rien pour un abonnement de boutique', async () => {
    const envois: any[] = [];
    jest.spyOn(NotificationService.prototype, 'sendToUser').mockImplementation(async (...a: any[]) => {
      envois.push({ userId: a[0], ...a[1] }); return { success: true } as any;
    });
    // Un seul palier a des comptes : « a » (Mobile Money, à l'année) et
    // « b » (App Store, que la boutique renouvelle elle-même).
    jest.spyOn(prisma.user, 'findMany')
      .mockResolvedValueOnce([{ id: 'a' }, { id: 'b' }] as any)
      .mockResolvedValue([] as any);
    jest.spyOn(prisma.subscription, 'findMany').mockResolvedValue([
      { userId: 'a', startDate: t0, endDate: apres(365), paymentMethod: 'geniuspay' },
      { userId: 'b', startDate: t0, endDate: apres(30), paymentMethod: 'iap_apple' },
    ] as any);
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue(null);

    expect(await new SubscriptionService().notifyExpiringSubscriptions()).toEqual({ notified: 1 });
    expect(envois).toEqual([expect.objectContaining({
      userId: 'a',
      data: { deep_link: '/compte/activer-premium?renouveler=premium_annual', type: 'premium' },
    })]);
    expect(envois[0].body).toContain('en un geste');
  });
});
