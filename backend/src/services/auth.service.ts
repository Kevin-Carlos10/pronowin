import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import crypto from 'crypto';
import { generateReferralCode, generateOtp } from '../utils/generators';
import { sendWhatsAppOtp } from './whatsapp.service';
import { sendEmailOtp } from './email.service';
import {
  compareReviewOtp,
  getGooglePlayReviewConfig,
  normaliseEmail,
} from '../config/google_play_review';
import logger from '../utils/logger';

import { prisma } from '../lib/prisma';
import { decisionEnvoiOtp, OTP_FENETRE_MS, QuotaOtpDepasse } from '../utils/quota_otp';

/**
 * Ce qui est conservé en base : des empreintes, pas des secrets.
 *
 * Les refresh tokens et les codes de connexion étaient stockés en clair. Une
 * fuite de la base — ou d'une sauvegarde, qui vit sur le même disque — donnait
 * trente jours de sessions valables pour chaque compte, et les codes en cours
 * (constat S11 de l'audit du 24 septembre 2026).
 *
 * Un refresh token est un jeton aléatoire long : SHA-256 suffit. Un code de
 * connexion n'a que six chiffres, un million de valeurs : son empreinte est un
 * HMAC avec un secret du serveur, et le destinataire y entre — sans le secret,
 * on ne peut pas retrouver le code en essayant toutes les valeurs.
 */
export const empreinteJeton = (jeton: string) =>
  crypto.createHash('sha256').update(jeton).digest('hex');

export function empreinteOtp(destinataire: string, code: string): string {
  const secret = process.env.OTP_SECRET ?? process.env.JWT_SECRET ?? '';
  return crypto.createHmac('sha256', secret).update(`${destinataire}:${code}`).digest('hex');
}

export class AuthService {

  /** Envoie un OTP SMS au numéro donné */
  /**
   * Refuse un envoi de plus quand le quota de l'adresse est atteint.
   *
   * Lu dans la base plutôt qu'en mémoire : le compteur du contrôleur ne
   * survit ni à un redémarrage ni à une seconde instance, et c'est justement
   * sur la durée qu'un envoi en boucle fait mal.
   */
  private async _verifierQuotaEnvoi(destinataire: string): Promise<void> {
    const recents = await prisma.otpCode.findMany({
      where: {
        phoneNumber: destinataire,
        createdAt:   { gt: new Date(Date.now() - OTP_FENETRE_MS) },
      },
      select: { createdAt: true },
    });
    const decision = decisionEnvoiOtp(recents.map((r) => r.createdAt));
    if (!decision.autorise) throw new QuotaOtpDepasse(decision.attendreMinutes);
  }

  async sendOtp(phoneNumber: string): Promise<void> {
    await this._verifierQuotaEnvoi(phoneNumber);

    // Invalider les anciens OTPs
    await prisma.otpCode.updateMany({
      where: { phoneNumber, used: false },
      data:  { used: true },
    });

    const code      = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await prisma.otpCode.create({
      data: { phoneNumber, code: empreinteOtp(phoneNumber, code), expiresAt },
    });

    await sendWhatsAppOtp(phoneNumber, code);
  }

  /** Vérifie l'OTP et crée/connecte l'utilisateur */
  async verifyOtp(phoneNumber: string, code: string) {
    if (!await this._consommerOtp(phoneNumber, code)) {
      throw new Error('Code OTP invalide ou expiré.');
    }

    // Créer ou récupérer l'utilisateur
    let user = await prisma.user.findUnique({ where: { phoneNumber } });

    if (!user) {
      user = await prisma.user.create({
        data: {
          phoneNumber,
          phoneVerified: true,
          pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
          referralCode: generateReferralCode(),
          // Deduit de l'indicatif quand il est reconnu ; null sinon — la
          // completion de profil renseignera le pays choisi par l'utilisateur.
          countryCode:  phoneNumber.startsWith('+226') ? 'BF'
                      : phoneNumber.startsWith('+225') ? 'CI'
                      : phoneNumber.startsWith('+221') ? 'SN' : null,
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
    // Par empreinte ; en clair pour les jetons émis avant ce changement, qui
    // disparaissent d'eux-mêmes à leur échéance (30 jours).
    const record = await prisma.refreshToken.findUnique({ where: { token: empreinteJeton(token) } })
      ?? await prisma.refreshToken.findUnique({ where: { token } });

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

    // ── Rotation : consommer l'ancien, émettre une nouvelle paire ──
    //
    // Lecture puis marquage sans condition : deux rafraîchissements
    // simultanés du même jeton réussissaient tous les deux, et la détection
    // de réutilisation ci-dessus se contournait par une course (constat S11).
    // Le marquage ne réussit plus que pour un jeton encore inutilisé ; le
    // perdant est traité comme une réutilisation.
    const { count } = await prisma.refreshToken.updateMany({
      where: { id: record.id, used: false },
      data:  { used: true },
    });
    if (count === 0) {
      console.warn(`[Auth] ⚠️  Refresh token consommé deux fois pour userId=${record.userId} — révocation de toutes les sessions`);
      await prisma.refreshToken.deleteMany({ where: { userId: record.userId } });
      throw new Error('Session compromise détectée. Veuillez vous reconnecter.');
    }

    const newTokens = await this._generateTokens(record.userId);
    return newTokens; // { access_token, refresh_token }
  }

  /** Envoie un OTP par email. Indique aussi si l'email correspond à un
   *  compte déjà existant, pour adapter le message côté app (connexion
   *  vs inscription) sans dupliquer l'écran. */
  async sendEmailOtp(email: string): Promise<{ isNewUser: boolean }> {
    const review = getGooglePlayReviewConfig();
    if (review && normaliseEmail(email) === review.email) {
      // The reviewer enters the stable code provided in Play Console. No email
      // is sent and no temporary OTP record is created for this account.
      return { isNewUser: false };
    }

    // Le quota est vérifié après l'échappatoire du relecteur Play : son compte
    // n'envoie aucun courriel et ne crée aucun code, il n'a donc rien à
    // consommer.
    await this._verifierQuotaEnvoi(email);

    await prisma.otpCode.updateMany({
      where: { phoneNumber: email, used: false },
      data:  { used: true },
    });

    const code      = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    await prisma.otpCode.create({
      data: { phoneNumber: email, code: empreinteOtp(email, code), expiresAt },
    });

    await sendEmailOtp(email, code);

    const existing = await prisma.user.findUnique({ where: { email }, select: { id: true } });
    return { isNewUser: !existing };
  }

  /** Verifie l'OTP email et connecte ou cree l'utilisateur */
  async verifyEmailOtp(email: string, code: string) {
    const review = getGooglePlayReviewConfig();
    if (review && normaliseEmail(email) === review.email) {
      if (!compareReviewOtp(code, review.otp)) {
        throw new Error('Code OTP invalide ou expire.');
      }

      const user = await prisma.user.findUnique({ where: { email: review.email } });
      if (!user || !user.isActive || user.deletedAt) {
        throw new Error('Compte de revue indisponible.');
      }

      const activeUser = await prisma.user.update({
        where: { id: user.id },
        data:  { lastLoginAt: new Date() },
      });
      const tokens = await this._generateTokens(activeUser.id);
      logger.info('[Auth] Connexion du compte de revue Google Play');
      return { user: activeUser, ...tokens };
    }

    if (!await this._consommerOtp(email, code)) throw new Error('Code OTP invalide ou expiré.');

    /*
     * Consentement aux CGU.
     *
     * Il y avait deux recueils successifs : la mention « En continuant, tu
     * acceptes nos conditions » sur l'écran d'e-mail, puis un écran entier
     * avec une case à cocher. Un seul suffit, et c'est le premier : taper
     * « Continuer » sous une mention lisible EST l'acte de consentement.
     *
     * On l'horodate ici, au moment où le compte est réellement créé ou
     * reconnecté. Pour un compte existant dont la date est nulle,
     * l'utilisateur vient de repasser par le même écran et la même mention —
     * on n'invente donc aucun consentement rétroactif.
     */
    const maintenant = new Date();

    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          emailVerified:   true,
          acceptedTermsAt: maintenant,
          pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
          referralCode: generateReferralCode(),
          },
      });
    } else if (!user.emailVerified || !user.acceptedTermsAt) {
      user = await prisma.user.update({
        where: { id: user.id },
        data:  {
          emailVerified:   true,
          acceptedTermsAt: user.acceptedTermsAt ?? maintenant,
        },
      });
    }

    await prisma.user.update({
      where: { id: user.id },
      data:  { lastLoginAt: maintenant },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  /// Connexion via Google.
  ///
  /// Le client envoie l'`idToken` renvoyé par le SDK Google ; on le vérifie
  /// auprès de Google (signature + audience + expiration) avant de faire quoi
  /// que ce soit. Ne jamais faire confiance à l'e-mail transmis par le client :
  /// seul le contenu du jeton vérifié fait foi.
  async loginWithGoogle(idToken: string) {
    const clientIds = (process.env.GOOGLE_CLIENT_IDS ?? '')
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
    if (clientIds.length === 0) {
      throw new Error('Connexion Google non configurée sur le serveur.');
    }

    const client = new OAuth2Client();
    let payload;
    try {
      const ticket = await client.verifyIdToken({
        idToken,
        audience: clientIds,
      });
      payload = ticket.getPayload();
    } catch {
      throw new Error('Jeton Google invalide.');
    }

    const email = payload?.email?.toLowerCase();
    if (!email || payload?.email_verified !== true) {
      throw new Error('Adresse Google non vérifiée.');
    }

    // Même recueil de consentement que par e-mail : la mention légale est
    // affichée au-dessus du bouton Google, taper dessus vaut acceptation.
    const maintenant = new Date();

    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          emailVerified:   true,
          acceptedTermsAt: maintenant,
          // Google a déjà vérifié l'adresse : pas d'OTP à repasser.
          firstName:    payload?.given_name  ?? null,
          lastName:     payload?.family_name ?? null,
          pseudo:       `Parieur_${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
          referralCode: generateReferralCode(),
        },
      });
    } else if (!user.emailVerified || !user.acceptedTermsAt) {
      user = await prisma.user.update({
        where: { id: user.id },
        data:  {
          emailVerified:   true,
          acceptedTermsAt: user.acceptedTermsAt ?? maintenant,
        },
      });
    }

    await prisma.user.update({
      where: { id: user.id },
      data:  { lastLoginAt: maintenant },
    });

    const tokens = await this._generateTokens(user.id);
    return { user, ...tokens };
  }

  // ─── Liaison de compte ────────────────────────────────────────────────────

  /** Lie un numéro de téléphone à un compte existant (après vérification OTP) */
  async linkPhone(userId: string, phoneNumber: string, code: string) {
    // Vérifier que le téléphone n'est pas déjà pris par un AUTRE compte
    const conflict = await prisma.user.findUnique({ where: { phoneNumber } });
    if (conflict && conflict.id !== userId) {
      throw new Error('Ce numéro de téléphone est déjà utilisé par un autre compte.');
    }
    if (conflict && conflict.id === userId) {
      throw new Error('Ce numéro de téléphone est déjà lié à votre compte.');
    }

    // Vérifier l'OTP
    if (!await this._consommerOtp(phoneNumber, code)) throw new Error('Code OTP invalide ou expiré.');

    const user = await prisma.user.update({
      where: { id: userId },
      data:  { phoneNumber, phoneVerified: true },
    });
    return { user };
  }

  /** Lie un email à un compte existant (après vérification OTP email) */
  async linkEmail(userId: string, email: string, code: string) {
    // Vérifier que l'email n'est pas déjà pris par un AUTRE compte
    const conflict = await prisma.user.findUnique({ where: { email } });
    if (conflict && conflict.id !== userId) {
      throw new Error('Cet email est déjà utilisé par un autre compte.');
    }
    if (conflict && conflict.id === userId) {
      throw new Error('Cet email est déjà lié à votre compte.');
    }

    // Vérifier l'OTP (stocké dans phoneNumber pour réutiliser le modèle existant)
    if (!await this._consommerOtp(email, code)) throw new Error('Code OTP invalide ou expiré.');

    const user = await prisma.user.update({
      where: { id: userId },
      data:  { email, emailVerified: true },
    });
    return { user };
  }

  /** Déconnecte l'utilisateur */
  async logout(userId: string, refreshToken: string): Promise<void> {
    // Par empreinte, et en clair pour un jeton émis avant qu'elles existent.
    await prisma.refreshToken.deleteMany({
      where: { userId, token: { in: [empreinteJeton(refreshToken), refreshToken] } },
    });
  }

  // ─── Privé ────────────────────────────────────────────────────────────────

  /**
   * Consomme un code de connexion, une seule fois.
   *
   * Lecture puis marquage sans condition : deux vérifications simultanées du
   * même code ouvraient deux sessions. Le marquage ne réussit plus que pour
   * un code encore inutilisé. Les codes émis juste avant ce changement,
   * stockés en clair, restent acceptés pendant leurs dix minutes de validité.
   */
  private async _consommerOtp(destinataire: string, code: string): Promise<boolean> {
    const candidat = await prisma.otpCode.findFirst({
      where: {
        phoneNumber: destinataire,
        code:        { in: [empreinteOtp(destinataire, code), code] },
        used:        false,
        expiresAt:   { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (!candidat) return false;
    const { count } = await prisma.otpCode.updateMany({
      where: { id: candidat.id, used: false },
      data:  { used: true },
    });
    return count === 1;
  }

  private async _generateTokens(userId: string) {
    const accessToken  = this._generateAccessToken(userId);
    // Un identifiant propre à chaque jeton : sans lui, deux émissions dans la
    // même seconde pour le même compte produisaient le même jeton, que la
    // contrainte d'unicité refusait — une connexion qui échouait sans raison
    // visible.
    const refreshToken = jwt.sign(
      { userId, jti: crypto.randomUUID() },
      process.env.JWT_REFRESH_SECRET!,
      { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN ?? '30d' } as jwt.SignOptions,
    );

    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await prisma.refreshToken.create({
      data: { userId, token: empreinteJeton(refreshToken), expiresAt },
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
