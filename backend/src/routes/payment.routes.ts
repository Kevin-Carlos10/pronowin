import { Router } from 'express';
import { authMiddleware }  from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/payment.controller';

const r = Router();

// ── Routes UTILISATEURS ───────────────────────────────────────────────────────
r.get ('/wallet',       authMiddleware, C.getWallet);
r.post('/request',      authMiddleware, C.createRequestValidators, C.createRequest);
r.get ('/transactions', authMiddleware, C.getTransactions);

// ── Routes ADMIN ──────────────────────────────────────────────────────────────
r.get ('/admin/pending', adminMiddleware, C.getPending);
r.patch('/admin/:id',    adminMiddleware, C.processRequest);

export default r;
