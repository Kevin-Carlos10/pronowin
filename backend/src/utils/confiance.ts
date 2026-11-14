/**
 * Indice de confiance de l'analyste — en pourcentage, saisi par lui.
 *
 * ── Deux grandeurs, une seule saisie ──────────────────────────────────────
 *
 * L'analyste saisit un pourcentage (`confidence_pct`, 1 à 99). C'est ce que
 * l'application et le site affichent : son appréciation, en clair, et non une
 * conversion d'étoiles.
 *
 * Le niveau de 1 à 5 (`confidence_score`) en est **déduit**, jamais saisi. Il
 * reste le seul que comprennent le barème de mise (`miseSuggeree`), les
 * recommandations personnalisées et les versions de l'application déjà
 * installées sur les téléphones. Le déduire plutôt que le demander garantit
 * que les deux ne se contredisent jamais.
 *
 * ── Pourquoi pas 100 % ────────────────────────────────────────────────────
 *
 * « 100 % » se lit comme une victoire certaine. Aucun pronostic ne l'est, et
 * l'afficher dans une application de paris serait une promesse trompeuse.
 * La saisie s'arrête à 99.
 */

export const POURCENTAGE_MIN = 1;
export const POURCENTAGE_MAX = 99;

/** Niveau 1–5 déduit du pourcentage, par paliers de 20 points. */
export function niveauDepuisPourcentage(pct: number): number {
  if (pct >= 80) return 5;
  if (pct >= 60) return 4;
  if (pct >= 40) return 3;
  if (pct >= 20) return 2;
  return 1;
}

/**
 * Pourcentage d'un pronostic qui n'en a pas : le milieu de son palier
 * (1 → 10, 2 → 30, 3 → 50, 4 → 70, 5 → 90).
 *
 * Sert aux pronostics publiés avant la saisie en pourcentage, et aux appels
 * qui n'envoient encore qu'un niveau. Le milieu ne flatte ni n'abaisse :
 * redéduire le niveau de ce pourcentage redonne le niveau de départ.
 */
export function pourcentageDepuisNiveau(niveau: number): number {
  const n = Math.min(5, Math.max(1, Math.round(niveau)));
  return n * 20 - 10;
}

/** Le pourcentage à publier pour un pronostic, saisi ou reconstitué. */
export function pourcentageConfiance(p: { confidencePct?: number | null; confidenceScore: number }): number {
  return p.confidencePct ?? pourcentageDepuisNiveau(p.confidenceScore);
}
