import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { PaymentService } from '../services/payment.service';
import { listerPubliques } from '../services/payment_method.service';
import { lirePagination } from '../utils/pagination';
import { repondreErreur } from '../utils/erreurs';

/**
 * Versements Mobile Money — administration seulement.
 *
 * Les routes utilisateur (`createRequest`, `getTransactions`, `getWallet`) ont
 * été retirées avec le portefeuille dépôt/retrait : plus aucun client ne les
 * appelait depuis la suppression de l'écran mobile correspondant. Ne subsiste
 * que l'approbation des versements de gains de parrainage.
 */

const svc = new PaymentService();

export const getPending = async (req: AdminRequest, res: Response) => {
  try {
    // Jusqu'à 1 000 lignes par page : c'est la taille des exports du panneau.
    const { page, perPage } = lirePagination(req.query, { max: 1000 });
    const texte = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 80) : undefined);
    res.json(await svc.getPendingRequests({
      page, perPage, search: texte(req.query.search), method: texte(req.query.method) }));
  } catch (e: any) { repondreErreur(res, e); }
};

/** Clés des méthodes actives — alimente les filtres de l'administration. */
export const getPaymentMethods = async (_req: AdminRequest, res: Response) => {
  res.json((await listerPubliques()).map(m => m.key));
};

export const processRequest = async (req: AdminRequest, res: Response) => {
  const { status, admin_note } = req.body;
  if (!['completed', 'rejected'].includes(status)) {
    res.status(422).json({ message: 'Statut invalide. Utilisez "completed" ou "rejected".' });
    return;
  }
  try {
    const r = await svc.processRequest({
      transactionId: req.params.id,
      adminId:       req.adminId!,
      status,
      adminNote:     admin_note,
    });
    res.json(r);
  } catch (e: any) { repondreErreur(res, e, 400); }
};
