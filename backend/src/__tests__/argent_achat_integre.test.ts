/**
 * L'achat intégré : un remboursement doit fermer l'accès, et un octroi doit
 * être entier ou ne pas avoir lieu.
 *
 * ── Le remboursé qui garde tout ────────────────────────────────────────────
 *
 * Quand Apple rembourse un abonné, le reçu revient avec le statut `revoked` :
 * la personne a récupéré son argent. `_revokeIfExpired` refusait pourtant de
 * retirer l'accès, à cause de ce garde-fou :
 *
 *     if (user.subscriptionExpiresAt > new Date()) return;
 *
 * Son intention était juste — ne pas couper quelqu'un qui a *aussi* payé par
 * Mobile Money, une échéance qui ne regarde pas le store. Mais `grantPremium`
 * écrit `subscriptionExpiresAt` avec la date **du store** : après un achat
 * intégré, cette date est toujours dans le futur. La condition était donc
 * vraie pour exactement les gens qu'elle devait laisser révoquer, et fausse
 * pour personne d'autre. Une protection dont la condition d'activation ne
 * distinguait rien.
 *
 * Résultat : rembourser son abonnement rendait l'argent **et** conservait le
 * Premium jusqu'au terme payé. Le remboursement était gratuit.
 *
 * Le correctif garde l'intention et lui donne les moyens : on cherche un
 * abonnement encore en cours **dont le moyen de paiement n'est pas le store**.
 * S'il existe, l'accès reste — et l'échéance est ramenée à la sienne, au lieu
 * de conserver celle du store remboursé.
 *
 * ── L'octroi à moitié écrit ────────────────────────────────────────────────
 *
 * `grantPremium` écrivait l'historique et le compte par un `Promise.all` :
 * deux écritures indépendantes. Si la première échoue, la seconde a déjà eu
 * lieu — le compte passe Premium sans qu'aucune ligne n'explique pourquoi, ni
 * combien a été payé, ni par quel moyen. L'inverse laisse une ligne d'achat
 * sans accès. Les deux tiennent désormais dans une transaction.
 *
 * ── Ce que ce banc ne mesure pas ───────────────────────────────────────────
 *
 * La base est simulée (voir `aides/base_memoire.ts`) : l'atomicité réelle
 * appartient à Postgres. Ce qui est établi ici est que les deux écritures
 * passent par `$transaction` et non par deux appels indépendants — sans quoi
 * aucune isolation ne pourrait les rattraper.
 */
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());

jest.mock('../services/notification.service', () => ({
  NotificationService: class {
    async sendToUser() { /* rien : les notifications ne sont pas le sujet */ }
  },
}));

import { IapService } from '../services/iap.service';
import { SubscriptionService } from '../services/subscription.service';

const { prisma, _base } = require('../lib/prisma');

const iap = new IapService();
const abonnements = new SubscriptionService();

const JOUR = 86_400_000;
const DANS_30_JOURS = () => new Date(Date.now() + 30 * JOUR);

/** Le reçu tel qu'Apple le renverrait, dans l'état demandé. */
function recu(statut: string, expire = DANS_30_JOURS()) {
  return {
    store: 'apple' as const,
    productId: 'com.pronowin.premium.monthly',
    transactionId: 'tx-apple-1',
    originalTransactionId: 'orig-apple-1',
    expiresAt: expire,
    status: statut,
    environment: 'Production',
    payload: {},
  };
}

/** Fait répondre Apple avec [statut], puis rejoue la vérification. */
async function verifier(statut: string, expire?: Date) {
  jest.spyOn(iap, 'verifyApple').mockResolvedValue(recu(statut, expire));
  return iap.verifyAndRecord({
    userId: 'abonne', store: 'apple', receipt: 'orig-apple-1',
  });
}

const compte = () => _base.users.get('abonne');

beforeEach(() => {
  jest.restoreAllMocks();
  for (const t of Object.values(_base) as Map<string, any>[]) t.clear();
  _base.users.set('abonne', {
    id: 'abonne', pseudo: 'Abonné', referralEarnings: 0, referredBy: null,
    subscriptionPlan: 'free', subscriptionExpiresAt: null, fcmToken: null,
  });
});

describe('un achat remboursé ferme l\'accès', () => {
  it('l\'achat ouvre l\'accès', async () => {
    const r = await verifier('active');
    expect(r.active).toBe(true);
    expect(compte().subscriptionPlan).toBe('premium');
  });

  it('le remboursement le referme', async () => {
    await verifier('active');
    await verifier('revoked');

    expect(compte().subscriptionPlan).toBe('free');
  });

  it('une expiration ordinaire le referme aussi', async () => {
    await verifier('active');
    await verifier('expired', new Date(Date.now() - JOUR));

    expect(compte().subscriptionPlan).toBe('free');
  });

  it('un abonnement Mobile Money encore en cours survit au remboursement', async () => {
    // Contrepartie, et c'est l'intention d'origine du garde-fou : le store ne
    // décide pas d'un accès qu'il n'a pas vendu. Un correctif qui révoquerait
    // sans regarder couperait un abonné qui a payé deux fois.
    await verifier('active');
    const fin = new Date(Date.now() + 90 * JOUR);
    await prisma.subscription.create({ data: {
      userId: 'abonne', plan: 'premium', amountPaid: 3000,
      paymentMethod: 'orange_money', startDate: new Date(), endDate: fin,
    } });

    await verifier('revoked');

    expect(compte().subscriptionPlan).toBe('premium');
    expect(compte().subscriptionExpiresAt.getTime()).toBe(fin.getTime());
  });

  it('un abonnement Mobile Money déjà terminé ne protège rien', async () => {
    // Contrepartie de la contrepartie : chercher « un abonnement hors store »
    // sans regarder sa date laisserait l'accès ouvert à vie dès qu'un ancien
    // paiement figure dans l'historique.
    await verifier('active');
    await prisma.subscription.create({ data: {
      userId: 'abonne', plan: 'premium', amountPaid: 3000,
      paymentMethod: 'orange_money', startDate: new Date(Date.now() - 120 * JOUR),
      endDate: new Date(Date.now() - 90 * JOUR),
    } });

    await verifier('revoked');

    expect(compte().subscriptionPlan).toBe('free');
  });

  it('un autre achat store encore actif maintient l\'accès', async () => {
    // Deux abonnements store : rembourser le mensuel ne doit pas fermer
    // l'accès ouvert par l'annuel.
    await verifier('active');
    await prisma.iapPurchase.create({ data: {
      userId: 'abonne', store: 'apple', productId: 'com.pronowin.premium.annual',
      transactionId: 'tx-apple-2', originalTransactionId: 'orig-apple-2',
      expiresAt: new Date(Date.now() + 300 * JOUR), status: 'active',
      environment: 'Production',
    } });

    await verifier('revoked');

    expect(compte().subscriptionPlan).toBe('premium');
  });
});

describe('un octroi de Premium est entier, ou n\'a pas lieu', () => {
  it('l\'historique et le compte sont écrits ensemble', async () => {
    await abonnements.grantPremium({
      userId: 'abonne', durationDays: 30, amountPaid: 3000,
      paymentMethod: 'orange_money', notify: false,
    });

    expect(compte().subscriptionPlan).toBe('premium');
    expect(_base.subscriptions.size).toBe(1);
  });

  it('si l\'historique échoue, le compte ne passe pas Premium', async () => {
    // Deux écritures indépendantes laissaient un compte Premium sans aucune
    // ligne disant ce qui avait été payé — invérifiable, et irréconciliable.
    const vraiCreate = prisma.subscription.create;
    prisma.subscription.create = jest.fn()
      .mockRejectedValue(new Error('écriture de l\'historique impossible'));

    await expect(abonnements.grantPremium({
      userId: 'abonne', durationDays: 30, amountPaid: 3000,
      paymentMethod: 'orange_money', notify: false,
    })).rejects.toThrow();

    prisma.subscription.create = vraiCreate;

    expect(compte().subscriptionPlan).toBe('free');
    expect(compte().subscriptionExpiresAt).toBeNull();
  });
});
