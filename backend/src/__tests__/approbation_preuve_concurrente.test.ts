/**
 * Deux approbations simultanées d'une même preuve n'en font qu'une.
 *
 * La preuve était lue « en attente », puis approuvée par une écriture sans
 * condition, en parallèle de l'octroi du Premium. Deux administrateurs qui
 * cliquaient à quelques secondes d'écart passaient tous deux le contrôle :
 * deux lignes d'abonnement, et deux commissions de parrainage pour un seul
 * paiement (constat I1 de l'audit du 24 septembre 2026).
 *
 * Une course ne se voit qu'avec une vraie base : ce banc écrit dans la base
 * de développement (`DATABASE_URL`), sur un compte créé pour lui et supprimé
 * ensuite. Les notifications et commissions sont remplacées par des
 * compteurs.
 */
let commissions = 0;
jest.mock('../services/referral.service', () => ({
  ReferralService: class { async triggerCommissions() { commissions++; return {}; } },
}));
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { return {}; } },
}));

import { prisma } from '../lib/prisma';
import { SubscriptionService } from '../services/subscription.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const svc = new SubscriptionService();
const marque = `banc-i1-${Date.now()}`;
let userId = '';

beforeAll(async () => {
  if (!BASE_LOCALE) return;
  const u = await prisma.user.create({
    data: { pseudo: marque, referralCode: marque.slice(-12).toUpperCase() },
  });
  userId = u.id;
});

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.subscriptionProof.deleteMany({ where: { userId } });
  await prisma.subscription.deleteMany({ where: { userId } });
  await prisma.user.delete({ where: { id: userId } }).catch(() => {});
  await prisma.$disconnect();
});

const nouvellePreuve = () => prisma.subscriptionProof.create({
  data: { userId, type: 'payment_screenshot', screenshotUrl: 'banc://preuve', amount: 2000 },
});

decrireSurBaseLocale('approbation d\'une preuve : une seule fois', () => {
  it('deux approbations simultanées : une réussit, l\'autre est refusée', async () => {
    const preuve = await nouvellePreuve();
    commissions = 0;

    const issues = await Promise.allSettled([
      svc.reviewProof({ proofId: preuve.id, adminId: 'banc-a', approved: true }),
      svc.reviewProof({ proofId: preuve.id, adminId: 'banc-b', approved: true }),
    ]);

    const reussies = issues.filter((i) => i.status === 'fulfilled');
    const refusees = issues.filter((i) => i.status === 'rejected') as PromiseRejectedResult[];
    expect(reussies).toHaveLength(1);
    expect(refusees).toHaveLength(1);
    expect(refusees[0].reason.message).toMatch(/déjà traitée/);

    // Ce qui coûte : l'historique et la commission.
    expect(await prisma.subscription.count({ where: { userId } })).toBe(1);
    expect(commissions).toBe(1);
  });

  it('un refus arrivé après une approbation ne réécrit pas la preuve', async () => {
    const preuve = await nouvellePreuve();
    await svc.reviewProof({ proofId: preuve.id, adminId: 'banc-a', approved: true });

    await expect(svc.reviewProof({ proofId: preuve.id, adminId: 'banc-b', approved: false }))
      .rejects.toThrow(/déjà traitée/);
    const relue = await prisma.subscriptionProof.findUnique({ where: { id: preuve.id } });
    expect(relue?.status).toBe('approved');
    expect(relue?.reviewedBy).toBe('banc-a');
  });

  it('une approbation seule aboutit normalement', async () => {
    // Contrepartie : un service qui refuserait toute approbation passerait les
    // deux points précédents.
    const preuve = await nouvellePreuve();
    const avant = await prisma.subscription.count({ where: { userId } });
    await expect(svc.reviewProof({ proofId: preuve.id, adminId: 'banc-a', approved: true }))
      .resolves.toEqual({ success: true, approved: true });
    expect(await prisma.subscription.count({ where: { userId } })).toBe(avant + 1);
  });
});
