import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';

/**
 * « Qui va gagner ? » — le vote des fans avant le match (26 octobre 2026),
 * comme sur Sofascore.
 *
 * Avant le coup d'envoi, chacun choisit l'équipe à domicile, le nul ou
 * l'équipe à l'extérieur, puis voit la répartition. Un vote par compte et par
 * match, modifiable jusqu'au coup d'envoi ; ensuite, les votes sont clos et
 * la répartition reste visible de tous. Seule la répartition est publique,
 * jamais qui a voté quoi.
 *
 * Ce n'est pas un pari : rien n'est misé, aucune cote n'est montrée — la
 * carte s'affiche aussi sur iPhone.
 */

export type ChoixVote = '1' | 'N' | '2';
export const CHOIX_VOTE: ChoixVote[] = ['1', 'N', '2'];

/** Le match, par son identifiant ou celui de son pronostic. */
async function matchDe(id: string) {
  const select = { id: true, status: true, matchDate: true } as const;
  return (await prisma.match.findUnique({ where: { id }, select }))
    ?? (await prisma.pronostic.findUnique({ where: { id }, select: { match: { select } } }))?.match
    ?? null;
}

/** Ouvert tant que le match n'a pas commencé. */
const ouvert = (m: { status: string; matchDate: Date }, maintenant: Date) =>
  m.status === 'SCHEDULED' && m.matchDate.getTime() > maintenant.getTime();

/**
 * Des pourcentages entiers dont la somme fait 100 (méthode du plus fort
 * reste) : 33 / 33 / 33 laisserait le lecteur chercher le point manquant.
 */
export function pourcentages(compte: [number, number, number]): [number, number, number] {
  const total = compte[0] + compte[1] + compte[2];
  if (!total) return [0, 0, 0];
  const exacts = compte.map(n => n / total * 100);
  const entiers = exacts.map(Math.floor) as [number, number, number];
  const reste = 100 - (entiers[0] + entiers[1] + entiers[2]);
  const ordre = [0, 1, 2].sort((a, b) => (exacts[b] - entiers[b]) - (exacts[a] - entiers[a]));
  for (let k = 0; k < reste; k++) entiers[ordre[k]]++;
  return entiers;
}

export async function resumeVotes(id: string, userId?: string | null, maintenant = new Date()) {
  const match = await matchDe(id);
  if (!match) return null;
  const [groupes, mien] = await Promise.all([
    prisma.voteMatch.groupBy({ by: ['choix'], where: { matchId: match.id }, _count: { _all: true } }),
    userId ? prisma.voteMatch.findUnique({ where: { matchId_userId: { matchId: match.id, userId } }, select: { choix: true } })
           : Promise.resolve(null),
  ]);
  const nb = (c: ChoixVote) => groupes.find(g => g.choix === c)?._count._all ?? 0;
  const compte: [number, number, number] = [nb('1'), nb('N'), nb('2')];
  const [pDom, pNul, pExt] = pourcentages(compte);
  return {
    ouvert: ouvert(match, maintenant),
    total:  compte[0] + compte[1] + compte[2],
    dom: compte[0], nul: compte[1], ext: compte[2],
    pourcentages: { dom: pDom, nul: pNul, ext: pExt },
    mon_vote: (mien?.choix ?? null) as ChoixVote | null,
  };
}

export type ResumeVotes = NonNullable<Awaited<ReturnType<typeof resumeVotes>>>;

/** Vote, ou change son vote, jusqu'au coup d'envoi ; rend la répartition. */
export async function voter(id: string, userId: string, choix: unknown, maintenant = new Date()): Promise<ResumeVotes> {
  if (typeof choix !== 'string' || !(CHOIX_VOTE as string[]).includes(choix)) {
    throw new ErreurMetier('Choix invalide : 1, N ou 2.', 422);
  }
  const match = await matchDe(id);
  if (!match) throw new ErreurMetier('Match introuvable.', 404);
  if (!ouvert(match, maintenant)) throw new ErreurMetier('Les votes sont clos : le match a commencé.', 409);
  await prisma.voteMatch.upsert({
    where:  { matchId_userId: { matchId: match.id, userId } },
    create: { matchId: match.id, userId, choix },
    update: { choix },
  });
  return (await resumeVotes(match.id, userId, maintenant))!;
}
