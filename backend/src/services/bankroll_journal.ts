/**
 * Le journal des mouvements de la bankroll (constat B1), partagé par les mises
 * simples, les combinés et les couvertures enregistrées (27 novembre 2026).
 *
 * Sorti de `bankroll.service.ts` pour que les combinés et les couvertures s'en
 * servent sans dépendance circulaire : le règlement des mises simples appelle
 * le leur.
 */
import { Prisma } from '@prisma/client';
import { pasDeDevise } from './mise_suggeree';

export type Tx = Prisma.TransactionClient;
export type TypeMouvement =
  'ouverture' | 'budget' | 'devise' | 'mise' | 'reglement' | 'correction_mise' | 'reinitialisation'
  | 'annulation' | 'combine' | 'couverture';

/**
 * Un montant ramené à l'unité de la devise, par défaut.
 *
 * Le franc CFA n'a pas de centimes. Un gain potentiel de 1 234 × 1,73 était
 * gardé à 2 134,82 FCFA — une somme qu'aucun bookmaker ne verse —, et ces
 * centimes fictifs, additionnés en virgule flottante, rendaient le solde
 * inexact. En unités entières, un nombre à virgule flottante est exact : les
 * additions répétées du solde ne dérivent plus.
 */
export function aLUnite(montant: number, devise: string | null | undefined): number {
  const facteur = 1 / pasDeDevise(devise);
  return Math.floor(montant * facteur + 1e-9) / facteur;
}

/** Le solde à la précision de la devise : au centime près pour l'euro. */
export function soldeExact(solde: number, devise: string | null | undefined): number {
  const facteur = 1 / pasDeDevise(devise);
  return Math.round(solde * facteur) / facteur;
}

/**
 * Déplace le solde disponible et l'inscrit au journal, dans la transaction de
 * l'appelant. C'est le seul chemin qui modifie `currentBalance` : la somme
 * des mouvements d'une bankroll vaut ainsi son solde.
 *
 * `siSolde` : ne bouge que si le solde vaut encore ce montant — la garde de
 * placeBet contre deux mises simultanées. Renvoie le solde après le
 * mouvement, ou `null` si la garde a refusé.
 */
export async function mouvoir(
  tx: Tx, bankrollId: string, devise: string, montant: number, type: TypeMouvement,
  opts: { pariId?: string; motif?: string; siSolde?: number } = {},
): Promise<number | null> {
  const where: Prisma.UserBankrollWhereInput = { id: bankrollId };
  if (opts.siSolde !== undefined) where.currentBalance = opts.siSolde;
  const r = await tx.userBankroll.updateMany({ where, data: { currentBalance: { increment: montant } } });
  if (r.count === 0) return null;

  // La ligne est verrouillée par l'UPDATE jusqu'à la fin de la transaction :
  // ce qu'on relit est notre écriture, pas celle d'un autre.
  const lu = await tx.userBankroll.findUnique({ where: { id: bankrollId } });
  let solde = lu!.currentBalance;
  const exact = soldeExact(solde, devise);
  if (exact !== solde) {
    await tx.userBankroll.update({ where: { id: bankrollId }, data: { currentBalance: exact } });
    solde = exact;
  }
  await tx.bankrollMouvement.create({ data: {
    bankrollId, type, montant, soldeApres: solde, pariId: opts.pariId ?? null, motif: opts.motif ?? null,
    creeLe: new Date(),
  } });
  return solde;
}
