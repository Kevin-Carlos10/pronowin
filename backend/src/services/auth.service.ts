import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { generateReferralCode, generateOtp } from '../utils/generators';
import { sendWhatsAppOtp } from './whatsapp.service';
import { sendEmailOtp } from './email.service';

import { prisma } from '../lib/prisma';

export class AuthService {

  /** Envoie un OTP SMS au numéro donné */
  async sendOtp(phoneNumber: string): Promise<void> {
    // Invalider les anciens OTPs
    await prisma.otpCode.updateMany({
      where: { phoneNumber, used: false },
      data:  { used: true },
    });

    const code      = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await prisma.otpCode.create({
      data: { phoneNumber, code, expiresAt },
    });

    await sendWhatsAppOtp(phoneNumber, code);
  }

  /** Vérifie l'OTP et crée/connecte l'utilisateur */
  async verifyOtp(phoneNumber: string, code: string) {
    const otpRecord = await prisma.otpCode.findFirst({
      where: {
        phoneNumber,
        code,
        used: false,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!otpRecord) {
      throw new Error('Code OTP invalide ou expiré.');
    }

    // Marquer l'OTP comme utilisé
    await prisma.otpCode.update({
      where: { id: otpRecord.id },
      data:  { used: true },
    });

    // Créer ou récupérer l'utilisateur
    let user = await prisma.user.findUnique({ where: { phoneNumber } });

    if (!user) {
      user = await prisma.user.create({
        data: {
          phoneNumber,
          phoneVerified: true,
          pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
          referralCode: generateReferralCode(),
          countryCode:  phoneNumber.startsWith('+226') ? 'BF'
                      : phoneNumber.startsWith('+225') ? 'CI'
                      : phoneNumber.startsWith('+221') ? 'SN' : 'XX',
        },
      });
    } else if (!user.phoneVerified) {
      user = await prisma.user.update({
        where: { id: user.id },
        data:  { phoneVerified: true },
      });
    }

    // Mettre à jour lastLoginAt
    await prisma.user.update({
      where: { id: user.id },
      data:  { lastLoginAt: new Date() },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /** Rafraîchit l'access token avec rotation complète du refresh token */
  async refreshToken(token: string) {
    const record = await prisma.refreshToken.findUnique({ where: { token } });

    // Token introuvable
    if (!record) {
      throw new Error('Token de rafraîchissement invalide.');
    }

    // ── Détection de réutilisation (Token Theft Detection) ──────────────────
    // Si le token est déjà marqué "used", quelqu'un l'a réutilisé → vol probable
    if (record.used) {
      console.warn(`[Auth] ⚠️  Refresh token réutilisé pour userId=${record.userId} — révocation de toutes les sessions`);
      // Révoquer TOUS les tokens de cet utilisateur (compromission détectée)
      await prisma.refreshToken.deleteMany({ where: { userId: record.userId } });
      throw new Error('Session compromise détectée. Veuillez vous reconnecter.');
    }

    // Token expiré → nettoyer et rejeter
    if (record.expiresAt < new Date()) {
      await prisma.refreshToken.delete({ where: { id: record.id } });
      throw new Error('Session expirée. Veuillez vous reconnecter.');
    }

    // ── Rotation : marquer l'ancien comme "used", émettre une nouvelle paire ─
    await prisma.refreshToken.update({
      where: { id: record.id },
      data:  { used: true },
    });

    const newTokens = await this._generateTokens(record.userId);
    return newTokens; // { access_token, refresh_token }
  }

  /**
   * Inscription/connexion rapide sans vérification.
   * Crée le compte si inexistant (phoneVerified/emailVerified = false).
   * Si le compte existe déjà sans vérification, retourne un nouveau token.
   */
  async quickRegister(params: { phoneNumber?: string; email?: string }) {
    const { phoneNumber, email } = params;
    if (!phoneNumber && !email) throw new Error('Numéro ou email requis.');

    let user = phoneNumber
      ? await prisma.user.findUnique({ where: { phoneNumber } })
      : await prisma.user.findUnique({ where: { email: email! } });

    if (!user) {
      const data: any = {
        pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
        referralCode: generateReferralCode(),
        countryCode:  phoneNumber?.startsWith('+226') ? 'BF'
                    : phoneNumber?.startsWith('+225') ? 'CI'
                    : phoneNumber?.startsWith('+221') ? 'SN' : 'BF',
        phoneVerified: false,
        emailVerified: false,
      };
      if (phoneNumber) data.phoneNumber = phoneNumber;
      if (email)       data.email       = email;
      user = await prisma.user.create({ data });
    }

    await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /** Inscription par email + mot de passe */
  async registerEmail(email: string, password: string, pseudo: string) {
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) throw new Error('Un compte existe déjà avec cet email.');

    const passwordHash = await bcrypt.hash(password, 12);
    const user = await prisma.user.create({
      data: {
        email,
        emailVerified: true,
        passwordHash,
        pseudo,
        referralCode: generateReferralCode(),
        countryCode:  'BF',
      },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /** Connexion par email + mot de passe */
  async loginEmail(email: string, password: string) {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || !user.passwordHash) {
      throw new Error('Email ou mot de passe incorrect.');
    }
    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) throw new Error('Email ou mot de passe incorrect.');

    await prisma.user.update({
      where: { id: user.id },
      data:  { lastLoginAt: new Date() },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /** Envoie un OTP par email */
  async sendEmailOtp(email: string): Promise<void> {
    await prisma.otpCode.updateMany({
      where: { phoneNumber: email, used: false },
      data:  { used: true },
    });

    const code      = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await prisma.otpCode.create({
      data: { phoneNumber: email, code, expiresAt },
    });

    await sendEmailOtp(email, code);
  }

  /** Vérifie l'OTP email et connecte/crée l'utilisateur */
  async verifyEmailOtp(email: string, code: string) {
    const otpRecord = await prisma.otpCode.findFirst({
      where: {
        phoneNumber: email,
        code,
        used:      false,
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!otpRecord) throw new Error('Code OTP invalide ou expiré.');

    await prisma.otpCode.update({
      where: { id: otpRecord.id },
      data:  { used: true },
    });

    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          emailVerified: true,
          pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
          referralCode: generateReferralCode(),
          countryCode:  'BF',
        },
      });
    } else if (!user.emailVerified) {
      user = await prisma.user.update({
        where: { id: user.id },
        data:  { emailVerified: true },
      });
    }

    await prisma.user.update({
      where: { id: user.id },
      data:  { lastLoginAt: new Date() },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /** Déconnecte l'utilisateur */
  async logout(userId: string, refreshToken: string): Promise<void> {
    await prisma.refreshToken.deleteMany({
      where: { userId, token: refreshToken },
    });
  }

  // ─── Privé ────────────────────────────────────────────────────────────────

  private async _generateTokens(userId: string) {
    const accessToken  = this._generateAccessToken(userId);
    const refreshToken = jwt.sign(
      { userId },
      process.env.JWT_REFRESH_SECRET!,
      { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN ?? '30d' } as jwt.SignOptions,
    );

    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await prisma.refreshToken.create({
      data: { userId, token: refreshToken, expiresAt },
    });

    return { access_token: accessToken, refresh_token: refreshToken };
  }

  private _generateAccessToken(userId: string): string {
    return jwt.sign(
      { userId },
      process.env.JWT_SECRET!,
      { expiresIn: process.env.JWT_EXPIRES_IN ?? '15m' } as jwt.SignOptions,
    );
  }
}
