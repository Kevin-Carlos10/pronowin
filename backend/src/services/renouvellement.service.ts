import { prisma } from '../lib/prisma';

/**
 * Renouveler en un geste (23 novembre 2026).
 *
 * Le Mobile Money ne se reconduit pas : chaque échéance est une occasion de
 * perdre l'abonné. Le rappel « Ton Premium expire demain » menait à
 * l'onglet Compte, d'où il fallait rouvrir l'offre, choisir la formule, la
 * méthode, puis payer. Le lien mène désormais à l'étape de paiement de la
 * formule de l'abonné — l'application n'a plus qu'à proposer « Payer ».
 */
export type Formule = 'premium_monthly' | 'premium_annual';

/** Au-delà de 200 jours, un abonnement est annuel (365 j) ; sinon mensuel (30 j). */
export function formuleDe(debut: Date, fin: Date): Formule {
  return (fin.getTime() - debut.getTime()) / 86_400_000 > 200 ? 'premium_annual' : 'premium_monthly';
}

/** Le lien du rappel : l'étape de paiement de la formule, ou l'offre si on l'ignore. */
export function lienRenouvellement(formule: Formule | null): string {
  return formule ? `/compte/activer-premium?renouveler=${formule}` : '/compte/activer-premium';
}

export interface DernierAbonnement {
  formule: Formule;
  /** Vendu par Apple ou Google : la boutique le renouvelle elle-même. */
  boutique: boolean;
}

/** Le dernier abonnement Premium de chaque compte demandé, en une requête. */
export async function derniersAbonnements(userIds: string[]): Promise<Map<string, DernierAbonnement>> {
  const resultat = new Map<string, DernierAbonnement>();
  if (userIds.length === 0) return resultat;
  const abonnements = await prisma.subscription.findMany({
    where:   { userId: { in: userIds }, plan: 'premium' },
    orderBy: { endDate: 'desc' },
    select:  { userId: true, startDate: true, endDate: true, paymentMethod: true },
  });
  for (const a of abonnements) {
    if (resultat.has(a.userId)) continue;   // le plus récent d'abord
    resultat.set(a.userId, {
      formule:  formuleDe(a.startDate, a.endDate),
      boutique: a.paymentMethod.startsWith('iap_'),
    });
  }
  return resultat;
}
