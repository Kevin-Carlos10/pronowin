/**
 * Le rendement des pronostics, en unités (constat A8 de l'audit du
 * 24 septembre 2026).
 *
 * La performance affichée était un taux de réussite. Il ne dit rien de la
 * rentabilité : à la cote 1,13, 86 % de réussite perd de l'argent. Le
 * rendement suppose une unité misée sur chaque pronostic réglé, à sa cote
 * conseillée : un gagnant rapporte (cote − 1), un perdant coûte 1, un
 * remboursé rien — et il ne compte pas comme pari.
 */
export function rendementUnites(pronostics: { result: string | null; oddsRecommended: number | null }[]) {
  let unites = 0;
  let paris = 0;
  for (const p of pronostics) {
    if (p.result === 'WIN') { unites += (p.oddsRecommended ?? 1) - 1; paris++; }
    else if (p.result === 'LOSS') { unites -= 1; paris++; }
  }
  return {
    unites:  Math.round(unites * 100) / 100,
    paris,
    // Rendement par unité misée : +10 % = un dixième d'unité gagné par pari.
    roi_pct: paris > 0 ? Math.round((unites / paris) * 1000) / 10 : null,
  };
}
