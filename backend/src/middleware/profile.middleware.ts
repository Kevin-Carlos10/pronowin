import { Response, NextFunction } from 'express';
import { AuthRequest } from './auth.middleware';
import { prisma } from '../lib/prisma';

/**
 * Bloque l'accès si le profil n'est pas complet pour le premium.
 * Conditions : au moins un canal vérifié + firstName + lastName + birthDate.
 */
export async function requireProfileComplete(
  req: AuthRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const user = await prisma.user.findUnique({
    where:  { id: req.userId! },
    select: { phoneVerified: true, emailVerified: true, firstName: true, lastName: true, birthDate: true },
  });

  if (!user) { res.status(404).json({ message: 'Utilisateur introuvable.' }); return; }

  const missingFields: string[] = [];
  if (!user.phoneVerified && !user.emailVerified) missingFields.push('contact_verified');
  if (!user.firstName) missingFields.push('first_name');
  if (!user.lastName)  missingFields.push('last_name');
  if (!user.birthDate) missingFields.push('birth_date');

  if (missingFields.length > 0) {
    res.status(403).json({
      code:           'PROFILE_INCOMPLETE',
      message:        'Complète ton profil avant de passer en premium.',
      missing_fields: missingFields,
    });
    return;
  }

  next();
}
