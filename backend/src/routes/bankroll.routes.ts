import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/bankroll.controller';
import { valider } from '../middleware/valider';
import {
  apercuCombineBankroll, budgetBankroll, combineBankroll, confirmationMise, couvertureBankroll, pariBankroll,
  resultatSelectionLibre,
} from '../schemas/entrees';

const r = Router();

r.get   ('/',          authMiddleware, C.getBankroll);
r.post  ('/budget',    authMiddleware, valider({ body: budgetBankroll }), C.setBudget);
r.post  ('/reset',     authMiddleware, C.resetBankroll);
r.post  ('/bet',       authMiddleware, valider({ body: pariBankroll }), C.placeBet);
r.post  ('/bet/:id/confirmer', authMiddleware, valider({ body: confirmationMise }), C.confirmerMise);
r.get   ('/stats',     authMiddleware, C.getStats);
r.get   ('/suggest',   authMiddleware, C.getSuggestedStake);
// La couverture de sa mise sur ce pronostic, maintenant (26 novembre 2026).
r.get   ('/couverture/:pronosticId', authMiddleware, C.getCouverture);
// « J'ai couvert » et les coupons combinés (27 novembre 2026).
r.post  ('/couvertures', authMiddleware, valider({ body: couvertureBankroll }), C.enregistrerCouverture);
r.post  ('/combines/apercu', authMiddleware, valider({ body: apercuCombineBankroll }), C.apercuCombine);
r.post  ('/combines', authMiddleware, valider({ body: combineBankroll }), C.placerCombine);
r.get   ('/combines/:id/couverture', authMiddleware, C.getCouvertureCombine);
r.post  ('/combines/:id/selections/:selectionId/resultat', authMiddleware,
  valider({ body: resultatSelectionLibre }), C.reglerSelectionLibre);

// ── Admin ─────────────────────────────────────────────────────────────────────
r.get   ('/admin/list',      adminMiddleware, C.adminListBankrolls);
// Avant `/admin/:userId` : sans cela « stats » serait capté comme un
// identifiant d'utilisateur par la route paramétrée.
r.get   ('/admin/stats',     adminMiddleware, C.adminBankrollStats);
r.get   ('/admin/:userId',   adminMiddleware, C.adminGetBankrollDetail);

export default r;
