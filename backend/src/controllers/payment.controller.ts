import { Response } from 'express';
import { body, validationResult } from 'express-validator';
import { AuthRequest }  from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { PaymentService, MOBCASH_NUMBERS } from '../services/payment.service';

const svc = new PaymentService();

// ── Validators ────────────────────────────────────────────────────────────────
export const createRequestValidators = [
  body('type').isIn(['deposit', 'withdrawal']).withMessage('Type invalide.'),
  body('amount').isFloat({ min: 500, max: 5000000 }).withMessage('Montant invalide (500 – 5 000 000 FCFA).'),
  body('method').isIn(Object.keys(MOBCASH_NUMBERS)).withMessage('Méthode invalide.'),
  body('xbet_id').notEmpty().withMessage('ID 1xBet requis.'),
  body('sender_phone').notEmpty().withMessage('Numéro Mobile Money requis.'),
];

// ── UTILISATEUR ───────────────────────────────────────────────────────────────
export const createRequest = async (req: AuthRequest, res: Response) => {
  const err = validationResult(req);
  if (!err.isEmpty()) { res.status(422).json({ message: err.array()[0].msg }); return; }
  try {
    const r = await svc.createRequest({
      userId:      req.userId!,
      type:        req.body.type,
      amount:      parseFloat(req.body.amount),
      method:      req.body.method,
      xbetId:      req.body.xbet_id,
      senderPhone: req.body.sender_phone,
    });
    res.status(201).json(r);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const getTransactions = async (req: AuthRequest, res: Response) => {
  try {
    res.json(await svc.getUserTransactions(req.userId!, parseInt((req.query.page as string) ?? '1')));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getWallet = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getWalletInfo(req.userId!)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const getPending = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.getPendingRequests(parseInt((req.query.page as string) ?? '1')));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
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
      adminId:       req.adminId!,           // ← AdminRequest.adminId (corrigé)
      status,
      adminNote:     admin_note,
    });
    res.json(r);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};
