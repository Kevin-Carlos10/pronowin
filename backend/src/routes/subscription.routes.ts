import { Router } from 'express';
import { authMiddleware }       from '../middleware/auth.middleware';
import { adminMiddleware }      from '../middleware/admin.middleware';
import { requireProfileComplete } from '../middleware/profile.middleware';
import * as C from '../controllers/subscription.controller';

const r = Router();

// Publique
r.get('/plans', C.getPlans);

// Utilisateur
r.get ('/current',       authMiddleware, C.getCurrent);
r.get ('/proof-status',  authMiddleware, C.getProofStatus);
r.post('/upload-url',    authMiddleware, requireProfileComplete, C.getUploadUrl);
r.post('/submit-proof',  authMiddleware, requireProfileComplete, C.submitProof);

// Admin
r.get  ('/admin/proofs',      adminMiddleware, C.getPendingProofs);
r.patch('/admin/proofs/:id',  adminMiddleware, C.reviewProof);

export default r;
