import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

import { prisma } from '../lib/prisma';

// Interface étendue pour les requêtes admin
export interface AdminRequest extends Request {
  adminId?:   string;
  adminRole?: string;
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
    ) as { adminId: string; role: string };

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

    req.adminId   = admin.id;
    req.adminRole = admin.role;
    next();

  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      res.status(401).json({ message: 'Session admin expirée.', code: 'TOKEN_EXPIRED' });
    } else {
      res.status(401).json({ message: 'Token admin invalide.' });
    }
  }
}
