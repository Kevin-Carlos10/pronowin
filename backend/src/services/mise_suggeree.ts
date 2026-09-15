/**
 * Quelle mise proposer, et sous quel nom.
 *
 * ── Ce que ce calcul n'est pas ─────────────────────────────────────────────
 *
 * Il s'appelait « Kelly simplifié ». Le critère de Kelly met en rapport une
 * **probabilité** et une **cote** pour déterminer la fraction optimale d'un
 * capital. Rien de tel ici : on applique une part fixe selon la note de 1 à 5
 * que l'analyste a cochée à la publication. C'est une règle de prudence
 * éditoriale, parfaitement défendable — mais lui emprunter le nom d'une
 * formule mathématique lui prête une autorité qu'elle n'a pas.
 *
 * Le nom retenu dit ce que la chose fait : une part du capital, choisie selon
 * le niveau de confiance de l'analyste.
 *
 * ── Trois défauts de calcul ────────────────────────────────────────────────
 *
 * 1. `Math.max(100, …)` imposait un plancher de 100 **sans regarder le
 *    solde**. Avec 50 en banque, l'application conseillait de miser 100 :
 *    davantage que ce que l'utilisateur possède.
 *
 * 2. L'arrondi à la centaine était pensé pour le franc CFA et appliqué à
 *    toutes les devises. En euros, arrondir une mise à la centaine n'a aucun
 *    sens. Le Bankroll porte pourtant la devise depuis toujours.
 *
 * 3. Le même arrondi écrasait les petits capitaux : avec 1 000 en banque et
 *    une note de 4, la part de 3 % vaut 30, l'arrondi à la centaine rendait 0,
 *    et le plancher le remontait à 100 — soit 10 % du capital, trois fois la
 *    part annoncée. Le pas s'affine désormais tant qu'il dépasse la mise.
 */

/** Part du capital engagée, selon la note de confiance de l'analyste (1-5). */
export function partSelonConfiance(note: number): number {
  if (note >= 5) return 0.05;
  if (note >= 3) return 0.03;
  return 0.015;
}

/**
 * Pas d'arrondi d'affichage, par devise.
 *
 * Le franc CFA et le franc guinéen n'ont pas de subdivision en usage et leurs
 * montants courants se comptent par centaines ; l'euro se compte à l'unité.
 * Une devise inconnue prend le pas le plus fin : mieux vaut un montant précis
 * qu'un montant arrondi selon les habitudes d'un autre pays.
 */
const PAS_PAR_DEVISE: Record<string, number> = {
  XOF: 100,
  XAF: 100,
  GNF: 100,
  EUR: 1,
};

export function pasDeDevise(devise: string | null | undefined): number {
  return PAS_PAR_DEVISE[(devise ?? '').toUpperCase()] ?? 1;
}

/**
 * Arrondit [montant] au pas, en affinant le pas tant qu'il dépasse le montant.
 *
 * Sans cet affinage, toute mise inférieure à un demi-pas tombait à zéro, et le
 * plancher la remontait bien au-dessus de la part voulue.
 */
function arrondirAuPas(montant: number, pas: number): number {
  let p = pas;
  while (p > 1 && p > montant) p = Math.max(1, Math.floor(p / 10));
  return Math.round(montant / p) * p;
}

/**
 * La mise proposée pour ce capital et cette note.
 *
 * Elle ne dépasse jamais [solde] : proposer plus que ce qu'on a n'est pas un
 * conseil, c'est une erreur d'affichage.
 */
export function miseSuggeree(
  solde: number,
  note: number,
  devise: string | null | undefined = 'XOF',
): number {
  if (!Number.isFinite(solde) || solde <= 0) return 0;

  const brut = solde * partSelonConfiance(note);
  const arrondi = arrondirAuPas(brut, pasDeDevise(devise));

  // Au moins quelque chose tant qu'il reste de quoi miser, jamais plus que le
  // solde.
  return Math.min(solde, Math.max(1, arrondi));
}
