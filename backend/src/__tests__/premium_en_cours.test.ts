/**
 * Premium en cours : une seule règle, celle qui ouvre l'accès (14 novembre
 * 2026).
 *
 * Le filtre « Premium » de la liste des utilisateurs du panneau ne lisait que
 * le plan. Aucune tâche ne repasse en `free` un abonnement échu : un compte
 * expiré depuis des semaines restait donc dans le filtre, affiché « Gratuit »
 * sur sa propre ligne. Et les compteurs oubliaient les Premium sans échéance,
 * que `premiumMiddleware` et l'application, eux, traitent en Premium.
 */
jest.mock('../lib/prisma', () => ({ prisma: { transaction: { groupBy: jest.fn(async () => []) } } }));

import { premiumEnCours, filtrePremiumEnCours, filtreSansPremium, filtrePremiumEchu } from '../utils/premium';
import { UsersAdminService } from '../services/users_admin.service';

const maintenant = new Date('2026-11-14T10:00:00Z');
const hier = new Date('2026-11-13T10:00:00Z');
const demain = new Date('2026-11-15T10:00:00Z');

describe('la règle', () => {
  it('Premium : plan premium et échéance future, ou sans échéance', () => {
    expect(premiumEnCours({ subscriptionPlan: 'premium', subscriptionExpiresAt: demain }, maintenant)).toBe(true);
    expect(premiumEnCours({ subscriptionPlan: 'premium', subscriptionExpiresAt: null }, maintenant)).toBe(true);
  });

  it('échu ou gratuit : pas Premium', () => {
    expect(premiumEnCours({ subscriptionPlan: 'premium', subscriptionExpiresAt: hier }, maintenant)).toBe(false);
    expect(premiumEnCours({ subscriptionPlan: 'free', subscriptionExpiresAt: demain }, maintenant)).toBe(false);
  });

  it('les filtres Prisma disent la même chose', () => {
    expect(filtrePremiumEnCours(maintenant)).toEqual({
      subscriptionPlan: 'premium',
      OR: [{ subscriptionExpiresAt: null }, { subscriptionExpiresAt: { gt: maintenant } }],
    });
    expect(filtreSansPremium(maintenant)).toEqual({ NOT: filtrePremiumEnCours(maintenant) });
    expect(filtrePremiumEchu(maintenant)).toEqual({ subscriptionPlan: 'premium', subscriptionExpiresAt: { lte: maintenant } });
  });
});

describe('le filtre « plan » de la liste du panneau', () => {
  const svc = new UsersAdminService();
  beforeAll(() => { jest.useFakeTimers({ now: maintenant }); });
  afterAll(() => { jest.useRealTimers(); });

  it('« premium » lit l\'échéance, plus seulement le drapeau', async () => {
    const where = await svc.filtreUtilisateurs({ plan: 'premium' });
    expect(where.subscriptionPlan).toBeUndefined();
    expect(where.AND).toEqual([filtrePremiumEnCours(maintenant)]);
  });

  it('« free » compte aussi les Premium échus ; « expire » ne garde qu\'eux', async () => {
    expect((await svc.filtreUtilisateurs({ plan: 'free' })).AND).toEqual([filtreSansPremium(maintenant)]);
    expect((await svc.filtreUtilisateurs({ plan: 'expire' })).AND).toEqual([filtrePremiumEchu(maintenant)]);
  });

  it('la recherche garde son OR à côté du plan', async () => {
    const where = await svc.filtreUtilisateurs({ plan: 'premium', search: 'kone' });
    expect(where.OR).toHaveLength(6);
    expect(where.AND).toHaveLength(1);
  });

  it('un plan inconnu ne filtre rien', async () => {
    expect((await svc.filtreUtilisateurs({ plan: 'vip' })).AND).toBeUndefined();
  });
});
