import { Router } from 'express';
import * as AuthController from '../controllers/auth.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

// Routes publiques — WhatsApp OTP (pour vérification profil)
router.post('/send-otp',   AuthController.sendOtpValidators,   AuthController.sendOtp);
router.post('/verify-otp', AuthController.verifyOtpValidators, AuthController.verifyOtp);

/*
 * Connexion par e-mail — code à usage unique, sans mot de passe.
 *
 * Trois routes ont été retirées ici, et pas seulement parce qu'aucun client ne
 * les appelait :
 *
 *   POST /quick-register  acceptait un e-mail nu et, si le compte existait,
 *                         renvoyait des jetons valides pour ce compte. Connaître
 *                         l'adresse d'un utilisateur suffisait à prendre sa
 *                         place. Aucune limitation de débit n'était appliquée.
 *   POST /register        posait le mot de passe de l'appelant sur tout compte
 *                         dépourvu de `passwordHash` — donc sur tous ceux créés
 *                         par OTP ou Google — puis renvoyait des jetons.
 *   POST /set-password    n'avait plus d'objet une fois la connexion par mot de
 *                         passe supprimée.
 *
 * Le code envoyé par e-mail est désormais le seul chemin d'entrée, avec Google.
 */
router.post('/send-email-otp',   AuthController.emailOtpValidators,        AuthController.sendEmailOtp);
router.post('/verify-email-otp', AuthController.verifyEmailOtpValidators,  AuthController.verifyEmailOtp);

// Connexion Google — le jeton est vérifié auprès de Google côté serveur.
router.post('/google', AuthController.googleLoginValidators, AuthController.googleLogin);

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

// Routes protégées — profil & session
router.get  ('/profile',      authMiddleware, AuthController.getProfile);
router.get  ('/streak',       authMiddleware, AuthController.getStreakHandler);
router.post ('/logout',       authMiddleware, AuthController.logout);
router.patch('/accept-terms', authMiddleware, AuthController.acceptTerms);

// Routes protégées — liaison de compte (phone ↔ email → même compte)
// Étape 1 : envoyer l'OTP (réutilise les endpoints publics send-otp / send-email-otp)
// Étape 2 : vérifier et lier
router.post('/link-phone',    authMiddleware, AuthController.linkPhone);
router.post('/link-email',    authMiddleware, AuthController.linkEmail);

export default router;
