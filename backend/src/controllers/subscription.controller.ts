import { Response } from 'express';
import { Request }  from 'express';
import { AuthRequest }  from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { SubscriptionService } from '../services/subscription.service';

const svc = new SubscriptionService();

// ── PUBLIQUE ──────────────────────────────────────────────────────────────────
export const getPlans = (_: Request, res: Response) => res.json(svc.getPlans());

// ── UTILISATEUR ───────────────────────────────────────────────────────────────
export const getCurrent = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getCurrentSubscription(req.userId!)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getProofStatus = async (req: AuthRequest, res: Response) => {
  try {
    const status = await svc.getProofStatus(req.userId!);
    res.json(status ?? { status: 'none' });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** Obtenir une URL pré-signée S3 pour upload depuis le mobile */
export const getUploadUrl = async (req: AuthRequest, res: Response) => {
  const { mime_type } = req.body;
  if (!mime_type || !['image/jpeg', 'image/png', 'image/webp'].includes(mime_type)) {
    res.status(422).json({ message: 'Type MIME invalide. Utilisez image/jpeg ou image/png.' });
    return;
  }
  try {
    const result = await svc.getUploadUrl(req.userId!, mime_type);
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** Soumettre une preuve (base64 ou URL déjà uploadée) */
export const submitProof = async (req: AuthRequest, res: Response) => {
  const { type, image_base64, screenshot_url, xbet_id, amount, sender_phone } = req.body;

  if (!type || !['payment_screenshot', 'xbet_account_screenshot'].includes(type)) {
    res.status(422).json({ message: 'Type de preuve invalide.' });
    return;
  }
  if (!image_base64 && !screenshot_url) {
    res.status(422).json({ message: 'Image requise (base64 ou URL).' });
    return;
  }

  try {
    const result = await svc.submitProof({
      userId:        req.userId!,
      type,
      imageBase64:   image_base64,
      screenshotUrl: screenshot_url,
      xbetId:        xbet_id,
      amount:        amount ? parseFloat(amount) : undefined,
      senderPhone:   sender_phone,
    });
    res.status(201).json(result);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const getPendingProofs = async (req: AdminRequest, res: Response) => {
  try {
    const page = parseInt((req.query.page as string) ?? '1');
    res.json(await svc.getPendingProofs(page));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const reviewProof = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.reviewProof({
      proofId:      req.params.id,
      adminId:      req.adminId!,
      approved:     req.body.approved === true || req.body.approved === 'true',
      adminNote:    req.body.admin_note,
      durationDays: req.body.duration_days ? parseInt(req.body.duration_days) : 30,
    });
    res.json(result);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};
