import { Response } from 'express';
import { Request }  from 'express';
import { AuthRequest }  from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { SubscriptionService } from '../services/subscription.service';
import { repondreErreur } from '../utils/erreurs';

const svc = new SubscriptionService();

// ── PUBLIQUE ──────────────────────────────────────────────────────────────────
export const getPlans = async (_: Request, res: Response) => res.json(await svc.getPlans());

// ── UTILISATEUR ───────────────────────────────────────────────────────────────
export const getCurrent = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getCurrentSubscription(req.userId!)); }
  catch (e: any) { repondreErreur(res, e); }
};

export const getProofStatus = async (req: AuthRequest, res: Response) => {
  try {
    const status = await svc.getProofStatus(req.userId!);
    res.json(status ?? { status: 'none' });
  } catch (e: any) { repondreErreur(res, e); }
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
  } catch (e: any) { repondreErreur(res, e); }
};

/** Soumettre une preuve (base64 ou URL déjà uploadée) */
export const submitProof = async (req: AuthRequest, res: Response) => {
  const { type, image_base64, screenshot_url, xbet_id, platform, amount, sender_phone, plan_id } = req.body;

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
      userId:             req.userId!,
      type,
      imageBase64:        image_base64,
      screenshotUrl:      screenshot_url,
      xbetId:             xbet_id,
      platform:           platform,
      amount:             amount ? parseFloat(amount) : undefined,
      senderPhone:        sender_phone,
      planId:             plan_id,
    });
    res.status(201).json(result);
  } catch (e: any) { repondreErreur(res, e, 400); }
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const getPendingProofs = async (req: AdminRequest, res: Response) => {
  try {
    // `per_page` etait ignore : le service retombait sur son defaut de 20,
    // quelle que soit la valeur envoyee. Le panneau admin en demandait 5000
    // pour que sa recherche couvre toute la file — la valeur etait jetee ici,
    // et une preuve au-dela de la 20e ressortait « introuvable ».
    const page    = parseInt((req.query.page as string)     ?? '1') || 1;
    const perPage = parseInt((req.query.per_page as string) ?? '20') || 20;
    const statutQ = (req.query.status as string) ?? 'pending';
    const statut  = (['pending', 'approved', 'rejected', 'all'].includes(statutQ)
                      ? statutQ : 'pending') as 'pending' | 'approved' | 'rejected' | 'all';

    res.json(await svc.listProofs({
      page, perPage, statut,
      recherche: (req.query.search as string) ?? '',
    }));
  } catch (e: any) { repondreErreur(res, e); }
};

export const reviewProof = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.reviewProof({
      proofId:      req.params.id,
      // Qui a réellement tranché. Le jeton est celui du compte de service,
      // partagé par tous les sous-admins : `req.adminId` inscrivait donc le
      // même auteur sur chaque preuve. La délégation nomme la personne.
      adminId:      req.acteurAdmin?.role === 'sub'
        ? `sub:${req.acteurAdmin.id}`
        : req.adminId!,
      approved:     req.body.approved === true || req.body.approved === 'true',
      adminNote:    req.body.admin_note,
      durationDays: req.body.duration_days ? parseInt(req.body.duration_days) : 30,
      xbetId:       req.body.xbet_id,
    });
    res.json(result);
  } catch (e: any) {
    // 409 : la preuve a été traitée entre l'affichage et le clic — par un
    // collègue, ou par un double envoi du formulaire. Ce n'est pas une saisie
    // invalide.
    res.status(/déjà traitée/.test(e.message) ? 409 : 400).json({ message: e.message });
  }
};
