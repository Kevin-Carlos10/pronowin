import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { body, validationResult } from 'express-validator';
import { AuthService } from '../services/auth.service';
import { AuthRequest } from '../middleware/auth.middleware';
import bcrypt from 'bcrypt';
import { updateStreak, getStreak } from '../services/streak.service';

const authService = new AuthService();

// ─── Protection brute-force OTP par numéro de téléphone ──────────────────────
// Indépendant du rate-limit global (qui est par IP) — ici on track par phone.
interface OtpAttempts { count: number; resetAt: number; blockedUntil?: number; }
const _otpAttempts = new Map<string, OtpAttempts>();
const OTP_MAX_ATTEMPTS = 5;        // 5 tentatives échouées
const OTP_WINDOW_MS    = 10 * 60 * 1000;   // sur 10 minutes
const OTP_BLOCK_MS     = 15 * 60 * 1000;   // blocage 15 minutes

function _checkOtpBrute(phone: string): { blocked: boolean; message?: string } {
  const now  = Date.now();
  const rec  = _otpAttempts.get(phone);
  if (!rec) return { blocked: false };
  if (rec.blockedUntil && now < rec.blockedUntil) {
    const wait = Math.ceil((rec.blockedUntil - now) / 60000);
    return { blocked: true, message: `Trop de tentatives. Réessayez dans ${wait} minute(s).` };
  }
  if (now > rec.resetAt) { _otpAttempts.delete(phone); return { blocked: false }; }
  return { blocked: false };
}

function _recordOtpFailure(phone: string): void {
  const now = Date.now();
  const rec = _otpAttempts.get(phone) ?? { count: 0, resetAt: now + OTP_WINDOW_MS };
  rec.count++;
  if (rec.count >= OTP_MAX_ATTEMPTS) {
    rec.blockedUntil = now + OTP_BLOCK_MS;
    console.warn(`[OTP] Brute-force détecté pour ${phone} — bloqué 15 min`);
  }
  _otpAttempts.set(phone, rec);
}

function _clearOtpAttempts(phone: string): void {
  _otpAttempts.delete(phone);
}




// ─── Validateurs ─────────────────────────────────────────────────────────────
// ─── Quick Register (sans vérification) ──────────────────────────────────────
export const quickRegisterValidators = [
  body('phone_number').optional().matches(/^\+?[1-9]\d{7,14}$/).withMessage('Format numéro invalide.'),
  body('email').optional().isEmail().withMessage('Email invalide.'),
];

export async function quickRegister(req: Request, res: Response): Promise<void> {
  const err = validationResult(req);
  if (!err.isEmpty()) { res.status(422).json({ message: err.array()[0].msg }); return; }

  const { phone_number, email } = req.body;
  if (!phone_number && !email) {
    res.status(422).json({ message: 'Numéro de téléphone ou email requis.' });
    return;
  }

  try {
    const result = await authService.quickRegister({ phoneNumber: phone_number, email });
    const streakResult = await updateStreak(result.user.id).catch(() => null);
    res.status(201).json({
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      user:          _formatUser(result.user),
      streak:        streakResult ?? undefined,
    });
  } catch (e: any) {
    res.status(400).json({ message: e.message });
  }
}

export const sendOtpValidators = [
  body('phone_number')
    .notEmpty().withMessage('Numéro de téléphone requis.')
    .matches(/^\+?[1-9]\d{7,14}$/).withMessage('Format de numéro invalide.'),
];

export const verifyOtpValidators = [
  body('phone_number').notEmpty().withMessage('Numéro requis.'),
  body('otp').isLength({ min: 6, max: 6 }).withMessage('OTP invalide (6 chiffres).'),
];

export const registerEmailValidators = [
  body('email').isEmail().withMessage('Email invalide.'),
  body('password').isLength({ min: 8 }).withMessage('Mot de passe minimum 8 caractères.'),
  body('pseudo').isLength({ min: 3, max: 30 }).withMessage('Pseudo entre 3 et 30 caractères.'),
];

export const loginEmailValidators = [
  body('email').isEmail().withMessage('Email invalide.'),
  body('password').notEmpty().withMessage('Mot de passe requis.'),
];

export const emailOtpValidators = [
  body('email').isEmail().withMessage('Email invalide.'),
];

export const verifyEmailOtpValidators = [
  body('email').isEmail().withMessage('Email invalide.'),
  body('otp').isLength({ min: 6, max: 6 }).withMessage('OTP invalide (6 chiffres).'),
];

// ─── Controllers ─────────────────────────────────────────────────────────────
export async function sendOtp(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(422).json({ message: errors.array()[0].msg });
    return;
  }

  // Vérifier le brute-force avant d'envoyer (évite de spammer le SMS provider)
  const bruteCheck = _checkOtpBrute(req.body.phone_number);
  if (bruteCheck.blocked) {
    res.status(429).json({ message: bruteCheck.message });
    return;
  }

  try {
    await authService.sendOtp(req.body.phone_number);
    res.json({ message: 'Code OTP envoyé sur WhatsApp.' });
  } catch (error: any) {
    res.status(500).json({ message: error.message ?? 'Erreur lors de l\'envoi du SMS.' });
  }
}

export async function verifyOtp(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(422).json({ message: errors.array()[0].msg });
    return;
  }

  // Vérifier le brute-force
  const bruteCheck = _checkOtpBrute(req.body.phone_number);
  if (bruteCheck.blocked) {
    res.status(429).json({ message: bruteCheck.message });
    return;
  }

  try {
    const result = await authService.verifyOtp(req.body.phone_number, req.body.otp);
    // Succès → réinitialiser le compteur
    _clearOtpAttempts(req.body.phone_number);
    // Mettre à jour le streak (fire-and-forget pour ne pas bloquer la réponse)
    const streakResult = await updateStreak(result.user.id).catch(() => null);
    res.json({
      user:          _formatUser(result.user),
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      streak:        streakResult,
    });
  } catch (error: any) {
    // Échec → incrémenter le compteur
    _recordOtpFailure(req.body.phone_number);
    res.status(401).json({ message: error.message ?? 'Vérification OTP échouée.' });
  }
}

export async function registerEmail(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) { res.status(422).json({ message: errors.array()[0].msg }); return; }
  try {
    const { email, password, pseudo } = req.body;
    const result = await authService.registerEmail(email, password, pseudo);
    const streakResult = await updateStreak(result.user.id).catch(() => null);
    res.status(201).json({
      user:          _formatUser(result.user),
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      streak:        streakResult,
    });
  } catch (e: any) {
    const isDuplicate = e.message?.includes('existe déjà');
    res.status(isDuplicate ? 409 : 500).json({ message: e.message });
  }
}

export async function loginEmail(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) { res.status(422).json({ message: errors.array()[0].msg }); return; }
  try {
    const { email, password } = req.body;
    const result = await authService.loginEmail(email, password);
    const streakResult = await updateStreak(result.user.id).catch(() => null);
    res.json({
      user:          _formatUser(result.user),
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      streak:        streakResult,
    });
  } catch (e: any) {
    res.status(401).json({ message: e.message });
  }
}

export async function sendEmailOtp(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) { res.status(422).json({ message: errors.array()[0].msg }); return; }
  const bruteCheck = _checkOtpBrute(req.body.email);
  if (bruteCheck.blocked) { res.status(429).json({ message: bruteCheck.message }); return; }
  try {
    await authService.sendEmailOtp(req.body.email);
    res.json({ message: 'Code OTP envoyé par email.' });
  } catch (e: any) {
    res.status(500).json({ message: e.message ?? 'Erreur lors de l\'envoi.' });
  }
}

export async function verifyEmailOtp(req: Request, res: Response): Promise<void> {
  const errors = validationResult(req);
  if (!errors.isEmpty()) { res.status(422).json({ message: errors.array()[0].msg }); return; }
  const bruteCheck = _checkOtpBrute(req.body.email);
  if (bruteCheck.blocked) { res.status(429).json({ message: bruteCheck.message }); return; }
  try {
    const result = await authService.verifyEmailOtp(req.body.email, req.body.otp);
    _clearOtpAttempts(req.body.email);
    const streakResult = await updateStreak(result.user.id).catch(() => null);
    res.json({
      user:          _formatUser(result.user),
      access_token:  result.access_token,
      refresh_token: result.refresh_token,
      streak:        streakResult,
    });
  } catch (e: any) {
    _recordOtpFailure(req.body.email);
    res.status(401).json({ message: e.message ?? 'Vérification OTP échouée.' });
  }
}

export async function refreshToken(req: Request, res: Response): Promise<void> {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    res.status(400).json({ message: 'Token de rafraîchissement manquant.' });
    return;
  }
  try {
    const result = await authService.refreshToken(refresh_token);
    res.json(result);
  } catch (error: any) {
    res.status(401).json({ message: error.message });
  }
}

export async function getProfile(req: AuthRequest, res: Response): Promise<void> {
  const user = await prisma.user.findUnique({ where: { id: req.userId } });
  if (!user) { res.status(404).json({ message: 'Utilisateur introuvable.' }); return; }
  res.json(_formatUser(user));
}

export async function getStreakHandler(req: AuthRequest, res: Response): Promise<void> {
  try {
    const data = await getStreak(req.userId!);
    res.json(data);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
}

export async function logout(req: AuthRequest, res: Response): Promise<void> {
  const { refresh_token } = req.body;
  await authService.logout(req.userId!, refresh_token);
  res.json({ message: 'Déconnexion réussie.' });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function _formatUser(user: any) {
  return {
    id:                     user.id,
    phone_number:           user.phoneNumber,
    email:                  user.email,
    pseudo:                 user.pseudo,
    first_name:             user.firstName ?? null,
    last_name:              user.lastName  ?? null,
    avatar_url:             user.avatarUrl,
    country_code:           user.countryCode,
    subscription_plan:      user.subscriptionPlan,
    subscription_expires_at:user.subscriptionExpiresAt,
    referral_code:          user.referralCode,
    referral_earnings:      user.referralEarnings,
    phone_verified:         user.phoneVerified  ?? false,
    email_verified:         user.emailVerified  ?? false,
    created_at:             user.createdAt,
    accepted_terms_at:      user.acceptedTermsAt ?? null,
    terms_version:          user.termsVersion    ?? 1,
  };
}

const CURRENT_TERMS_VERSION = parseInt(process.env.TERMS_VERSION ?? '1', 10);

export async function acceptTerms(req: AuthRequest, res: Response): Promise<void> {
  try {
    const user = await prisma.user.update({
      where: { id: req.userId! },
      data:  { acceptedTermsAt: new Date(), termsVersion: CURRENT_TERMS_VERSION } as any,
    });
    res.json({ accepted_terms_at: user.acceptedTermsAt, terms_version: CURRENT_TERMS_VERSION });
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
}

// ─── AJOUT : Controller pour créer le tout premier Admin ──────────────────────
export async function createAdmin(req: Request, res: Response): Promise<void> {
  try {
    const { email, password, name, role } = req.body;

    // 1. Validation de base des données reçues
    if (!email || !password || !name) {
      res.status(400).json({ message: 'Champs requis manquants : email, password ou name.' });
      return;
    }

    // 2. Vérifier si l'email existe déjà dans la table Admin
    const existingAdmin = await prisma.admin.findUnique({ where: { email } });
    if (existingAdmin) {
      res.status(400).json({ message: 'Cet email d\'administrateur est déjà utilisé.' });
      return;
    }

    // 3. Hasher le mot de passe de manière sécurisée
    const hashedPassword = await bcrypt.hash(password, 10);

    // 4. Déterminer le rôle (par défaut : analyst, ou super_admin si spécifié)
    let adminRole: 'super_admin' | 'analyst' = 'analyst';
    if (role === 'super_admin') {
      adminRole = 'super_admin';
    }

    // 5. Insertion propre dans la table "admins"
    const newAdmin = await prisma.admin.create({
      data: {
        email,
        passwordHash: hashedPassword,
        name,
        role: adminRole,
        isActive: true,
      },
    });

    // 6. Réponse de succès (sans renvoyer le hash du mot de passe)
    res.status(201).json({
      message: 'Compte Administrateur créé avec succès !',
      admin: {
        id: newAdmin.id,
        email: newAdmin.email,
        name: newAdmin.name,
        role: newAdmin.role,
        is_active: newAdmin.isActive,
        created_at: newAdmin.createdAt,
      },
    });

  } catch (error: any) {
    console.error('[CREATE_ADMIN_ERROR]', error);
    res.status(500).json({ message: error.message ?? 'Erreur interne lors de la création de l\'admin.' });
  }
}
