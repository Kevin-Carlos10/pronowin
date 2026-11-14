/**
 * Premium en cours : la règle unique (14 novembre 2026).
 *
 * Le plan `premium` ET une échéance future — ou aucune échéance (Premium
 * accordé sans limite). C'est la règle qui ouvre réellement l'accès :
 * `premiumMiddleware`, le badge des commentaires, et l'application
 * (`UserEntity.isPremium`).
 *
 * Aucune tâche ne repasse en `free` un abonnement échu : le plan reste
 * `premium` après l'échéance, et seule la date dit s'il court encore. Le
 * filtre « Premium » de la liste des utilisateurs du panneau ne lisait que le
 * plan : il montrait des comptes dont l'abonnement était expiré depuis
 * longtemps, affichés « Gratuit » sur leur propre ligne. Et les compteurs,
 * eux, oubliaient les Premium sans échéance.
 */
import type { Prisma } from '@prisma/client';

export interface EtatAbonnement {
  subscriptionPlan?: string | null;
  subscriptionExpiresAt?: Date | null;
}

export function premiumEnCours(u: EtatAbonnement, maintenant: Date = new Date()): boolean {
  return u.subscriptionPlan === 'premium'
    && (!u.subscriptionExpiresAt || u.subscriptionExpiresAt > maintenant);
}

/** Le même critère, en filtre Prisma. */
export function filtrePremiumEnCours(maintenant: Date = new Date()): Prisma.UserWhereInput {
  return {
    subscriptionPlan: 'premium',
    OR: [{ subscriptionExpiresAt: null }, { subscriptionExpiresAt: { gt: maintenant } }],
  };
}

/** Sans Premium en cours : gratuits, et Premium échus. */
export function filtreSansPremium(maintenant: Date = new Date()): Prisma.UserWhereInput {
  return { NOT: filtrePremiumEnCours(maintenant) };
}

/** Premium échu : le plan est resté `premium`, l'échéance est passée. */
export function filtrePremiumEchu(maintenant: Date = new Date()): Prisma.UserWhereInput {
  return { subscriptionPlan: 'premium', subscriptionExpiresAt: { lte: maintenant } };
}
