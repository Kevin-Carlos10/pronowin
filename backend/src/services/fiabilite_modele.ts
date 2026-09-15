/**
 * Quand la sortie du modèle externe ne veut rien dire.
 *
 * Le fournisseur (API-Football) donnait sur Lask Linz – Celtic :
 *
 *     Lask Linz  0 %      Nul 50 %      Celtic 50 %
 *     Forme 0/100 · Attaque 0/100 · Défense 0/100 · Buts 0/100 · H2H 0/100
 *
 * Lask Linz a gagné 4–1.
 *
 * Ce n'est pas une prédiction qui s'est trompée, c'est une prédiction qui
 * n'existait pas. Aucun modèle calibré ne donne 0 % à une équipe de football,
 * et aucun ne place 100 % de l'avantage d'un seul côté sur **tous** les
 * critères à la fois — forme, attaque, défense, buts et confrontations. Ces
 * valeurs sont des butées : le signe qu'il n'y avait pas de données à comparer.
 *
 * Le service applique déjà le principe à l'axe 0/0 : « ce n'est pas une
 * égalité, c'est une absence de donnée ». Il manquait le cas jumeau, 0/100,
 * qui porte le même vide sous une apparence de certitude — et c'est celui qui
 * trompe, parce qu'il a l'air d'une mesure.
 *
 * Afficher ça sous le titre « Pourquoi ce pronostic » prête au fournisseur une
 * conviction qu'il n'a pas, sur l'écran même où l'utilisateur décide de miser.
 */

export interface AxeComparaison { label: string; home: number; away: number }

/** Une valeur est-elle collée à une butée ? */
const saturee = (v: number) => v <= 0 || v >= 100;

/**
 * Probabilité en dessous de laquelle le modèle prétend l'impossible.
 *
 * Au football, l'équipe la plus dominée garde quelques points de chance —
 * un but contre son camp, une expulsion, un penalty. En annoncer moins de 2 %
 * n'est pas de la confiance, c'est une butée numérique.
 */
export const PROBABILITE_PLANCHER = 2;

export interface Verdict {
  exploitable: boolean;
  /** Ce qui a disqualifié la sortie — pour le journal, jamais pour l'écran. */
  raison?: string;
}

export function evaluerFiabilite(p: {
  percentHome: number; percentDraw: number; percentAway: number;
  comparisons: AxeComparaison[];
}): Verdict {
  const { percentHome, percentDraw, percentAway, comparisons } = p;
  const somme = percentHome + percentDraw + percentAway;

  // Aucune probabilité : le fournisseur n'a rien renvoyé pour ce match.
  if (somme <= 0) {
    return { exploitable: false, raison: 'aucune probabilité' };
  }

  // Les trois issues doivent former un tout cohérent. Une somme qui s'en
  // éloigne signale une réponse tronquée, pas un modèle audacieux.
  if (Math.abs(somme - 100) > 5) {
    return { exploitable: false, raison: `somme des probabilités = ${somme} %` };
  }

  // Une issue déclarée quasi impossible.
  const minimum = Math.min(percentHome, percentDraw, percentAway);
  if (minimum < PROBABILITE_PLANCHER) {
    return { exploitable: false, raison: `probabilité minimale de ${minimum} %` };
  }

  // Tous les critères collés aux butées : le modèle ne discrimine pas, il
  // sature. Un seul axe à 100/0 reste plausible — une équipe peut avoir gagné
  // toutes ses confrontations. Les cinq à la fois, non.
  if (comparisons.length >= 3 &&
      comparisons.every(a => saturee(a.home) && saturee(a.away))) {
    return { exploitable: false, raison: 'tous les axes saturés (0/100)' };
  }

  return { exploitable: true };
}
