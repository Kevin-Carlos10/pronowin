import { prisma } from '../lib/prisma';

/**
 * Ceux qui suivent un match : favori (« Suivre ce match »), ou pari en cours
 * sur son pronostic dans la bankroll. Un utilisateur dans les deux cas ne
 * reçoit qu'une alerte.
 */
export async function suiveursDuMatch(matchId: string, pronosticId: string | null): Promise<string[]> {
  const [favoris, paris] = await Promise.all([
    prisma.userFavoriteMatch.findMany({ where: { matchId }, select: { userId: true } }),
    pronosticId
      ? prisma.bankrollBet.findMany({
          where:  { pronosticId, result: null },
          select: { bankroll: { select: { userId: true } } },
        })
      : Promise.resolve([] as { bankroll: { userId: string } }[]),
  ]);
  return [...new Set([...favoris.map(f => f.userId), ...paris.map(p => p.bankroll.userId)])];
}
