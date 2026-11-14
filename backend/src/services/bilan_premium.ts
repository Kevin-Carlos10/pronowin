/**
 * Bilan public des pronostics Premium : ce que le mur Premium de l'application
 * et la vitrine peuvent annoncer.
 *
 * Deux garde-fous décident si le taux est publié :
 *
 * - l'échantillon : sous ECHANTILLON_MINIMAL paris tranchés, un taux est un
 *   artefact (trois gagnés font « 100 % ») ;
 * - le seuil d'annonce : un taux sous SEUIL_ANNONCE n'est pas mis en avant.
 *   Décision produit du 6 novembre 2026 : un bilan Premium sous 80 % ne
 *   s'affiche pas.
 *
 * Le taux n'est **publié** (`taux_reussite` non nul) que si les deux sont
 * tenus. La règle est appliquée ici, sur le serveur, et pas dans chaque écran :
 * les versions de l'application déjà installées affichent le bilan dès que
 * `taux_reussite` n'est pas nul et que `echantillon_suffisant` est vrai, et
 * la vitrine fait de même. Les retenir ici les fait taire toutes à la fois,
 * sans attendre une mise à jour.
 *
 * Les comptes gagnés / perdus restent dans la réponse : ils ne sont affichés
 * qu'accompagnés du taux.
 */

export const ECHANTILLON_MINIMAL = 10;
export const SEUIL_ANNONCE       = 80;

export interface BilanPremium {
  periode_jours:         number;
  pronostics_tranches:   number;
  gagnes:                number;
  perdus:                number;
  /** `null` dès que le bilan n'est pas annonçable — voir `affichable`. */
  taux_reussite:         number | null;
  echantillon_minimal:   number;
  echantillon_suffisant: boolean;
  seuil_annonce:         number;
  affichable:            boolean;
}

/**
 * Les remboursés (PUSH) ne sont pas comptés : ni gagnés ni perdus, ils ne
 * disent rien de la justesse d'un pronostic.
 */
export function calculerBilanPremium(gagnes: number, perdus: number, jours: number): BilanPremium {
  const tranches   = gagnes + perdus;
  const suffisant  = tranches >= ECHANTILLON_MINIMAL;
  // Comparaison sur les entiers, pas sur le pourcentage arrondi : 79,6 %
  // s'arrondirait à « 80 % » et passerait le seuil qu'il n'atteint pas.
  const atteint    = tranches > 0 && gagnes * 100 >= SEUIL_ANNONCE * tranches;
  const affichable = suffisant && atteint;

  return {
    periode_jours:         jours,
    pronostics_tranches:   tranches,
    gagnes,
    perdus,
    taux_reussite:         affichable ? Math.round((gagnes / tranches) * 100) : null,
    echantillon_minimal:   ECHANTILLON_MINIMAL,
    echantillon_suffisant: suffisant,
    seuil_annonce:         SEUIL_ANNONCE,
    affichable,
  };
}
