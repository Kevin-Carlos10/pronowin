/**
 * Achats intégrés : un reçu, un accès ; un événement, jamais perdu.
 *
 * Constats de l'audit du 24 septembre 2026, à corriger avant l'ouverture des
 * achats in-app :
 *
 *  I9  — la lecture « jamais vue », l'enregistrement et l'octroi étaient trois
 *        opérations : deux appels simultanés avec le même reçu accordaient deux
 *        fois, y compris à deux comptes qui se partageaient ce reçu. Et un
 *        renouvellement présenté par un autre compte passait ;
 *  I11 — un achat store écrivait sa date sur le compte, et raccourcissait un
 *        Premium plus long payé en Mobile Money ;
 *  A17 — l'achat store était enregistré à 0 FCFA, lu comme gratuit ;
 *  I10 — les webhooks acquittaient les pannes : l'événement était perdu.
 *
 * Une course ne se voit qu'avec une vraie base : ce banc écrit dans la base de
 * développement (`DATABASE_URL`), sur des comptes créés pour lui et supprimés
 * ensuite. Les stores sont simulés : on ne vérifie pas un reçu Google ici, on
 * vérifie ce que l'API fait du verdict du store.
 */
let commissions = 0;
jest.mock('../services/referral.service', () => ({
  ReferralService: class { async triggerCommissions() { commissions++; return {}; } },
}));
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { return {}; } },
}));

import { prisma } from '../lib/prisma';
import { IapService } from '../services/iap.service';
import { FileNotificationsIap, TENTATIVES_MAX } from '../services/iap_notifications.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const marque = `banc-iap-${Date.now()}`;
const comptes: string[] = [];
const JOUR = 86400000;

async function compte(suffixe: string) {
  const u = await prisma.user.create({
    data: { pseudo: `${marque}-${suffixe}`, referralCode: `${suffixe}${Date.now()}`.slice(-14).toUpperCase() },
  });
  comptes.push(u.id);
  return u.id;
}

/** Le verdict d'un store, tel que `verifyGoogle` le rend. */
function verdict(transactionId: string, originalTransactionId: string, jours = 30, status = 'active') {
  return {
    store: 'google' as const, productId: 'com.pronowin.premium.monthly',
    transactionId, originalTransactionId,
    expiresAt: new Date(Date.now() + jours * JOUR),
    status, environment: 'Production', payload: {},
  };
}

const svc = new IapService();
function storeRepond(v: ReturnType<typeof verdict>) {
  jest.spyOn(svc as any, 'verifyGoogle').mockResolvedValue(v);
}

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.iapPurchase.deleteMany({ where: { userId: { in: comptes } } });
  await prisma.subscription.deleteMany({ where: { userId: { in: comptes } } });
  await prisma.iapNotification.deleteMany({ where: { evenementId: { startsWith: marque } } });
  await prisma.user.deleteMany({ where: { id: { in: comptes } } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('I9 — un reçu n\'ouvre qu\'un accès', () => {
  it('deux comptes, même reçu, au même instant : un seul Premium', async () => {
    const [a, b] = [await compte('a'), await compte('b')];
    storeRepond(verdict(`${marque}-t1`, `${marque}-o1`));
    commissions = 0;

    const issues = await Promise.allSettled([
      svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' }),
      svc.verifyAndRecord({ userId: b, store: 'google', receipt: 'x' }),
    ]);

    // Depuis que l'abonnement suit le compte qui présente le reçu, l'un des
    // deux peut l'emporter sans que l'autre soit refusé. Ce qui ne doit
    // jamais arriver : deux Premium, deux octrois ou deux commissions pour un
    // seul paiement.
    expect(issues.some((i) => i.status === 'fulfilled')).toBe(true);
    for (const refus of issues.filter((i) => i.status === 'rejected') as PromiseRejectedResult[]) {
      expect(refus.reason.statut).toBe(409);
    }
    expect(await prisma.subscription.count({ where: { userId: { in: [a, b] } } })).toBe(1);
    expect(commissions).toBe(1);
    const premiums = await prisma.user.count({ where: { id: { in: [a, b] }, subscriptionPlan: 'premium' } });
    expect(premiums).toBe(1);
  });

  it('le même compte, deux fois au même instant : un seul octroi, deux réponses', async () => {
    const a = await compte('c');
    storeRepond(verdict(`${marque}-t2`, `${marque}-o2`));
    commissions = 0;

    const issues = await Promise.allSettled([
      svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' }),
      svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' }),
    ]);
    expect(issues.every((i) => i.status === 'fulfilled')).toBe(true);
    expect(await prisma.subscription.count({ where: { userId: a } })).toBe(1);
    expect(commissions).toBe(1);
  });

  it("restauré sur un autre compte, l'abonnement y passe et l'ancien le perd", async () => {
    // Vu le 2 octobre 2026 : second compte PronoWin sur le même iPhone, Apple
    // répond « Vous êtes déjà abonné », et la restauration était refusée —
    // ce compte ne pouvait plus jamais être Premium.
    const [a, b] = [await compte('d'), await compte('e')];
    storeRepond(verdict(`${marque}-t3`, `${marque}-o3`));
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });

    // Nouvelle transaction, même abonnement d'origine.
    storeRepond(verdict(`${marque}-t3-renouv`, `${marque}-o3`));
    await expect(svc.verifyAndRecord({ userId: b, store: 'google', receipt: 'x' }))
      .resolves.toMatchObject({ active: true });

    const plan = (id: string) => prisma.user.findUnique({ where: { id }, select: { subscriptionPlan: true } });
    expect(await plan(b)).toEqual({ subscriptionPlan: 'premium' });
    // Un paiement, un Premium à la fois (I9).
    expect(await plan(a)).toEqual({ subscriptionPlan: 'free' });
    expect(await prisma.iapPurchase.count({ where: { originalTransactionId: `${marque}-o3`, userId: a } })).toBe(0);
  });

  it("l'ancien compte garde l'accès qu'il a payé autrement", async () => {
    // Le transfert retire ce que l'abonnement store donnait, pas un Premium
    // payé par Mobile Money.
    const [a, b] = [await compte('i'), await compte('j')];
    const soixante = new Date(Date.now() + 60 * JOUR);
    await prisma.subscription.create({ data: {
      userId: a, plan: 'premium', amountPaid: 6000, paymentMethod: 'manual_mobcash',
      startDate: new Date(), endDate: soixante,
    } });
    storeRepond(verdict(`${marque}-t8`, `${marque}-o8`));
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });

    await svc.verifyAndRecord({ userId: b, store: 'google', receipt: 'x' });

    const u = await prisma.user.findUnique({ where: { id: a }, select: { subscriptionPlan: true, subscriptionExpiresAt: true } });
    expect(u!.subscriptionPlan).toBe('premium');
    expect(u!.subscriptionExpiresAt!.getTime()).toBe(soixante.getTime());
  });

  it("l'abonnement d'un compte supprimé passe au compte qui présente le reçu", async () => {
    // Vu le 2 octobre 2026 : compte supprimé, nouveau compte avec le même
    // identifiant Apple, passage du mensuel à l'annuel — achat confirmé par
    // Apple, refusé ici en 409. La chaîne restait au compte anonymisé.
    const [ancien, nouveau] = [await compte('g'), await compte('h')];
    storeRepond(verdict(`${marque}-t9`, `${marque}-o9`));
    await svc.verifyAndRecord({ userId: ancien, store: 'google', receipt: 'x' });
    await prisma.user.update({ where: { id: ancien }, data: { deletedAt: new Date(), isActive: false } });

    // L'annuel : nouvelle transaction, même abonnement d'origine.
    storeRepond(verdict(`${marque}-t9-annuel`, `${marque}-o9`, 365));
    const r = await svc.verifyAndRecord({ userId: nouveau, store: 'google', receipt: 'x' });

    expect(r.active).toBe(true);
    expect(await prisma.user.findUnique({ where: { id: nouveau }, select: { subscriptionPlan: true } }))
      .toEqual({ subscriptionPlan: 'premium' });
    expect(await prisma.iapPurchase.count({ where: { originalTransactionId: `${marque}-o9`, userId: ancien } }))
      .toBe(0);

    // Restaurer la transaction d'origine ne la renvoie pas au compte supprimé.
    storeRepond(verdict(`${marque}-t9`, `${marque}-o9`));
    await expect(svc.verifyAndRecord({ userId: nouveau, store: 'google', receipt: 'x' }))
      .resolves.toMatchObject({ active: true });
  });
});

decrireSurBaseLocale('I11 et A17 — échéance et montant', () => {
  it('un achat store ne raccourcit pas un Premium payé plus loin', async () => {
    const a = await compte('f');
    const soixante = new Date(Date.now() + 60 * JOUR);
    await prisma.subscription.create({ data: {
      userId: a, plan: 'premium', amountPaid: 6000, paymentMethod: 'manual_mobcash',
      startDate: new Date(), endDate: soixante,
    } });
    await prisma.user.update({ where: { id: a }, data: { subscriptionPlan: 'premium', subscriptionExpiresAt: soixante } });

    storeRepond(verdict(`${marque}-t4`, `${marque}-o4`, 30));
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });
    let u = await prisma.user.findUnique({ where: { id: a } });
    expect(u!.subscriptionExpiresAt!.getTime()).toBe(soixante.getTime());

    // Le renouvellement non plus.
    storeRepond(verdict(`${marque}-t4`, `${marque}-o4`, 31));
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });
    u = await prisma.user.findUnique({ where: { id: a } });
    expect(u!.subscriptionExpiresAt!.getTime()).toBe(soixante.getTime());
  });

  it('un achat store est enregistré sans montant inventé', async () => {
    const a = await compte('g');
    storeRepond(verdict(`${marque}-t5`, `${marque}-o5`));
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });
    const ligne = await prisma.subscription.findFirst({ where: { userId: a } });
    expect(ligne!.amountPaid).toBeNull();
  });
});

decrireSurBaseLocale('I10 — un événement n\'est jamais perdu', () => {
  const faux = { handleAppleNotification: jest.fn(), handleGoogleNotification: jest.fn() };
  const file = new FileNotificationsIap(faux as any);
  const charge = { message: { data: 'e30=' } };

  it('un événement reçu deux fois n\'est inscrit qu\'une fois', async () => {
    expect(await file.recevoir('google', `${marque}-e1`, charge)).toEqual({ doublon: false });
    expect(await file.recevoir('google', `${marque}-e1`, charge)).toEqual({ doublon: true });
    expect(await prisma.iapNotification.count({ where: { evenementId: `${marque}-e1` } })).toBe(1);
  });

  it('un traitement qui échoue est retenté plus tard, pas abandonné', async () => {
    await file.recevoir('google', `${marque}-e2`, charge);
    faux.handleGoogleNotification.mockRejectedValue(new Error('base injoignable'));
    await file.traiterEnAttente(100);

    const n = await prisma.iapNotification.findFirst({ where: { evenementId: `${marque}-e2` } });
    expect(n!.statut).toBe('echec');
    expect(n!.tentatives).toBe(1);
    expect(n!.prochaineTentative.getTime()).toBeGreaterThan(Date.now());

    // Une fois l'échéance venue, le nouvel essai réussit.
    await prisma.iapNotification.update({ where: { id: n!.id }, data: { prochaineTentative: new Date() } });
    faux.handleGoogleNotification.mockResolvedValue({ handled: true });
    await file.traiterEnAttente(100);
    expect((await prisma.iapNotification.findUnique({ where: { id: n!.id } }))!.statut).toBe('traitee');
  });

  it('une notification arrivée avant l\'achat attend l\'achat', async () => {
    await file.recevoir('google', `${marque}-e3`, charge);
    faux.handleGoogleNotification.mockResolvedValue({ ignored: true, reason: 'unknown_purchase_token' });
    await file.traiterEnAttente(100);
    const n = await prisma.iapNotification.findFirst({ where: { evenementId: `${marque}-e3` } });
    expect(n!.statut).toBe('echec');

    // Après le dernier essai seulement, elle est classée ignorée.
    await prisma.iapNotification.update({
      where: { id: n!.id }, data: { tentatives: TENTATIVES_MAX - 1, prochaineTentative: new Date() } });
    await file.traiterEnAttente(100);
    expect((await prisma.iapNotification.findUnique({ where: { id: n!.id } }))!.statut).toBe('ignoree');
  });
});
