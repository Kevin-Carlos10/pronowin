import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';

const notifSvc = new NotificationService();

// ── Calcul de la mise suggérée (Kelly simplifié) ──────────────────────────────
// confidenceScore est l'échelle 1-5 cochée par l'admin à la publication.
export function suggestStake(balance: number, confidenceScore: number): number {
  const pct = confidenceScore >= 5 ? 0.05   // 5/5 → 5%
            : confidenceScore >= 4 ? 0.03   // 4/5 → 3%
            : confidenceScore >= 3 ? 0.03   // 3/5 → 3%
            : 0.015;                         // 1-2/5 → 1.5%
  const raw = balance * pct;
  // Arrondir à la centaine la plus proche (pratique pour XOF)
  return Math.max(100, Math.round(raw / 100) * 100);
}

// ── GET ou CREATE bankroll ────────────────────────────────────────────────────
export async function getBankroll(userId: string) {
  return prisma.userBankroll.findUnique({
    where: { userId },
    include: {
      bets: {
        include: { pronostic: { include: { match: true } } },
        orderBy: { createdAt: 'desc' },
        take: 50,
      },
    },
  });
}

// ── SET budget (crée ou met à jour) ──────────────────────────────────────────
export async function setBudget(userId: string, totalBudget: number, currency = 'XOF') {
  const existing = await prisma.userBankroll.findUnique({ where: { userId } });
  if (existing) {
    // Ne touche pas au solde courant si c'est juste un ajustement du budget total
    return prisma.userBankroll.update({
      where: { userId },
      data:  { totalBudget, currency },
    });
  }
  return prisma.userBankroll.create({
    data: { userId, totalBudget, currentBalance: totalBudget, currency },
  });
}

// ── RESET complet (cooldown 30 jours) ────────────────────────────────────────
export async function resetBankroll(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new Error('Bankroll introuvable.');

  // Vérifier le cooldown de 30 jours depuis le dernier reset
  const COOLDOWN_DAYS = 30;
  if ((bankroll as any).lastResetAt) {
    const daysSinceReset = (Date.now() - new Date((bankroll as any).lastResetAt).getTime()) / 86400000;
    if (daysSinceReset < COOLDOWN_DAYS) {
      const daysLeft = Math.ceil(COOLDOWN_DAYS - daysSinceReset);
      throw new Error(`Reset disponible dans ${daysLeft} jour${daysLeft > 1 ? 's' : ''}.`);
    }
  }

  return prisma.userBankroll.update({
    where: { userId },
    data:  { currentBalance: bankroll.totalBudget, lastResetAt: new Date() } as any,
  });
}

// ── PLACE BET ─────────────────────────────────────────────────────────────────
export async function placeBet(
  userId:      string,
  pronosticId: string,
  stakedAmount: number,
) {
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  if (!bankroll) throw new Error('Configure ton budget d\'abord.');
  if (stakedAmount <= 0) throw new Error('La mise doit être positive.');
  if (stakedAmount > bankroll.currentBalance) throw new Error('Solde insuffisant.');

  const pronostic = await prisma.pronostic.findUnique({ where: { id: pronosticId } });
  if (!pronostic) {
    // Essai par matchId
    const byMatch = await prisma.pronostic.findUnique({ where: { matchId: pronosticId } });
    if (!byMatch) throw new Error('Pronostic introuvable.');
    pronosticId = byMatch.id;
  }

  // Vérifier qu'il n'y a pas déjà un pari sur ce pronostic
  const existing = await prisma.bankrollBet.findUnique({
    where: { bankrollId_pronosticId: { bankrollId: bankroll.id, pronosticId } },
  });
  if (existing) throw new Error('Tu as déjà misé sur ce pronostic.');

  const pro = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });
  if (!pro) throw new Error('Pronostic introuvable.');

  const suggestedAmount = suggestStake(bankroll.currentBalance, pro.confidenceScore);
  const oddsUsed        = pro.oddsRecommended;
  const potentialGain   = parseFloat((stakedAmount * oddsUsed).toFixed(2));

  // Déduire immédiatement la mise du solde
  const [bet] = await prisma.$transaction([
    prisma.bankrollBet.create({
      data: {
        bankrollId:      bankroll.id,
        pronosticId,
        stakedAmount,
        suggestedAmount,
        oddsUsed,
        potentialGain,
      },
    }),
    prisma.userBankroll.update({
      where: { userId },
      data:  { currentBalance: { decrement: stakedAmount } },
    }),
  ]);

  return bet;
}

// ── SETTLE BETS (appelé quand un résultat est posté) ─────────────────────────
export async function settleBets(pronosticId: string, result: 'WIN' | 'LOSS') {
  const pendingBets = await prisma.bankrollBet.findMany({
    where:   { pronosticId, result: null },
    include: {
      bankroll: { include: { user: { select: { id: true } } } },
    },
  });

  // Récupérer les infos du pronostic pour le message de notif
  const pronostic = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });

  for (const bet of pendingBets) {
    const profit = result === 'WIN'
      ? parseFloat((bet.potentialGain - bet.stakedAmount).toFixed(2))
      : -bet.stakedAmount;

    await prisma.$transaction([
      prisma.bankrollBet.update({
        where: { id: bet.id },
        data:  { result, profit, settledAt: new Date() },
      }),
      ...(result === 'WIN'
        ? [prisma.userBankroll.update({
            where: { id: bet.bankrollId },
            data:  { currentBalance: { increment: bet.potentialGain } },
          })]
        : []),
    ]);

    // Notification personnalisée pour l'utilisateur
    const userId   = bet.bankroll.user.id;
    const currency = bet.bankroll.currency ?? 'XOF';
    const matchStr = pronostic?.match
      ? `${pronostic.match.homeTeam} vs ${pronostic.match.awayTeam}`
      : 'votre pronostic';

    if (result === 'WIN') {
      const gain = profit.toLocaleString('fr-FR');
      notifSvc.sendToUser(userId, {
        title: '🏆 Pronostic Gagnant !',
        body:  `+${gain} ${currency} sur ${matchStr}. Votre bankroll est mis à jour !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    } else {
      const perte = bet.stakedAmount.toLocaleString('fr-FR');
      notifSvc.sendToUser(userId, {
        title: '❌ Pronostic Perdant',
        body:  `-${perte} ${currency} sur ${matchStr}. Ne lâchez pas !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    }
  }

  return pendingBets.length;
}

// ── STATS ─────────────────────────────────────────────────────────────────────
export async function getBankrollStats(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({
    where:   { userId },
    include: { bets: { where: { result: { not: null } } } },
  });
  if (!bankroll) return null;

  const settled = bankroll.bets;
  const wins    = settled.filter(b => b.result === 'WIN').length;
  const losses  = settled.filter(b => b.result === 'LOSS').length;
  const totalProfit = settled.reduce((sum, b) => sum + (b.profit ?? 0), 0);
  const totalStaked = settled.reduce((sum, b) => sum + b.stakedAmount, 0);
  const roi = totalStaked > 0 ? (totalProfit / totalStaked) * 100 : 0;

  return {
    totalBudget:    bankroll.totalBudget,
    currentBalance: bankroll.currentBalance,
    currency:       bankroll.currency,
    totalBets:      settled.length,
    wins,
    losses,
    winRate:        settled.length > 0 ? (wins / settled.length) * 100 : 0,
    totalProfit:    parseFloat(totalProfit.toFixed(2)),
    totalStaked:    parseFloat(totalStaked.toFixed(2)),
    roi:            parseFloat(roi.toFixed(2)),
  };
}
