import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import * as C from '../controllers/referral.controller';

const r = Router();
r.use(authMiddleware);
r.get ('/',           C.getStats);
r.post('/apply-code', C.applyCode);
r.post('/withdraw',   C.requestWithdrawal);
r.get ('/history',    C.getHistory);

export default r;

