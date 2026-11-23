/**
 * Relancer les abonnés dont le Premium a expiré (15 novembre 2026) : après
 * l'échéance, rien ne rappelait de renouveler.
 */
import { prisma } from '../lib/prisma';
import { NotificationService } from '../services/notification.service';
import * as config from '../services/app_config.service';
import {
  apercuRelance, relancerAutomatiquement, relancerExpires, MESSAGE_RELANCE, TYPE_RELANCE_PREMIUM,
} from '../services/relance_premium.service';

const maintenant = new Date('2026-11-15T09:00:00Z');
const ilYa = (jours: number) => new Date(maintenant.getTime() - jours * 86_400_000);

let envois: any[];
beforeEach(() => {
  envois = [];
  jest.spyOn(NotificationService.prototype, 'sendToUser').mockImplementation(async (...a: any[]) => {
    envois.push({ userId: a[0], ...a[1], categorie: a[2] }); return { success: true } as any;
  });
  jest.spyOn(config, 'lireConfig').mockResolvedValue({ valeurs: { PROMO_CODE: 'PRONOWIN2026' } } as any);
  // Le dernier abonnement de chacun : « a » au mois, « b » à l'année.
  jest.spyOn(prisma.subscription, 'findMany').mockResolvedValue([
    { userId: 'a', startDate: ilYa(33), endDate: ilYa(3), paymentMethod: 'orange_money' },
    { userId: 'b', startDate: ilYa(370), endDate: ilYa(5), paymentMethod: 'geniuspay' },
  ] as any);
});
afterEach(() => jest.restoreAllMocks());

describe('la relance automatique', () => {
  it('3 à 10 jours après l\'échéance, une fois : déjà relancé depuis, on passe', async () => {
    const comptes = jest.spyOn(prisma.user, 'findMany').mockResolvedValue([
      { id: 'a', subscriptionExpiresAt: ilYa(3) }, { id: 'b', subscriptionExpiresAt: ilYa(5) },
    ] as any);
    jest.spyOn(prisma.notification, 'findFirst').mockImplementation((async (args: any) =>
      args.where.userId === 'b' ? { id: 'n' } : null) as any);
    expect(await relancerAutomatiquement(maintenant)).toEqual({ notified: 1 });

    const ou = comptes.mock.calls[0][0]!.where as any;
    expect(ou).toMatchObject({ isActive: true, deletedAt: null, subscriptionPlan: 'premium' });
    expect(ou.subscriptionExpiresAt).toEqual({ lte: ilYa(3), gt: ilYa(10) });
    // « Depuis l'échéance » : une relance d'avant ne compte pas.
    expect((prisma.notification.findFirst as jest.Mock).mock.calls[0][0].where)
      .toEqual({ userId: 'a', type: TYPE_RELANCE_PREMIUM, createdAt: { gte: ilYa(3) } });

    expect(envois).toEqual([expect.objectContaining({
      userId: 'a', title: MESSAGE_RELANCE.fr.title, titleEn: MESSAGE_RELANCE.en.title,
      // Droit à l'étape de paiement de sa formule (renouveler en un geste).
      data: { deep_link: '/compte/activer-premium?renouveler=premium_monthly', type: TYPE_RELANCE_PREMIUM },
      categorie: 'premium',
    })]);
    // Pas de code promo dans la relance automatique.
    expect(envois[0].body).not.toContain('PRONOWIN2026');
  });
});

describe('la relance depuis l\'administration', () => {
  beforeEach(() => {
    jest.spyOn(prisma.user, 'count').mockImplementation((async (args: any) =>
      args.where.notifications ? 2 : args.where.appareils ? 9 : 12) as any);
    jest.spyOn(prisma.user, 'findMany').mockResolvedValue([{ id: 'a' }, { id: 'b' }] as any);
  });

  it('l\'aperçu : échus, joignables, déjà relancés dans la semaine, et le code disponible', async () => {
    expect(await apercuRelance(maintenant)).toEqual({
      expires: 12, joignables: 9, recemment: 2, a_relancer: 7, code_promo: 'PRONOWIN2026',
      titre: MESSAGE_RELANCE.fr.title, message: MESSAGE_RELANCE.fr.body,
    });
    const ou = (prisma.user.count as jest.Mock).mock.calls[0][0].where;
    expect(ou).toMatchObject({ isActive: true, deletedAt: null, subscriptionPlan: 'premium',
      subscriptionExpiresAt: { lte: maintenant } });
  });

  it('le texte par défaut, avec le code promo : en français et en anglais', async () => {
    expect(await relancerExpires({ avec_code: true }, maintenant))
      .toEqual({ sent: 2, failed: 0, skipped: 2, total: 4, avec_code: true });
    expect(envois.map(e => e.userId)).toEqual(['a', 'b']);
    expect(envois.map(e => e.data.deep_link)).toEqual([
      '/compte/activer-premium?renouveler=premium_monthly', '/compte/activer-premium?renouveler=premium_annual']);
    expect(envois[0].body).toBe(`${MESSAGE_RELANCE.fr.body} Code promo : PRONOWIN2026`);
    expect(envois[0].bodyEn).toBe(`${MESSAGE_RELANCE.en.body} Promo code: PRONOWIN2026`);
    expect(envois[0].categorie).toBe('premium');
    // Ni ceux relancés dans les 7 jours, ni ceux sans appli installée.
    const ou = (prisma.user.findMany as jest.Mock).mock.calls[0][0].where;
    expect(ou.appareils).toEqual({ some: {} });
    expect(ou.notifications.none).toEqual({ type: TYPE_RELANCE_PREMIUM, createdAt: { gte: ilYa(7) } });
  });

  it('un texte écrit à la main part tel quel, sans traduction inventée', async () => {
    await relancerExpires({ titre: '  Reviens !  ', message: 'Le Premium t\u2019attend.' }, maintenant);
    expect(envois[0]).toMatchObject({ title: 'Reviens !', body: 'Le Premium t\u2019attend.' });
    expect(envois[0].titleEn).toBeUndefined();
    expect(envois[0].bodyEn).toBeUndefined();
  });

  it('refusé : un texte trop long, ou le code demandé sans code configuré', async () => {
    await expect(relancerExpires({ titre: 'x'.repeat(81) }, maintenant)).rejects.toMatchObject({ statut: 422 });
    await expect(relancerExpires({ message: 42 }, maintenant)).rejects.toMatchObject({ statut: 422 });
    (config.lireConfig as jest.Mock).mockResolvedValue({ valeurs: { PROMO_CODE: '' } });
    await expect(relancerExpires({ avec_code: true }, maintenant)).rejects.toMatchObject({ statut: 422 });
    expect(envois).toEqual([]);
  });
});
