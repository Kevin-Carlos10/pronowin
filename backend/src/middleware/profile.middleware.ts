import { Response, NextFunction } from 'express';
import { AuthRequest } from './auth.middleware';
import { prisma } from '../lib/prisma';
import { estMajeur } from '../utils/age';

/**
 * Ce qui manque à un profil pour accéder au premium — **règle unique**.
 *
 * Extraite du middleware parce qu'un second appelant en avait besoin : le
 * service d'abonnement, qui ne doit publier les numéros de réception qu'à un
 * profil complet. Redéfinir « complet » à cet endroit-là aurait créé deux
 * règles capables de diverger — et c'est toujours la plus laxiste qui garde la
 * porte.
 *
 * Conditions : au moins un canal vérifié, prénom, nom, **majorité établie**,
 * téléphone.
 */
export async function champsManquants(userId: string): Promise<string[] | null> {
  const user = await prisma.user.findUnique({
    where:  { id: userId },
    select: {
      phoneVerified: true, emailVerified: true, firstName: true,
      lastName: true, birthDate: true, phoneNumber: true,
    },
  });

  if (!user) return null;   // utilisateur introuvable — distinct d'« incomplet »

  const manquants: string[] = [];
  if (!user.phoneVerified && !user.emailVerified) manquants.push('contact_verified');
  if (!user.firstName)   manquants.push('first_name');
  if (!user.lastName)    manquants.push('last_name');
  // La seule présence d'une date ne prouvait rien : ce contrôle acceptait un
  // profil déclarant seize ans. La barrière d'âge n'existait donc que dans le
  // sélecteur de l'application, contournable par un appel direct à l'API.
  if (!estMajeur(user.birthDate)) manquants.push('birth_date');
  if (!user.phoneNumber) manquants.push('phone_number');

  return manquants;
}

/** Vrai si le profil satisfait toutes les conditions ci-dessus. */
export async function estProfilComplet(userId: string): Promise<boolean> {
  const manquants = await champsManquants(userId);
  return manquants !== null && manquants.length === 0;
}

/** Bloque l'accès si le profil n'est pas complet pour le premium. */
export async function requireProfileComplete(
  req: AuthRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const manquants = await champsManquants(req.userId!);

  if (manquants === null) {
    res.status(404).json({ message: 'Utilisateur introuvable.' });
    return;
  }

  if (manquants.length > 0) {
    res.status(403).json({
      code:           'PROFILE_INCOMPLETE',
      message:        'Complète ton profil avant de passer en premium.',
      missing_fields: manquants,
    });
    return;
  }

  next();
}
