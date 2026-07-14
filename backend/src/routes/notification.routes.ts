import { Router } from 'express';
import { authMiddleware }  from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/notification.controller';

const r = Router();

// ── Utilisateur ───────────────────────────────────────────────────────────────
r.get ('/my',                       authMiddleware,  C.getMyNotifications);
r.patch('/:id/read',                authMiddleware,  C.markOneRead);
r.post ('/mark-all-read',           authMiddleware,  C.markAllRead);
r.post ('/register-token',          authMiddleware,  C.registerToken);

// ── Admin ─────────────────────────────────────────────────────────────────────
r.post('/admin/send-user/:userId',  adminMiddleware, C.sendToUser);
r.post('/admin/send-topic',         adminMiddleware, C.sendToTopic);

export default r;
