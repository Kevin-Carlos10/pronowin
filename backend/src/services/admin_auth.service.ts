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

  /**
   * Changer son propre mot de passe.
   *
   * L'admin-web postait déjà sur PATCH /admin/profile/password, qui n'existait
   * pas : le formulaire échouait toujours pour l'admin principal (les
   * sous-admins, eux, sont gérés localement par l'admin-web).
   *
   * La longueur minimale est revérifiée ici : l'admin-web la contrôle déjà,
   * mais un contrôle purement client ne protège rien.
   */
  async changePassword(adminId: string, currentPassword: string, newPassword: string) {
    if (!currentPassword || !newPassword) {
      throw new Error('Mot de passe actuel et nouveau mot de passe requis.');
    }
    if (newPassword.length < 8) {
      throw new Error('Le nouveau mot de passe doit faire au moins 8 caractères.');
    }

    const admin = await prisma.admin.findUnique({ where: { id: adminId } });
    if (!admin) throw new Error('Compte introuvable.');

    if (!await bcrypt.compare(currentPassword, admin.passwordHash)) {
      throw new Error('Mot de passe actuel incorrect.');
    }
    if (await bcrypt.compare(newPassword, admin.passwordHash)) {
      throw new Error('Le nouveau mot de passe doit être différent de l\'actuel.');
    }

    await prisma.admin.update({
      where: { id: adminId },
      data:  { passwordHash: await bcrypt.hash(newPassword, 12) },
    });
    return { success: true };
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