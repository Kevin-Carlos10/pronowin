import { Router } from 'express';
import * as AuthController from '../controllers/auth.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

// Inscription rapide sans vérification
router.post('/quick-register', AuthController.quickRegisterValidators, AuthController.quickRegister);

// Routes publiques — WhatsApp OTP (pour vérification profil)
router.post('/send-otp',   AuthController.sendOtpValidators,   AuthController.sendOtp);
router.post('/verify-otp', AuthController.verifyOtpValidators, AuthController.verifyOtp);

// Routes publiques — Email
router.post('/register',         AuthController.registerEmailValidators,   AuthController.registerEmail);
router.post('/login',            AuthController.loginEmailValidators,      AuthController.loginEmail);
router.post('/send-email-otp',   AuthController.emailOtpValidators,        AuthController.sendEmailOtp);
router.post('/verify-email-otp', AuthController.verifyEmailOtpValidators,  AuthController.verifyEmailOtp);

router.post('/refresh',    AuthController.refreshToken);

// ─── Route d'initialisation Admin ────────────────────────────────────────────
/*
router.post('/admin/create', (req, res, next) => {
  const setupSecret = req.headers['x-admin-setup-secret'];
  if (!setupSecret || setupSecret !== process.env.ADMIN_SETUP_SECRET) {
    return res.status(403).json({ message: 'Secret de configuration invalide ou manquant.' });
  }
  next();
}, AuthController.createAdmin);
*/

// Routes protégées
router.get  ('/profile',      authMiddleware, AuthController.getProfile);
router.get  ('/streak',       authMiddleware, AuthController.getStreakHandler);
router.post ('/logout',       authMiddleware, AuthController.logout);
router.patch('/accept-terms', authMiddleware, AuthController.acceptTerms);

export default router;
