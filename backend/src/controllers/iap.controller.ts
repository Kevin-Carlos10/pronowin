import { Request, Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { IapService, IAP_PRODUCTS, IapStoreName } from '../services/iap.service';

const svc = new IapService();

/**
 * GET /subscriptions/iap/products
 *
 * Le mobile a besoin des identifiants exacts pour interroger le store ; les
 * coder en dur des deux côtés garantit qu'ils divergeront un jour.
 */
export const getProducts = (_req: Request, res: Response) => {
  res.json({
    product_ids: Object.keys(IAP_PRODUCTS),
    products: Object.entries(IAP_PRODUCTS).map(([id, p]) => ({
      product_id: id, plan: p.plan, fallback_days: p.fallbackDays,
    })),
  });
};

/**
 * POST /subscriptions/iap/verify
 *
 * Appelé après un achat ET à chaque restauration. Le reçu n'est jamais cru sur
 * parole côté client : c'est le store qui est interrogé.
 */
export const verify = async (req: AuthRequest, res: Response) => {
  const { store, receipt } = req.body as { store?: string; receipt?: string };

  if (store !== 'apple' && store !== 'google') {
    res.status(422).json({ message: 'store doit valoir « apple » ou « google ».' }); return;
  }
  if (!receipt?.trim()) {
    res.status(422).json({ message: 'receipt requis.' }); return;
  }

  try {
    res.json(await svc.verifyAndRecord({
      userId:  req.userId!,
      store:   store as IapStoreName,
      receipt: receipt.trim(),
    }));
  } catch (e: any) {
    // 422 et non 500 : ces échecs sont presque toujours dus au reçu lui-même
    // (produit inconnu, reçu de test, achat déjà rattaché), pas au serveur.
    res.status(422).json({ message: e.message });
  }
};

/**
 * POST /subscriptions/iap/apple-notifications
 *
 * Webhook public : la signature du JWS est vérifiée dans le service. On répond
 * toujours 200 — un non-2xx déclenche chez Apple une longue série de
 * réessais, y compris pour des événements qu'on ignore volontairement.
 */
export const appleNotifications = async (req: Request, res: Response) => {
  try {
    const { signedPayload } = req.body as { signedPayload?: string };
    if (!signedPayload) { res.status(200).json({ ignored: true }); return; }
    res.status(200).json(await svc.handleAppleNotification(signedPayload));
  } catch (e: any) {
    console.error('[IAP] Notification Apple rejetée :', e.message);
    res.status(200).json({ ignored: true, error: e.message });
  }
};

/**
 * POST /subscriptions/iap/google-notifications
 *
 * Push Pub/Sub. Même logique : toujours 200, sinon Pub/Sub rejoue en boucle.
 */
export const googleNotifications = async (req: Request, res: Response) => {
  try {
    res.status(200).json(await svc.handleGoogleNotification(req.body?.message ?? {}));
  } catch (e: any) {
    console.error('[IAP] Notification Google rejetée :', e.message);
    res.status(200).json({ ignored: true, error: e.message });
  }
};
