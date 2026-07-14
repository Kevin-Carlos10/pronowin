import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/users_admin.controller';

const r = Router();
r.use(adminMiddleware);

r.get ('/',              C.getUsers);
r.get ('/stats',         C.getStats);
r.get ('/export/csv',    C.exportCsv);
r.get ('/:id',           C.getUserDetail);
r.patch('/:id/suspend',  C.toggleSuspend);
r.post ('/:id/premium',  C.grantPremium);
r.delete('/:id/premium', C.revokePremium);
r.post ('/:id/notify',   C.sendNotification);
r.patch('/:id/pseudo',   C.updatePseudo);

export default r;
