/**
 * Le taux de réussite, réservé aux abonnés Premium (23 novembre 2026).
 *
 * Décision de l'utilisateur : le pourcentage de réussite des pronostics
 * PronoWin — et les comptes qui le donnent d'un coup d'œil (« 18 gagnés sur
 * 25 ») — ne s'affiche qu'aux abonnés Premium, partout : l'application, la
 * vitrine, le bilan de la semaine. Pour les autres, le bloc disparaît, sans
 * cadenas à la place. Le résultat de chaque pronostic (gagné, perdu) reste
 * visible de tous, dans l'historique et sur chaque match.
 *
 * La règle est tenue ici, sur le serveur : les versions de l'application déjà
 * installées et la vitrine se taisent dès que le taux manque, sans attendre
 * une mise à jour. Ce qui ne part pas du serveur ne peut pas s'afficher.
 *
 * Ne concerne pas les taux personnels (bankroll, votes, classement de la
 * communauté) : ce sont ceux de la personne, ou des autres membres.
 */
import { prisma } from '../lib/prisma';
import { premiumEnCours } from '../utils/premium';

/** L'utilisateur [userId] a-t-il un Premium en cours ? Un invité, jamais. */
export async function voitLeTaux(userId?: string | null): Promise<boolean> {
  if (!userId) return false;
  const u = await prisma.user.findUnique({
    where:  { id: userId },
    select: { subscriptionPlan: true, subscriptionExpiresAt: true },
  });
  return !!u && premiumEnCours(u);
}

export interface StatsAccueil {
  winRate: number | null;
  streak: number;
  totalFinished: number | null;
  wins: number | null;
  publishedToday: number;
  upcoming: number;
}

/**
 * Les statistiques de l'accueil sans le taux, ni les deux comptes qui le
 * donnent. La série en cours, les publiés du jour et les matchs à venir
 * restent : ce ne sont pas des pourcentages.
 *
 * `totalFinished` nul plutôt que zéro n'y change rien pour les versions
 * installées : elles lisent `?? 0`, et affichent « — » sous trois pronostics
 * tranchés — jamais « 0 % ».
 */
export function statsSansTaux(s: StatsAccueil): StatsAccueil {
  return { ...s, winRate: null, totalFinished: null, wins: null };
}
