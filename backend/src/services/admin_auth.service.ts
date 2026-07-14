import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import { prisma } from '../lib/prisma';

export class AdminAuthService {
  async login(email: string, password: string) {
    // 1. Utilisation de 'prisma.admin' (avec un A majuscule pour correspondre à ton schema.prisma)
    // 2. Recherche uniquement sur le champ unique '@unique' (email) sans filtres additionnels
    const admin = await prisma.admin.findUnique({ where: { email } });
    
    // 3. Vérification combinée de l'existence de l'admin et de son statut actif
    if (!admin || !admin.isActive) throw new Error('Email ou mot de passe incorrect.');

    const valid = await bcrypt.compare(password, admin.passwordHash);
    if (!valid) throw new Error('Email ou mot de passe incorrect.');

    // Mise à jour de la date de dernière connexion
    await prisma.admin.update({ where: { id: admin.id }, data: { lastLoginAt: new Date() } });

    const token = jwt.sign(
      { adminId: admin.id, role: admin.role },
      process.env.ADMIN_JWT_SECRET ?? process.env.JWT_SECRET!,
      { expiresIn: '8h' }
    );
    return { token, admin: { id: admin.id, name: admin.name, email: admin.email, role: admin.role } };
  }

  async createAdmin(data: { email: string; password: string; name: string; role?: 'super_admin' | 'analyst' }) {
    const hash = await bcrypt.hash(data.password, 12);
    
    // Utilisation de 'prisma.admin' également ici
    return prisma.admin.create({
      data: { email: data.email, passwordHash: hash, name: data.name, role: data.role ?? 'analyst' },
      select: { id: true, email: true, name: true, role: true },
    });
  }
}