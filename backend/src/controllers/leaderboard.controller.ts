import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';

import { prisma } from '../lib/prisma';

const MIN_SETTLED = 3; // paris réglés minimum pour apparaître

/** GET /leaderboard?period=weekly|monthly|all_time&limit=50 */
export const getLeaderboard = async (req: AuthRequest, res: Response) => {
  try {
    const period = (req.query.period as string) ?? 'monthly';
    const limit  = Math.min(parseInt(req.query.limit as string ?? '50'), 100);

    const since = periodToDate(period);

    // Récupérer tous les paris réglés dans la période, groupés par utilisateur
    const bets = await prisma.bankrollBet.findMany({
      where: {
        result:   { not: null },
        ...(since ? { createdAt: { gte: since } } : {}),
      },
      select: {
        result: true,
        bankroll: {
          select: {
            userId: true,
            user: {
              select: {
                pseudo:           true,
                avatarUrl:        true,
                subscriptionPlan: true,
              },
            },
          },
        },
      },
    });

    // Agréger par userId
    const map = new Map<string, {
      userId:   string;
      pseudo:   string;
      avatarUrl: string | null;
      isPremium: boolean;
      wins:     number;
      settled:  number;
    }>();

    for (const b of bets) {
      const uid  = b.bankroll.userId;
      const user = b.bankroll.user;
      if (!map.has(uid)) {
        map.set(uid, {
          userId:    uid,
          pseudo:    user.pseudo ?? 'Inconnu',
          avatarUrl: user.avatarUrl ?? null,
          isPremium: user.subscriptionPlan !== 'free',
          wins:      0,
          settled:   0,
        });
      }
      const entry = map.get(uid)!;
      entry.settled++;
      if (b.result === 'WIN') entry.wins++;
    }

    // Filtrer seuil minimum, trier par taux de réussite desc, puis par paris gagnés desc
    const sorted = [...map.values()]
      .filter(e => e.settled >= MIN_SETTLED)
      .sort((a, b) => {
        const rateA = a.wins / a.settled;
        const rateB = b.wins / b.settled;
        if (rateB !== rateA) return rateB - rateA;
        return b.wins - a.wins;
      })
      .slice(0, limit);

    const data = sorted.map((e, i) => ({
      rank:             i + 1,
      user_id:          e.userId,
      pseudo:           e.pseudo,
      avatar_url:       e.avatarUrl,
      total_predictions: e.settled,
      won_predictions:  e.wins,
      win_rate:         e.settled > 0 ? e.wins / e.settled : 0,
      total_points:     e.wins * 10,  // 10 pts par pari gagné
      is_premium:       e.isPremium,
      badge:            resolveBadge(i, e.wins / e.settled, e.isPremium),
    }));

    res.json({ data, period, total: data.length });
  } catch (err: any) {
    res.status(500).json({ message: err.message });
  }
};

function periodToDate(period: string): Date | null {
  const now = new Date();
  if (period === 'weekly')  { now.setDate(now.getDate() - 7);  return now; }
  if (period === 'monthly') { now.setDate(now.getDate() - 30); return now; }
  return null; // all_time
}

function resolveBadge(rank: number, winRate: number, isPremium: boolean): string | null {
  if (rank === 0 && winRate >= 0.75) return 'legend';  // 1er
  if (winRate >= 0.70 && isPremium)  return 'expert';
  if (rank <= 4 && winRate >= 0.60)  return 'rising';
  return null;
}
