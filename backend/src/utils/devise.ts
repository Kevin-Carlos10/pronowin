/**
 * Nom d'usage d'une devise, par opposition à son code ISO.
 *
 * Le Bankroll stocke des codes ISO — c'est la bonne donnée : `XOF` est sans
 * ambiguïté, il voyage bien, il ne dépend d'aucune langue. Mais il ne doit pas
 * **s'afficher** tel quel. Ce qui est écrit sur les billets, et ce que les gens
 * disent, c'est « FCFA ».
 *
 * Le mobile l'avait déjà compris (`lib/shared/utils/devise.dart`) et corrigé
 * ses écrans. Les notifications, elles, partaient toujours d'ici avec le code
 * brut :
 *
 *     🏆 Pronostic Gagnant !
 *     +2 000 XOF sur Lyon – Fenerbahçe
 *
 * Une notification n'est pas rattrapable : elle est déjà dans la barre du
 * téléphone quand on s'aperçoit qu'elle parle un langage de banque.
 *
 * ── Sur la duplication ──────────────────────────────────────────────────────
 *
 * Cette table existe aussi côté mobile. Deux copies, deux langages : c'est
 * précisément ce qui diverge. `devise.test.ts` lit les deux fichiers et refuse
 * qu'ils s'éloignent — le contrôle vaut mieux qu'un commentaire demandant de
 * penser à les synchroniser.
 */
const NOMS: Record<string, string> = {
  // Franc CFA d'Afrique de l'Ouest (BCEAO) et d'Afrique centrale (BEAC). Les
  // deux se disent « FCFA » — ils ne sont pas interchangeables à la banque,
  // mais un utilisateur ne voit qu'une seule devise à la fois : la sienne.
  XOF: 'FCFA',
  XAF: 'FCFA',
  GNF: 'GNF',
  EUR: '€',
};

/**
 * Nom à afficher pour un code de devise.
 *
 * Un code inconnu est rendu tel quel : mieux vaut un sigle qu'un montant sans
 * unité, qui ne veut plus rien dire du tout.
 */
export function nomDevise(code: string | null | undefined): string {
  if (!code) return '';
  return NOMS[code.toUpperCase()] ?? code;
}
