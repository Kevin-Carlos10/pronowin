import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/notification.controller';

// Monté sur /admin/notifications — chemins attendus de longue date par la page
// « Notifications » de l'admin-web, qui postait dans le vide (404).
const r = Router();

r.get ('/preview', adminMiddleware, C.previewSegment);
r.post('/send',    adminMiddleware, C.sendSegment);

export default r;
