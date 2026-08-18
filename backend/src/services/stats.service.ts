
import { prisma } from '../lib/prisma';

export class StatsService {

  async getDashboardStats(days: number = 30) {
    const now   = new Date();
    const start = new Date(now.getTime() - days * 86400000);
    const prev  = new Date(start.getTime() - days * 86400000);

    const [
      // ─── Utilisateurs ──────────────────────────────────────────────────
      totalUsers, newUsers, newUsersPrev,
      premiumUsers, freeUsers,
      // ─── Versements de parrainage ──────────────────────────────────────
      withdrawals, pendingTx,
      // ─── Abonnements ───────────────────────────────────────────────────
      newSubscriptions, subRevenue, subRevenuePrev,
      // ─── Parrainage ────────────────────────────────────────────────────
      totalReferrals, paidCommissions,
    ] = await Promise.all([
      // Utilisateurs
      prisma.user.count(),
      prisma.user.count({ where: { createdAt: { gte: start } } }),
      prisma.user.count({ where: { createdAt: { gte: prev, lt: start } } }),
      prisma.user.count({ where: { subscriptionPlan: 'premium',
        subscriptionExpiresAt: { gt: now } } }),
      prisma.user.count({ where: { subscriptionPlan: 'free' } }),

      // Versements de gains de parrainage (sortie de trésorerie)
      prisma.transaction.aggregate({
        where: { status: 'completed', createdAt: { gte: start } },
        _sum: { amount: true }, _count: true,
      }),
      prisma.transaction.count({ where: { status: 'pending' } }),

      // Abonnements — désormais la seule entrée de revenu
      prisma.subscription.count({ where: { createdAt: { gte: start } } }).catch(() => 0),
      prisma.subscription.aggregate({
        where: { createdAt: { gte: start } },
        _sum: { amountPaid: true },
      }).catch(() => ({ _sum: { amountPaid: 0 } })),
      prisma.subscription.aggregate({
        where: { createdAt: { gte: prev, lt: start } },
        _sum: { amountPaid: true },
      }).catch(() => ({ _sum: { amountPaid: 0 } })),

      // Parrainage
      prisma.referral.count({ where: { createdAt: { gte: start } } }).catch(() => 0),
      prisma.referral.aggregate({
        where: { isPaid: true, createdAt: { gte: start } },
        _sum: { commissionAmount: true },
      }).catch(() => ({ _sum: { commissionAmount: 0 } })),
    ]);

    // Le revenu valait auparavant « dépôts + abonnements ». Les dépôts ayant
    // disparu, la seule entrée reste l'abonnement Premium — et la croissance
    // se calcule sur cette même base, sans quoi elle serait figée à 0.
    const withdrawalAmount     = withdrawals._sum.amount ?? 0;
    const subRevenueAmount     = subRevenue._sum.amountPaid ?? 0;
    const subRevenueAmountPrev = subRevenuePrev._sum.amountPaid ?? 0;
    const commissionsAmount    = paidCommissions._sum.commissionAmount ?? 0;
    const totalRevenue         = subRevenueAmount;

    const userGrowth    = newUsersPrev > 0
      ? Math.round(((newUsers - newUsersPrev) / newUsersPrev) * 100) : 0;
    const revenueGrowth = subRevenueAmountPrev > 0
      ? Math.round(((subRevenueAmount - subRevenueAmountPrev) / subRevenueAmountPrev) * 100) : 0;

    return {
      period_days: days,
      users: {
        total:          totalUsers,
        new:            newUsers,
        growth_pct:     userGrowth,
        premium:        premiumUsers,
        free:           freeUsers,
        conversion_rate: totalUsers > 0
          ? Math.round((premiumUsers / totalUsers) * 100) : 0,
      },
      revenue: {
        total:            Math.round(totalRevenue),
        subscriptions:    Math.round(subRevenueAmount),
        withdrawals:      Math.round(withdrawalAmount),
        net:              Math.round(subRevenueAmount - withdrawalAmount),
        revenue_growth:   revenueGrowth,
        withdrawal_count: withdrawals._count,
      },
      subscriptions: {
        new:     newSubscriptions,
        revenue: Math.round(subRevenueAmount),
      },
      referral: {
        new:         totalReferrals,
        commissions: Math.round(commissionsAmount),
      },
      pending: {
        transactions: pendingTx,
      },
    };
  }

  // ─── Série temporelle — revenu par jour ──────────────────────────────────
  // Cette courbe sommait les dépôts. Sans dépôt possible, elle serait
  // définitivement plate : elle suit désormais les abonnements Premium, qui
  // sont la recette réelle de la plateforme.
  async getRevenueTimeSeries(days: number = 30) {
    const start = new Date(Date.now() - days * 86400000);

    try {
      const txs = (await prisma.subscription.findMany({
        where: { createdAt: { gte: start } },
        select: { amountPaid: true, createdAt: true },
        orderBy: { createdAt: 'asc' },
      })).map(s => ({ amount: s.amountPaid, createdAt: s.createdAt }));

      // Grouper par jour
      const byDay: Record<string, number> = {};
      for (let i = 0; i < days; i++) {
        const d = new Date(start.getTime() + i * 86400000);
        byDay[d.toISOString().split('T')[0]] = 0;
      }
      for (const tx of txs) {
        const key = tx.createdAt.toISOString().split('T')[0];
        if (byDay[key] !== undefined) byDay[key] += tx.amount;
      }

      return Object.entries(byDay).map(([date, amount]) => ({
        date,
        label: new Date(date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }),
        amount: Math.round(amount),
      }));
    } catch (_) {
      return [];
    }
  }

  // ─── Série temporelle — inscriptions par jour ─────────────────────────────
  async getUsersTimeSeries(days: number = 30) {
    const start = new Date(Date.now() - days * 86400000);

    try {
      const users = await prisma.user.findMany({
        where:  { createdAt: { gte: start } },
        select: { createdAt: true, subscriptionPlan: true },
        orderBy: { createdAt: 'asc' },
      });

      const byDay: Record<string, { total: number; premium: number }> = {};
      for (let i = 0; i < days; i++) {
        const d = new Date(start.getTime() + i * 86400000);
        byDay[d.toISOString().split('T')[0]] = { total: 0, premium: 0 };
      }
      for (const u of users) {
        const key = u.createdAt.toISOString().split('T')[0];
        if (byDay[key]) {
          byDay[key].total++;
          if (u.subscriptionPlan === 'premium') byDay[key].premium++;
        }
      }

      return Object.entries(byDay).map(([date, data]) => ({
        date,
        label:   new Date(date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }),
        total:   data.total,
        premium: data.premium,
      }));
    } catch (_) {
      return [];
    }
  }

  // ─── Top utilisateurs (plus grosses dépenses) ────────────────────────────
  // Le classement portait sur les dépôts. Il porte maintenant sur le montant
  // d'abonnement réellement payé — la seule dépense qui subsiste.
  async getTopUsers(limit = 10) {
    try {
      const result = await prisma.subscription.groupBy({
        by:     ['userId'],
        _sum:   { amountPaid: true },
        _count: true,
        orderBy:{ _sum: { amountPaid: 'desc' } },
        take:   limit,
      });

      const userIds = result.map(r => r.userId);
      const users   = await prisma.user.findMany({
        where:  { id: { in: userIds } },
        select: { id: true, pseudo: true, phoneNumber: true,
                  subscriptionPlan: true, firstName: true, lastName: true },
      });
      const userMap = Object.fromEntries(users.map(u => [u.id, u]));

      return result.map(r => ({
        user:  userMap[r.userId] ?? { pseudo: 'Inconnu' },
        total: Math.round(r._sum.amountPaid ?? 0),
        count: r._count,
      }));
    } catch (_) { return []; }
  }
}
