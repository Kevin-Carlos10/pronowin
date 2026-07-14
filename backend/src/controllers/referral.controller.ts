import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { ReferralService } from '../services/referral.service';

const svc = new ReferralService();

export const getStats = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getStats(req.userId!)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const applyCode = async (req: AuthRequest, res: Response) => {
  const { referral_code } = req.body;
  if (!referral_code?.trim()) {
    res.status(422).json({ message: 'Code parrainage requis.' }); return;
  }
  try {
    res.json(await svc.applyReferralCode(req.userId!, referral_code.trim().toUpperCase()));
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const requestWithdrawal = async (req: AuthRequest, res: Response) => {
  const { amount, method, phone, use_as_credit } = req.body;
  if (!amount || amount < 1) {
    res.status(422).json({ message: 'Montant invalide.' }); return;
  }
  try {
    res.json(await svc.requestWithdrawal({
      userId:      req.userId!,
      amount:      parseFloat(amount),
      method:      method ?? 'orange_money',
      phone:       phone  ?? '',
      useAsCredit: use_as_credit === true || use_as_credit === 'true',
    }));
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const getHistory = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getEarningsHistory(req.userId!)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};
