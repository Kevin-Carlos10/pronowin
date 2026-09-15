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
 * ── Pourquoi un match terminé ne se verrouille plus ─────────────────────────
 *
 * Ce qui se vend, c'est de connaître le pronostic **avant** le coup d'envoi.
 * Après le coup de sifflet final, il ne reste rien à vendre : le score est
 * public, le pronostic est vérifiable, et le cacher ne protège aucune valeur.
 *
 * Le cacher coûte même quelque chose. L'écran d'accueil annonce un taux de
 * réussite ; un utilisateur gratuit qui ne peut relire aucun pronostic passé
 * n'a aucun moyen de le vérifier. On lui demande de croire un chiffre en lui
 * interdisant d'en contrôler la source. L'historique ouvert est le meilleur
 * argument de vente dont dispose ce produit — et le seul honnête.
 */

/** Statuts que le modèle emploie, dans les casses qu'on rencontre. */
const TERMINE = new Set(['finished', 'FINISHED', 'Finished']);

export function matchTermine(statut: string | null | undefined): boolean {
  if (!statut) return false;
  return TERMINE.has(statut) || statut.toLowerCase() === 'finished';
}

/**
 * Faut-il masquer le contenu payant de ce pronostic ?
 *
 * @param estPremium        le pronostic relève-t-il de l'offre payante
 * @param statutMatch       statut du match rattaché
 * @param utilisateurPremium l'utilisateur a-t-il un abonnement actif
 */
export function estVerrouille(
  estPremium: boolean,
  statutMatch: string | null | undefined,
  utilisateurPremium: boolean,
): boolean {
  if (!estPremium)              return false;
  if (utilisateurPremium)       return false;
  if (matchTermine(statutMatch)) return false;
  return true;
}
