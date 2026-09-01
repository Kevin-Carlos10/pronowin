import { Router } from 'express';
import { authMiddleware }       from '../middleware/auth.middleware';
import { adminMiddleware }      from '../middleware/admin.middleware';
import { requireProfileComplete } from '../middleware/profile.middleware';
import * as C from '../controllers/subscription.controller';
import * as IAP from '../controllers/iap.controller';

const r = Router();

// Publique
r.get('/plans', C.getPlans);

// ── Achat intégré (App Store / Google Play) ───────────────────────────────────
r.get ('/iap/products', IAP.getProducts);
r.post('/iap/verify',   authMiddleware, IAP.verify);

// Webhooks des stores : pas d'authMiddleware, l'authenticité vient de la
// signature du payload (Apple) et de l'URL secrète Pub/Sub (Google).
r.post('/iap/apple-notifications',  IAP.appleNotifications);
r.post('/iap/google-notifications', IAP.googleNotifications);

// Utilisateur
r.get ('/current',       authMiddleware, C.getCurrent);
r.get ('/proof-status',  authMiddleware, C.getProofStatus);
r.post('/upload-url',    authMiddleware, requireProfileComplete, C.getUploadUrl);
r.post('/submit-proof',  authMiddleware, requireProfileComplete, C.submitProof);

// Admin
r.get  ('/admin/proofs',      adminMiddleware, C.getPendingProofs);
r.patch('/admin/proofs/:id',  adminMiddleware, C.reviewProof);

export default r;
