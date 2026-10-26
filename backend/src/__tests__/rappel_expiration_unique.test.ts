/**
 * Le rappel « Ton Premium expire demain » part une fois, même si la tâche
 * repasse dans la journée.
 *
 * La tâche tourne deux minutes après chaque démarrage du serveur : un jour de
 * déploiements, un abonné recevait le même rappel deux ou trois fois (vidéo
 * du 8 octobre 2026).
 */
import { decrireSurBaseLocale, BASE_LOCALE } from './aides/base_locale';
import { prisma } from '../lib/prisma';
import { SubscriptionService } from '../services/subscription.service';

const marque = `banc-rappel-${Date.now()}`;
let compte: string | null = null;

afterAll(async () => {
  if (!BASE_LOCALE) return;
  if (compte) {
    await prisma.notification.deleteMany({ where: { userId: compte } });
    await prisma.user.delete({ where: { id: compte } });
  }
  await prisma.$disconnect();
});

decrireSurBaseLocale('rappel d\'expiration du Premium', () => {
  it('deux passages le même jour : un seul rappel', async () => {
    const demain = new Date(Date.now() + 86400000);
    demain.setHours(12, 0, 0, 0);
    const u = await prisma.user.create({ data: {
      pseudo: marque, referralCode: marque.slice(-12).toUpperCase(),
      subscriptionPlan: 'premium', subscriptionExpiresAt: demain,
    } });
    compte = u.id;

    const svc = new SubscriptionService();
    await svc.notifyExpiringSubscriptions();
    await svc.notifyExpiringSubscriptions();

    const rappels = await prisma.notification.findMany({
      where: { userId: u.id, title: { contains: 'expire demain' } },
    });
    expect(rappels).toHaveLength(1);
  });
});
