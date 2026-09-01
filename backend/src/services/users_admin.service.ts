import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';

const notifSvc = new NotificationService();

export class UsersAdminService {

  /**
   * Colonnes autorisées au tri.
   *
   * `sortBy` arrivait de la query string directement dans `orderBy` : une
   * valeur inconnue faisait lever Prisma (500), et n'importe quel champ du
   * modèle — `passwordHash` compris — devenait un critère d'ordre.
   */
  private static readonly SORTABLE = new Set([
    'createdAt', 'pseudo', 'lastLoginAt', 'subscriptionPlan', 'isActive', 'email',
  ]);

  /** Liste paginée avec recherche + filtres */
  async getUsers(params: {
    page:     number;
    perPage:  number;
    search?:  string;   // pseudo ou téléphone
    plan?:    string;   // 'free' | 'premium'
    status?:  string;   // 'active' | 'suspended'
    dateFrom?: string;  // inscrit à partir de (AAAA-MM-JJ)
    dateTo?:   string;  // inscrit jusqu'à (AAAA-MM-JJ, borne incluse)
    minTx?:    number;  // au moins N transactions
    sortBy?:  string;
    sortDir?: 'asc' | 'desc';
  }) {
    const { page, perPage, search, plan, status, dateFrom, dateTo, minTx,
            sortBy = 'createdAt', sortDir = 'desc' } = params;

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

    // Fenêtre d'inscription. Le panneau « Avancé » de l'admin envoyait déjà ces
    // deux paramètres, mais rien ne les lisait : le filtre s'affichait comme
    // actif sans jamais restreindre la liste.
    const createdAt: any = {};
    if (dateFrom) {
      const d = new Date(dateFrom);
      if (!isNaN(d.getTime())) createdAt.gte = d;
    }
    if (dateTo) {
      const d = new Date(dateTo);
      // Borne incluse : « avant le 12 » doit garder les inscrits du 12.
      if (!isNaN(d.getTime())) createdAt.lte = new Date(d.getTime() + 86400000 - 1);
    }
    if (Object.keys(createdAt).length) where.createdAt = createdAt;

    // Prisma ne sait pas filtrer sur un compteur de relation : on résout
    // d'abord les identifiants concernés.
    if (minTx && minTx > 0) {
      const grouped = await prisma.transaction.groupBy({
        by:     ['userId'],
        _count: { _all: true },
      });
      where.id = { in: grouped.filter(g => g._count._all >= minTx).map(g => g.userId) };
    }

    const col = UsersAdminService.SORTABLE.has(sortBy) ? sortBy : 'createdAt';
    const orderBy: any = { [col]: sortDir === 'asc' ? 'asc' : 'desc' };

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

  /**
   * Suspendre / réactiver un lot de comptes.
   *
   * La modération se faisait compte par compte, en ouvrant chaque fiche. On
   * garde l'envoi de notification en dehors de la transaction : un token FCM
   * périmé ne doit pas annuler la suspension elle-même.
   */
  async bulkSuspend(userIds: string[], suspend: boolean, reason?: string) {
    const ids = [...new Set(userIds.filter(id => typeof id === 'string' && id.trim()))];
    if (ids.length === 0) throw new Error('Aucun utilisateur sélectionné.');

    const { count } = await prisma.user.updateMany({
      where: { id: { in: ids } },
      data:  { isActive: !suspend },
    });

    if (suspend) {
      const cibles = await prisma.user.findMany({
        where:  { id: { in: ids }, fcmToken: { not: null } },
        select: { id: true },
      });
      await Promise.allSettled(cibles.map(u => notifSvc.sendToUser(u.id, {
        title: '⚠️ Compte suspendu',
        body:  reason ?? 'Votre compte a été suspendu. Contactez le support.',
        data:  { type: 'system' },
      })));
    }
    return { updated: count, suspended: suspend };
  }

  /**
   * Notifier un lot de comptes.
   *
   * Renvoie le détail : sans token FCM, l'envoi est impossible et le silence
   * ferait croire à un succès.
   */
  async bulkNotify(userIds: string[], title: string, body: string) {
    const ids = [...new Set(userIds.filter(id => typeof id === 'string' && id.trim()))];
    if (ids.length === 0)   throw new Error('Aucun utilisateur sélectionné.');
    if (!title?.trim())     throw new Error('Titre requis.');
    if (!body?.trim())      throw new Error('Message requis.');

    const cibles = await prisma.user.findMany({
      where:  { id: { in: ids }, fcmToken: { not: null } },
      select: { id: true },
    });
    const res = await Promise.allSettled(cibles.map(u =>
      notifSvc.sendToUser(u.id, { title: title.trim(), body: body.trim(), data: { type: 'system' } })));

    const sent = res.filter(r => r.status === 'fulfilled').length;
    return { sent, failed: cibles.length - sent, skipped: ids.length - cibles.length, total: ids.length };
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

  /** En-tête CSV (utilisateurs) */
  exportCsvHeader() {
    return 'ID,Pseudo,Prénom,Nom,Téléphone,Email,Pays,1xBet ID,Date naissance,Plan,Expire le,Code parrainage,Gains parrainage,Actif,Inscrit le,Dernière connexion';
  }

  /**
   * Exporter CSV en flux, page par page (cursor sur id), plutôt que de charger
   * toute la table users en mémoire et construire la chaîne CSV d'un bloc —
   * la table n'a pas de limite naturelle de croissance.
   */
  async *exportCsvRows(plan?: string, pageSize = 1000): AsyncGenerator<string> {
    const where: any = {};
    if (plan) where.subscriptionPlan = plan;

    let cursor: string | undefined;
    while (true) {
      const users = await prisma.user.findMany({
        where,
        orderBy: { id: 'asc' },
        take: pageSize,
        ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
        select: {
          id: true, pseudo: true, firstName: true, lastName: true,
          phoneNumber: true, email: true, countryCode: true, xbetId: true,
          birthDate: true, subscriptionPlan: true, subscriptionExpiresAt: true,
          referralCode: true, referralEarnings: true, isActive: true,
          createdAt: true, lastLoginAt: true,
        },
      });
      if (users.length === 0) return;

      for (const u of users) {
        yield [
          u.id, u.pseudo, u.firstName ?? '', u.lastName ?? '',
          u.phoneNumber, u.email ?? '', u.countryCode, u.xbetId ?? '',
          (u.birthDate as Date)?.toISOString().split('T')[0] ?? '',
          u.subscriptionPlan,
          u.subscriptionExpiresAt?.toISOString().split('T')[0] ?? '',
          u.referralCode, u.referralEarnings,
          u.isActive ? 'Oui' : 'Non',
          u.createdAt.toISOString().split('T')[0],
          u.lastLoginAt?.toISOString().split('T')[0] ?? '',
        ].map(v => `"${v}"`).join(',');
      }

      cursor = users[users.length - 1].id;
      if (users.length < pageSize) return;
    }
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
