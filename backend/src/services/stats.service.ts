
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
      // ─── Transactions ──────────────────────────────────────────────────
      deposits, withdrawals, depositsPrev,
      pendingTx,
      // ─── Abonnements ───────────────────────────────────────────────────
      newSubscriptions, subRevenue,
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

      // Transactions dépôts
      prisma.transaction.aggregate({
        where: { type: 'deposit', status: 'completed', createdAt: { gte: start } },
        _sum: { amount: true }, _count: true,
      }),
      prisma.transaction.aggregate({
        where: { type: 'withdrawal', status: 'completed', createdAt: { gte: start } },
        _sum: { amount: true }, _count: true,
      }),
      prisma.transaction.aggregate({
        where: { type: 'deposit', status: 'completed', createdAt: { gte: prev, lt: start } },
        _sum: { amount: true }, _count: true,
      }),
      prisma.transaction.count({ where: { status: 'pending' } }),

      // Abonnements
      prisma.subscription.count({ where: { createdAt: { gte: start } } }).catch(() => 0),
      prisma.subscription.aggregate({
        where: { createdAt: { gte: start } },
        _sum: { amountPaid: true },
      }).catch(() => ({ _sum: { amountPaid: 0 } })),

      // Parrainage
      prisma.referral.count({ where: { createdAt: { gte: start } } }).catch(() => 0),
      prisma.referral.aggregate({
        where: { isPaid: true, createdAt: { gte: start } },
        _sum: { commissionAmount: true },
      }).catch(() => ({ _sum: { commissionAmount: 0 } })),
    ]);

    // Calcul croissance
    const depositAmount     = deposits._sum.amount     ?? 0;
    const withdrawalAmount  = withdrawals._sum.amount  ?? 0;
    const depositAmountPrev = depositsPrev._sum.amount ?? 0;
    const subRevenueAmount  = subRevenue._sum.amountPaid ?? 0;
    const commissionsAmount = paidCommissions._sum.commissionAmount ?? 0;
    const totalRevenue      = depositAmount + subRevenueAmount;

    const userGrowth    = newUsersPrev > 0
      ? Math.round(((newUsers - newUsersPrev) / newUsersPrev) * 100) : 0;
    const depositGrowth = depositAmountPrev > 0
      ? Math.round(((depositAmount - depositAmountPrev) / depositAmountPrev) * 100) : 0;

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
        total:           Math.round(totalRevenue),
        deposits:        Math.round(depositAmount),
        subscriptions:   Math.round(subRevenueAmount),
        withdrawals:     Math.round(withdrawalAmount),
        net:             Math.round(depositAmount - withdrawalAmount),
        deposit_growth:  depositGrowth,
        deposit_count:   deposits._count,
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

  // ─── Série temporelle — dépôts par jour ──────────────────────────────────
  async getRevenueTimeSeries(days: number = 30) {
    const start = new Date(Date.now() - days * 86400000);

    try {
      const txs = await prisma.transaction.findMany({
        where: { type: 'deposit', status: 'completed', createdAt: { gte: start } },
        select: { amount: true, createdAt: true },
        orderBy: { createdAt: 'asc' },
      });

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

  // ─── Top utilisateurs (plus gros dépôts) ─────────────────────────────────
  async getTopUsers(limit = 10) {
    try {
      const result = await prisma.transaction.groupBy({
        by:     ['userId'],
        where:  { type: 'deposit', status: 'completed' },
        _sum:   { amount: true },
        _count: true,
        orderBy:{ _sum: { amount: 'desc' } },
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
        user:          userMap[r.userId] ?? { pseudo: 'Inconnu' },
        total_deposits: Math.round(r._sum.amount ?? 0),
        deposit_count:  r._count,
      }));
    } catch (_) { return []; }
  }
}
