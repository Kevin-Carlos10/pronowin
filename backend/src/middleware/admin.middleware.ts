import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

import { prisma } from '../lib/prisma';
import {
  ActeurAdmin,
  ENTETE_DELEGATION,
  estMutation,
  lireDelegation,
} from '../utils/delegation_admin';
import { acteurAutorise, cheminRelatif } from '../utils/permissions_admin';
import { repondreErreur } from '../utils/erreurs';

// Interface étendue pour les requêtes admin
export interface AdminRequest extends Request {
  adminId?:   string;
  adminRole?: string;
  /** La personne derrière le jeton, quand le panneau l'a signée. */
  acteurAdmin?: ActeurAdmin;
}

/**
 * Le secret partagé avec le panneau d'administration.
 *
 * Sans lui, cette API ne peut pas distinguer les dix sous-administrateurs qui
 * partagent le jeton du compte de service — ni savoir si un appel est passé
 * par le panneau. Le serveur refuse donc de démarrer sans.
 *
 * Il n'a volontairement pas de valeur par défaut : un secret écrit dans le
 * dépôt est une serrure dont la clé est publiée, et le panneau en a fait la
 * démonstration.
 */
const SECRET_DELEGATION = process.env.ADMIN_DELEGATION_SECRET ?? '';
if (!SECRET_DELEGATION) {
  console.error('ADMIN_DELEGATION_SECRET est absent.');
  console.error('Ce secret etablit qui agit derriere le compte de service du panneau ;');
  console.error('sans lui, une action d administration ne peut etre attribuee a personne.');
  console.error('La meme valeur doit etre posee dans backend/.env et admin-web/.env.');
  process.exit(1);
}

export async function adminMiddleware(
  req: AdminRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ message: 'Token admin manquant.' });
    return;
  }

  const token = authHeader.split(' ')[1];

  try {
    const payload = jwt.verify(
      token,
      process.env.ADMIN_JWT_SECRET ?? process.env.JWT_SECRET!
    ) as { adminId: string; role: string; v?: number };

    // Vérifier que le payload contient adminId (≠ token user qui contient userId)
    if (!payload.adminId) {
      res.status(401).json({ message: 'Token invalide : non-admin.' });
      return;
    }

    const admin = await prisma.admin.findUnique({
      where: { id: payload.adminId, isActive: true },
    });

    if (!admin) {
      res.status(401).json({ message: 'Admin introuvable ou désactivé.' });
      return;
    }

    // Un jeton émis avant le dernier changement de mot de passe ne vaut plus.
    if ((payload.v ?? 0) !== ((admin as any).sessionVersion ?? 0)) {
      res.status(401).json({ message: 'Session admin révoquée.', code: 'SESSION_REVOQUEE' });
      return;
    }

    req.adminId   = admin.id;
    req.adminRole = admin.role;

    // ── Qui agit derrière ce jeton ──
    //
    // Le panneau signe, à chaque appel, l'identité et les droits de la
    // personne connectée. La signature est posée par son serveur : elle ne
    // passe jamais par le navigateur, donc un sous-administrateur ne peut ni
    // la lire ni la refaire.
    //
    // Les lectures en étaient dispensées : le jeton du compte de service était
    // alors posé dans le navigateur des sous-admins, et ils pouvaient lire
    // toute l'API — téléphones, preuves de paiement, revenus — quelles que
    // soient leurs permissions (constat S1). Le jeton ne quitte plus le
    // serveur du panneau, qui délègue chacun de ses appels : une requête sans
    // délégation, lecture comprise, ne peut donc venir que d'ailleurs.
    const lecture = lireDelegation(
      req.headers[ENTETE_DELEGATION] as string | undefined,
      SECRET_DELEGATION,
    );

    if (!lecture.ok) {
      console.warn(
        `[admin] ${req.method} ${req.originalUrl} refusé — délégation `
        + `${lecture.cause}. Appel direct à l'API avec un jeton d'administration ?`);
      res.status(403).json({
        message: estMutation(req.method)
          ? 'Action refusée : cet appel ne vient pas du panneau d\'administration.'
          : 'Lecture refusée : cet appel ne vient pas du panneau d\'administration.',
        code:    'DELEGATION_' + lecture.cause.toUpperCase(),
      });
      return;
    }
    req.acteurAdmin = lecture.acteur;

    // ── Et a-t-elle le droit de le faire ? ──
    //
    // Les permissions voyageaient dans la délégation sans qu'aucune route ne
    // les lise : l'API s'en remettait au panneau. Elle les applique désormais
    // elle-même (`utils/permissions_admin.ts`).
    const verdict = acteurAutorise(lecture.acteur, req.method, cheminRelatif(req.originalUrl));
    if (!verdict.ok) {
      console.warn(`[admin] ${req.method} ${req.originalUrl} refusé à `
        + `${lecture.acteur.nom} (${lecture.acteur.id}) — ${verdict.raison}.`);
      res.status(403).json({
        message: `Accès refusé : ${verdict.raison}.`,
        code:    'PERMISSION_ADMIN',
      });
      return;
    }

    next();

  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      res.status(401).json({ message: 'Session admin expirée.', code: 'TOKEN_EXPIRED' });
    } else if (error instanceof jwt.JsonWebTokenError) {
      res.status(401).json({ message: 'Token admin invalide.' });
    } else {
      // Base injoignable : le panneau traite un 401 comme une session morte
      // et renvoie l'administrateur à l'écran de connexion. Ce n'en est pas une.
      repondreErreur(res, error);
    }
  }
}
