import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

import { prisma } from '../lib/prisma';

export interface AuthRequest extends Request {
  userId?: string;
}

export async function authMiddleware(
  req: AuthRequest, res: Response, next: NextFunction,
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ message: 'Token d\'authentification manquant.' });
    return;
  }

  const token = authHeader.split(' ')[1];

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as { userId: string };
    
    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
    });

    if (!user || (user as any).deletedAt) {
      res.status(401).json({ message: 'Utilisateur introuvable.' });
      return;
    }
    if (!user.isActive) {
      res.status(403).json({ message: 'Votre compte a été suspendu. Contactez le support.', code: 'ACCOUNT_BANNED' });
      return;
    }

    req.userId = payload.userId;
    next();
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      res.status(401).json({ message: 'Session expirée. Veuillez vous reconnecter.', code: 'TOKEN_EXPIRED' });
    } else {
      res.status(401).json({ message: 'Token invalide.' });
    }
  }
}

/** Middleware de validation Premium */
export async function premiumMiddleware(
  req: AuthRequest, res: Response, next: NextFunction,
): Promise<void> {
  const user = await prisma.user.findUnique({ where: { id: req.userId } });
  if (user?.subscriptionPlan !== 'premium' || 
      (user.subscriptionExpiresAt && user.subscriptionExpiresAt < new Date())) {
    res.status(403).json({ message: 'Accès réservé aux membres Premium.', code: 'PREMIUM_REQUIRED' });
    return;
  }
  next();
}