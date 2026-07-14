import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import * as C from '../controllers/bankroll.controller';

const r = Router();

r.get   ('/',          authMiddleware, C.getBankroll);
r.post  ('/budget',    authMiddleware, C.setBudget);
r.post  ('/reset',     authMiddleware, C.resetBankroll);
r.post  ('/bet',       authMiddleware, C.placeBet);
r.get   ('/stats',     authMiddleware, C.getStats);
r.get   ('/suggest',   authMiddleware, C.getSuggestedStake);

export default r;
