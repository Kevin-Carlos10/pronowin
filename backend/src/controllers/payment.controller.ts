import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { PaymentService } from '../services/payment.service';
import { listerPubliques } from '../services/payment_method.service';

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
    res.json(await svc.getPendingRequests(parseInt((req.query.page as string) ?? '1')));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
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
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};
