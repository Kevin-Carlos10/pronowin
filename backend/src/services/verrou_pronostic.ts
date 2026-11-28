/**
 * Ce qu'un pronostic premium cache, et jusqu'à quand.
 *
 * La règle vivait en double — `pronostics.service.ts` pour la liste,
 * `pronostics.controller.ts` pour le détail — sous la même forme :
 *
 *     const locked = p.isPremium && !isPremium;
 *
 * Deux copies d'une règle d'accès finissent toujours par diverger, et celle-ci
 * décide de ce qu'un utilisateur payant reçoit. Elle vit ici, une fois.
 *
 * ── Un pronostic Premium reste Premium, même après le match ─────────────────
 *
 * Jusqu'au 17 octobre 2026, un match terminé déverrouillait le pronostic pour
 * tous. Décision de l'utilisateur ce jour-là : un gratuit ne doit pas avoir
 * accès à l'historique des pronostics Premium. Option retenue, « visible mais
 * verrouillé » : le gratuit voit qu'il y a eu un pronostic Premium sur ce
 * match et son **résultat**, gagné comme perdu, mais ni le choix de
 * l'analyste, ni la cote, ni l'analyse.
 *
 * Le résultat reste visible pour une raison : masquer seulement les
 * pronostics perdus aurait montré aux gratuits un historique plus flatteur
 * que la réalité, sous une accroche « historique complet ». Le taux de
 * réussite reste calculé sur tous les pronostics publiés.
 */

/**
 * Statuts que le modèle emploie, dans les casses qu'on rencontre.
 *
 * Ne déverrouille plus rien : sert à `premiumSaufMatchTermine`, qui ouvre
 * après le match l'analyse et les commentaires d'un pronostic **gratuit**.
 */
const TERMINE = new Set(['finished', 'FINISHED', 'Finished']);

export function matchTermine(statut: string | null | undefined): boolean {
  if (!statut) return false;
  return TERMINE.has(statut) || statut.toLowerCase() === 'finished';
}

/**
 * Faut-il masquer le contenu payant de ce pronostic ?
 *
 * Avant, pendant et après le match : seul un abonnement l'ouvre.
 *
 * @param estPremium        le pronostic relève-t-il de l'offre payante
 * @param utilisateurPremium l'utilisateur a-t-il un abonnement actif
 */
export function estVerrouille(
  estPremium: boolean,
  utilisateurPremium: boolean,
): boolean {
  return estPremium && !utilisateurPremium;
}
