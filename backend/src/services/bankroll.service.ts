import { NotificationService } from './notification.service';
import { nomDevise } from '../utils/devise';
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

  // Déduction atomique et conditionnelle : le WHERE currentBalance>=stakedAmount est
  // évalué par Postgres au moment de l'UPDATE (verrou ligne), pas au moment de la
  // lecture ci-dessus — évite qu'un pari concurrent fasse passer le solde en négatif.
  const bet = await prisma.$transaction(async (tx) => {
    const decremented = await tx.userBankroll.updateMany({
      where: { userId, currentBalance: { gte: stakedAmount } },
      data:  { currentBalance: { decrement: stakedAmount } },
    });
    if (decremented.count === 0) throw new Error('Solde insuffisant.');

    return tx.bankrollBet.create({
      data: {
        bankrollId:      bankroll.id,
        pronosticId,
        stakedAmount,
        suggestedAmount,
        oddsUsed,
        potentialGain,
      },
    });
  });

  return bet;
}

// ── SETTLE BETS (appelé quand un résultat est posté) ─────────────────────────
export async function settleBets(pronosticId: string, result: 'WIN' | 'LOSS' | 'PUSH') {
  const pendingBets = await prisma.bankrollBet.findMany({
    where:   { pronosticId, result: null },
    include: {
      bankroll: { include: { user: { select: { id: true } } } },
    },
  });
  if (pendingBets.length === 0) return 0;

  // Récupérer les infos du pronostic pour le message de notif
  const pronostic = await prisma.pronostic.findUnique({
    where:   { id: pronosticId },
    include: { match: true },
  });

  // Un seul aller-retour DB (une seule transaction) pour tous les paris à régler,
  // au lieu d'une transaction séquentielle par pari (qui devient très lent quand
  // beaucoup d'utilisateurs ont misé sur le même pronostic).
  const ops: ReturnType<typeof prisma.bankrollBet.update>[] = [];
  const notifJobs: Array<{ userId: string; currency: string; profit: number; stakedAmount: number }> = [];

  for (const bet of pendingBets) {
    // PUSH (marché remboursé, ex. handicap asiatique sur ligne ronde) :
    // ni gain ni perte, la mise est simplement rendue.
    const profit = result === 'WIN'
      ? parseFloat((bet.potentialGain - bet.stakedAmount).toFixed(2))
      : result === 'PUSH' ? 0
      : -bet.stakedAmount;

    ops.push(prisma.bankrollBet.update({
      where: { id: bet.id },
      data:  { result, profit, settledAt: new Date() },
    }));

    if (result === 'WIN') {
      ops.push(prisma.userBankroll.update({
        where: { id: bet.bankrollId },
        data:  { currentBalance: { increment: bet.potentialGain } },
      }) as any);
    } else if (result === 'PUSH') {
      ops.push(prisma.userBankroll.update({
        where: { id: bet.bankrollId },
        data:  { currentBalance: { increment: bet.stakedAmount } },
      }) as any);
    }

    notifJobs.push({
      userId:       bet.bankroll.user.id,
      currency:     bet.bankroll.currency ?? 'XOF',
      profit,
      stakedAmount: bet.stakedAmount,
    });
  }

  await prisma.$transaction(ops);

  // Notifications envoyées après coup, en parallèle (déjà fire-and-forget avant ce correctif)
  const matchStr = pronostic?.match
    ? `${pronostic.match.homeTeam} vs ${pronostic.match.awayTeam}`
    : 'votre pronostic';

  for (const { userId, currency, profit, stakedAmount } of notifJobs) {
    if (result === 'WIN') {
      const gain = profit.toLocaleString('fr-FR');
      notifSvc.sendToUser(userId, {
        title: '🏆 Pronostic Gagnant !',
        body:  `+${gain} ${nomDevise(currency)} sur ${matchStr}. Votre bankroll est mis à jour !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    } else if (result === 'PUSH') {
      const remb = stakedAmount.toLocaleString('fr-FR');
      notifSvc.sendToUser(userId, {
        title: '🔄 Pronostic remboursé',
        body:  `${remb} ${nomDevise(currency)} de mise remboursée sur ${matchStr}.`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    } else {
      const perte = stakedAmount.toLocaleString('fr-FR');
      notifSvc.sendToUser(userId, {
        title: '❌ Pronostic Perdant',
        body:  `-${perte} ${nomDevise(currency)} sur ${matchStr}. Ne lâchez pas !`,
        data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
      }).catch(() => {});
    }
  }

  return pendingBets.length;
}

// ── ADMIN — Liste de toutes les bankrolls ─────────────────────────────────────
// Vue d'ensemble pour l'admin : un utilisateur n'apparaît que s'il a configuré
// un budget (sinon rien à montrer). Les stats (taux de réussite, ROI) sont
// recalculées ici plutôt que dénormalisées, cohérent avec getBankrollStats().
export async function listBankrolls(params: {
  page:     number;
  perPage:  number;
  search?:  string; // pseudo, téléphone ou email
  sortBy?:  'currentBalance' | 'totalBudget' | 'createdAt' | 'pseudo';
  sortDir?: 'asc' | 'desc';
}) {
  const { page, perPage, search, sortBy = 'currentBalance', sortDir = 'desc' } = params;

  const where: any = {};
  if (search) {
    where.user = {
      OR: [
        { pseudo:      { contains: search, mode: 'insensitive' } },
        { phoneNumber: { contains: search } },
        { email:       { contains: search, mode: 'insensitive' } },
      ],
    };
  }

  // `sortBy` vient de la query string : sans liste blanche, une valeur inconnue
  // fait lever Prisma (500) et n'importe quel champ du modèle devient un
  // critère d'ordre. Même correctif que sur la liste des utilisateurs.
  const SORTABLE = new Set(['currentBalance', 'totalBudget', 'createdAt', 'pseudo']);
  const col = SORTABLE.has(sortBy) ? sortBy : 'currentBalance';
  const dir = sortDir === 'asc' ? 'asc' : 'desc';

  // Le tri par pseudo porte sur la relation user — reste séparé du tri sur
  // les colonnes propres à UserBankroll pour garder un orderBy Prisma valide.
  const orderBy: any = col === 'pseudo'
    ? { user: { pseudo: dir } }
    : { [col]: dir };

  const [bankrolls, total] = await Promise.all([
    prisma.userBankroll.findMany({
      where, orderBy, skip: (page - 1) * perPage, take: perPage,
      include: {
        user: { select: { id: true, pseudo: true, phoneNumber: true, email: true, avatarUrl: true } },
        bets: { select: { result: true, profit: true, stakedAmount: true } },
      },
    }),
    prisma.userBankroll.count({ where }),
  ]);

  const data = bankrolls.map(b => {
    const settled  = b.bets.filter(bet => bet.result !== null);
    const decisive = settled.filter(bet => bet.result !== 'PUSH');
    const wins     = decisive.filter(bet => bet.result === 'WIN').length;
    const totalProfit = settled.reduce((sum, bet) => sum + (bet.profit ?? 0), 0);
    const totalStaked = decisive.reduce((sum, bet) => sum + bet.stakedAmount, 0);

    return {
      user_id:         b.userId,
      pseudo:          b.user.pseudo,
      phone_number:    b.user.phoneNumber,
      email:            b.user.email,
      avatar_url:       b.user.avatarUrl,
      total_budget:     b.totalBudget,
      current_balance:  b.currentBalance,
      currency:         b.currency,
      total_bets:       b.bets.length,
      pending_bets:     b.bets.length - settled.length,
      wins,
      losses:           decisive.length - wins,
      win_rate:         decisive.length > 0 ? parseFloat(((wins / decisive.length) * 100).toFixed(1)) : null,
      total_profit:     parseFloat(totalProfit.toFixed(2)),
      roi:              totalStaked > 0 ? parseFloat(((totalProfit / totalStaked) * 100).toFixed(1)) : null,
      last_reset_at:    b.lastResetAt,
      created_at:       b.createdAt,
    };
  });

  return { data, total, page, per_page: perPage, total_pages: Math.ceil(total / perPage) };
}

/**
 * ADMIN — Agrégats sur l'ensemble des bankrolls.
 *
 * La page listait les comptes un par un sans jamais dire si la fonctionnalité
 * marche : combien de budget est confié, combien de paris attendent leur
 * règlement, et surtout si l'ensemble des utilisateurs gagne ou perd. Ces
 * quatre chiffres se lisent en une seconde et remplacent une lecture ligne à
 * ligne.
 */
export async function listBankrollsStats() {
  const [agg, bets] = await Promise.all([
    prisma.userBankroll.aggregate({
      _count: { _all: true },
      _sum:   { totalBudget: true, currentBalance: true },
    }),
    prisma.bankrollBet.findMany({ select: { result: true, profit: true, stakedAmount: true } }),
  ]);

  const settled  = bets.filter(b => b.result !== null);
  const decisive = settled.filter(b => b.result !== 'PUSH');   // PUSH = mise rendue
  const wins     = decisive.filter(b => b.result === 'WIN').length;
  const profit   = settled.reduce((s, b) => s + (b.profit ?? 0), 0);
  const staked   = decisive.reduce((s, b) => s + b.stakedAmount, 0);

  return {
    bankrolls:     agg._count._all,
    total_budget:  Math.round(agg._sum.totalBudget    ?? 0),
    total_balance: Math.round(agg._sum.currentBalance ?? 0),
    total_bets:    bets.length,
    pending_bets:  bets.length - settled.length,
    wins, losses:  decisive.length - wins,
    // Sur zéro pari réglé, un « 0 % » se lirait comme un mauvais résultat
    // alors qu'il n'y a simplement rien à mesurer : on renvoie null.
    win_rate:      decisive.length > 0 ? +((wins / decisive.length) * 100).toFixed(1) : null,
    total_profit:  Math.round(profit),
    roi:           staked > 0 ? +((profit / staked) * 100).toFixed(1) : null,
  };
}

// ── STATS ─────────────────────────────────────────────────────────────────────
export async function getBankrollStats(userId: string) {
  const bankroll = await prisma.userBankroll.findUnique({
    where:   { userId },
    include: { bets: { where: { result: { not: null } } } },
  });
  if (!bankroll) return null;

  const settled = bankroll.bets;
  // Les remboursés (PUSH) ne sont ni des victoires ni des défaites — on les
  // exclut du taux de réussite et de la base de calcul du ROI (la mise a été
  // rendue, elle n'a jamais été réellement "à risque").
  const decisive = settled.filter(b => b.result !== 'PUSH');
  const wins     = decisive.filter(b => b.result === 'WIN').length;
  const losses   = decisive.filter(b => b.result === 'LOSS').length;
  const pushes   = settled.length - decisive.length;
  const totalProfit = settled.reduce((sum, b) => sum + (b.profit ?? 0), 0);
  const totalStaked = decisive.reduce((sum, b) => sum + b.stakedAmount, 0);
  const roi = totalStaked > 0 ? (totalProfit / totalStaked) * 100 : 0;

  return {
    totalBudget:    bankroll.totalBudget,
    currentBalance: bankroll.currentBalance,
    currency:       bankroll.currency,
    totalBets:      settled.length,
    wins,
    losses,
    pushes,
    winRate:        decisive.length > 0 ? (wins / decisive.length) * 100 : 0,
    totalProfit:    parseFloat(totalProfit.toFixed(2)),
    totalStaked:    parseFloat(totalStaked.toFixed(2)),
    roi:            parseFloat(roi.toFixed(2)),
  };
}
