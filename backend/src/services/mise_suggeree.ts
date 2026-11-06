/** Barème éditorial obligatoire. Ce n'est pas une probabilité de victoire. */
export function partSelonConfiance(note: number): number {
  if (!Number.isInteger(note) || note < 1 || note > 5) return 0;
  return note === 5 ? 0.05 : note >= 3 ? 0.03 : 0.015;
}

/** Unité monétaire d'affichage, pas de centaine susceptible de gonfler la mise. */
export function pasDeDevise(devise: string | null | undefined): number {
  return ['XOF','XAF','GNF','JPY','KRW'].includes((devise ?? '').toUpperCase()) ? 1 : 0.01;
}

/** Arrondi inférieur : la mise ne dépasse jamais le pourcentage annoncé. */
export function miseSuggeree(solde: number, note: number,
  devise: string | null | undefined = 'XOF'): number {
  if (!Number.isFinite(solde) || solde <= 0) return 0;
  const facteur = 1 / pasDeDevise(devise);
  const montant = solde * partSelonConfiance(note);
  return Math.min(solde, Math.floor(montant * facteur + 1e-9) / facteur);
}
