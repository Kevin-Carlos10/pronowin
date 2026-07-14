import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/tutorial_admin.controller';

const r = Router();
r.use(adminMiddleware);

r.get   ('/',              C.getAll);
r.get   ('/stats',         C.getStats);
r.post  ('/seed',          C.seed);
r.get   ('/:id',           C.getOne);
r.post  ('/',              C.create);
r.patch ('/:id',           C.update);
r.delete('/:id',           C.remove);
r.patch ('/:id/premium',   C.togglePremium);

export default r;
