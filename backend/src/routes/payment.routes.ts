import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/payment.controller';

/**
 * Versements Mobile Money — routes d'administration.
 *
 * Les trois routes utilisateur (`/wallet`, `/request`, `/transactions`) ont été
 * retirées avec le portefeuille dépôt/retrait. Aucune n'avait d'appelant
 * depuis la suppression de l'écran mobile : `POST /request` était le seul
 * moyen de créer un dépôt, il n'en existe donc plus.
 *
 * Ce qui reste sert à approuver les versements de gains de parrainage, créés
 * par `POST /referral/withdraw`.
 */
const r = Router();

r.get   ('/admin/pending', adminMiddleware, C.getPending);
r.get   ('/admin/methods', adminMiddleware, C.getPaymentMethods);
r.patch ('/admin/:id',     adminMiddleware, C.processRequest);

export default r;
