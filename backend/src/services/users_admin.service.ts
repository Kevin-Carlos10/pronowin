import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';

const notifSvc = new NotificationService();

export class UsersAdminService {

  /** Liste paginée avec recherche + filtres */
  async getUsers(params: {
    page:     number;
    perPage:  number;
    search?:  string;   // pseudo ou téléphone
    plan?:    string;   // 'free' | 'premium'
    status?:  string;   // 'active' | 'suspended'
    sortBy?:  string;   // 'createdAt' | 'pseudo' | 'subscriptionPlan'
    sortDir?: 'asc' | 'desc';
  }) {
    const { page, perPage, search, plan, status, sortBy = 'createdAt', sortDir = 'desc' } = params;

    const where: any = {};
    if (search) {
      where.OR = [
        { pseudo:      { contains: search, mode: 'insensitive' } },
        { phoneNumber: { contains: search } },
        { email:       { contains: search, mode: 'insensitive' } },
        { firstName:   { contains: search, mode: 'insensitive' } },
        { lastName:    { contains: search, mode: 'insensitive' } },
        { xbetId:      { contains: search } },
      ];
    }
    if (plan)   where.subscriptionPlan = plan;
    if (status === 'active')    where.isActive = true;
    if (status === 'suspended') where.isActive = false;

    const orderBy: any = {};
    orderBy[sortBy] = sortDir;

    const [users, total] = await Promise.all([
      prisma.user.findMany({
        where, orderBy, skip: (page - 1) * perPage, take: perPage,
        select: {
          id: true, pseudo: true, firstName: true, lastName: true,
          phoneNumber: true, email: true, countryCode: true,
          xbetId: true, birthDate: true,
          subscriptionPlan: true, subscriptionExpiresAt: true,
          referralCode: true, referralEarnings: true,
          isActive: true, createdAt: true, lastLoginAt: true,
          _count: { select: { transactions: true, referrals: true } },
        },
      }),
      prisma.user.count({ where }),
    ]);

    return {
      data: users.map(u => ({
        ...u,
        full_name: u.firstName && u.lastName ? `${u.firstName} ${u.lastName}` : null,
        is_premium: u.subscriptionPlan === 'premium' &&
          (u.subscriptionExpiresAt ? u.subscriptionExpiresAt > new Date() : false),
        days_left: u.subscriptionExpiresAt
          ? Math.max(0, Math.ceil((u.subscriptionExpiresAt.getTime() - Date.now()) / 86400000)) : 0,
        transaction_count: u._count.transactions,
        referral_count:    u._count.referrals,
      })),
      total, page, per_page: perPage,
      total_pages: Math.ceil(total / perPage),
    };
  }

  /** Détail complet d'un utilisateur */
  async getUserDetail(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, pseudo: true, firstName: true, lastName: true,
        phoneNumber: true, email: true, countryCode: true,
        xbetId: true, birthDate: true, avatarUrl: true,
        subscriptionPlan: true, subscriptionExpiresAt: true,
        referralCode: true, referralEarnings: true,
        isActive: true, createdAt: true, lastLoginAt: true, fcmToken: true,
      },
    });
    if (!user) throw new Error('Utilisateur introuvable.');

    // Transactions récentes
    const transactions = await prisma.transaction.findMany({
      where:   { userId },
      orderBy: { createdAt: 'desc' },
      take:    10,
    });

    // Abonnements
    const subscriptions = await prisma.subscription.findMany({
      where:   { userId },
      orderBy: { createdAt: 'desc' },
      take:    5,
    }).catch(() => []);

    // Preuves
    const proofs = await prisma.subscriptionProof.findMany({
      where:   { userId },
      orderBy: { createdAt: 'desc' },
      take:    5,
    }).catch(() => []);

    // Filleuls
    const referrals = await prisma.referral.findMany({
      where:   { referrerId: userId },
      include: { referred: { select: { pseudo: true, phoneNumber: true, subscriptionPlan: true } } },
      orderBy: { createdAt: 'desc' },
    }).catch(() => []);

    return {
      user: {
        ...user,
        full_name: user.firstName && user.lastName ? `${user.firstName} ${user.lastName}` : null,
        is_premium: user.subscriptionPlan === 'premium' &&
          (user.subscriptionExpiresAt ? user.subscriptionExpiresAt > new Date() : false),
        days_left: user.subscriptionExpiresAt
          ? Math.max(0, Math.ceil((user.subscriptionExpiresAt.getTime() - Date.now()) / 86400000)) : 0,
      },
      transactions, subscriptions, proofs, referrals,
    };
  }

  /** Suspendre / Réactiver */
  async toggleSuspend(userId: string, suspend: boolean, reason?: string) {
    const user = await prisma.user.update({
      where: { id: userId },
      data:  { isActive: !suspend },
    });

    if (suspend && user.fcmToken) {
      await notifSvc.sendToUser(userId, {
        title: '⚠️ Compte suspendu',
        body:  reason ?? 'Votre compte a été suspendu. Contactez le support.',
        data:  { type: 'system' },
      }).catch(() => {});
    }
    return user;
  }

  /** Passer Premium manuellement */
  async grantPremium(userId: string, durationDays: number, adminId: string) {
    const startDate = new Date();
    const endDate   = new Date(startDate.getTime() + durationDays * 86400000);

    await Promise.all([
      prisma.user.update({
        where: { id: userId },
        data:  { subscriptionPlan: 'premium', subscriptionExpiresAt: endDate },
      }),
      prisma.subscription.create({
        data: {
          userId, plan: 'premium', amountPaid: 0,
          paymentMethod: 'manual_admin', startDate, endDate,
        },
      }).catch(() => {}),
    ]);

    await notifSvc.sendToUser(userId, {
      title: '🎉 Premium activé !',
      body:  `Votre accès Premium a été activé pour ${durationDays} jours par l'équipe PronoWin.`,
      data:  { deep_link: '/pronostics', type: 'system' },
    }).catch(() => {});

    return { success: true, expires_at: endDate };
  }

  /** Révoquer Premium */
  async revokePremium(userId: string) {
    await prisma.user.update({
      where: { id: userId },
      data:  { subscriptionPlan: 'free', subscriptionExpiresAt: null },
    });
    return { success: true };
  }

  /** Envoyer notification push */
  async sendNotification(userId: string, title: string, body: string) {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { fcmToken: true } });
    if (!user?.fcmToken) throw new Error('Cet utilisateur n\'a pas de token FCM enregistré.');
    await notifSvc.sendToUser(userId, { title, body, data: { type: 'system' } });
    return { success: true };
  }

  /** Modifier pseudo */
  async updatePseudo(userId: string, newPseudo: string) {
    if (newPseudo.trim().length < 3) throw new Error('Pseudo trop court (min 3 caractères).');
    const existing = await prisma.user.findFirst({
      where: { pseudo: newPseudo.trim(), NOT: { id: userId } },
    });
    if (existing) throw new Error('Ce pseudo est déjà utilisé.');
    return prisma.user.update({ where: { id: userId }, data: { pseudo: newPseudo.trim() } });
  }

  /** Exporter CSV */
  async exportCsv(plan?: string) {
    const where: any = {};
    if (plan) where.subscriptionPlan = plan;

    const users = await prisma.user.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true, pseudo: true, firstName: true, lastName: true,
        phoneNumber: true, email: true, countryCode: true, xbetId: true,
        birthDate: true, subscriptionPlan: true, subscriptionExpiresAt: true,
        referralCode: true, referralEarnings: true, isActive: true,
        createdAt: true, lastLoginAt: true, 
      },
    });

    const header = 'ID,Pseudo,Prénom,Nom,Téléphone,Email,Pays,1xBet ID,Date naissance,Plan,Expire le,Code parrainage,Gains parrainage,Actif,Inscrit le,Dernière connexion';
    const rows   = users.map(u => [
      u.id, u.pseudo, u.firstName ?? '', u.lastName ?? '',
      u.phoneNumber, u.email ?? '', u.countryCode, u.xbetId ?? '',
      (u.birthDate as Date)?.toISOString().split('T')[0] ?? '',
      u.subscriptionPlan,
      u.subscriptionExpiresAt?.toISOString().split('T')[0] ?? '',
      u.referralCode, u.referralEarnings,
      u.isActive ? 'Oui' : 'Non',
      u.createdAt.toISOString().split('T')[0],
      u.lastLoginAt?.toISOString().split('T')[0] ?? '',
    ].map(v => `"${v}"`).join(','));

    return [header, ...rows].join('\n');
  }

  /** Stats globales */
  async getStats() {
    const now   = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const week  = new Date(today.getTime() - 7 * 86400000);
    const month = new Date(today.getTime() - 30 * 86400000);

    const [total, premium, active, newToday, newWeek, newMonth, suspended] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { subscriptionPlan: 'premium', subscriptionExpiresAt: { gt: now } } }),
      prisma.user.count({ where: { isActive: true } }),
      prisma.user.count({ where: { createdAt: { gte: today } } }),
      prisma.user.count({ where: { createdAt: { gte: week } } }),
      prisma.user.count({ where: { createdAt: { gte: month } } }),
      prisma.user.count({ where: { isActive: false } }),
    ]);

    return { total, premium, active, suspended, newToday, newWeek, newMonth,
      conversion_rate: total > 0 ? Math.round((premium / total) * 100) : 0 };
  }
}
