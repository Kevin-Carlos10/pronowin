/**
 * Probabilités déduites des cotes du marché.
 *
 * Sur Lask Linz – Celtic, l'application affichait deux lectures du même match,
 * à deux onglets d'écart, sans jamais les confronter :
 *
 *     Modèle externe   Lask Linz  < 1 %   ·  Nul 50 %  ·  Celtic 50 %
 *     Cotes 1xBet      Lask Linz 48,5 %   ·  Nul 24 %  ·  Celtic 27,5 %
 *
 * Lask Linz a gagné 4–1.
 *
 * Une cote n'est pas l'avis d'un analyste : c'est le prix d'équilibre d'un
 * marché où de gros volumes s'échangent, corrigé en continu par des
 * professionnels — blessures, compositions, mouvements d'argent. Aucun modèle
 * bâti sur les seuls buts marqués n'approche cette qualité d'information.
 *
 * ⚠️ Ce que ces probabilités ne permettent **pas** : dire que le marché se
 * trompe. Elles le décrivent, elles ne le battent pas. Trouver un écart
 * exploitable demande un modèle indépendant, jugé sur sa calibration.
 */

/** Marge maximale plausible d'un bookmaker sur un 1X2. */
const MARGE_MAX = 0.30;

export interface ProbabilitesMarche {
  /** 0–100, somme ≈ 100 : la marge du bookmaker est retirée. */
  home: number;
  draw: number;
  away: number;
  /** Marge retenue par le bookmaker, en points de pourcentage. */
  margePct: number;
}

/**
 * Convertit un triplet de cotes décimales en probabilités.
 *
 * Rend `null` plutôt qu'un résultat douteux : mieux vaut retomber sur une
 * autre source que publier un chiffre bâti sur une cote aberrante.
 *
 * La marge est retirée **proportionnellement** — la méthode standard, et la
 * seule qui n'introduit pas d'hypothèse supplémentaire. Elle surestime
 * légèrement les outsiders (le fameux *favourite-longshot bias*) ; les
 * méthodes de Shin ou en puissance corrigent ce biais, au prix d'un paramètre
 * qu'il faudrait estimer. À faire seulement quand on aura de quoi le valider.
 */
export function probabilitesDepuisCotes(
  home: number | null | undefined,
  draw: number | null | undefined,
  away: number | null | undefined,
): ProbabilitesMarche | null {
  const cotes = [home, draw, away];

  // Une cote décimale vaut strictement plus que 1 : à 1,00 le pari ne rapporte
  // rien, ce qui ne peut pas être une cote réelle.
  if (!cotes.every(c => typeof c === 'number' && Number.isFinite(c) && c > 1)) {
    return null;
  }

  const inverses = cotes.map(c => 1 / (c as number));
  const somme = inverses.reduce((a, b) => a + b, 0);

  // Somme < 1 : le triplet permettrait un gain garanti quelle que soit l'issue.
  // C'est une donnée corrompue, pas une aubaine.
  //
  // Le seuil est strict — une somme d'exactement 1 décrit un livre équilibré,
  // mathématiquement valide même si aucun bookmaker n'en propose. Refuser ce
  // cas aurait écarté une donnée juste.
  if (somme < 1) return null;
  // Marge démesurée : cotes obsolètes ou marché suspendu.
  if (somme - 1 > MARGE_MAX) return null;

  const pct = (v: number) => Math.round((v / somme) * 1000) / 10;

  return {
    home: pct(inverses[0]),
    draw: pct(inverses[1]),
    away: pct(inverses[2]),
    margePct: Math.round((somme - 1) * 1000) / 10,
  };
}
