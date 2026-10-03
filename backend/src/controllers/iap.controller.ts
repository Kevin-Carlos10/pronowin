import { Request, Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { IapService, IAP_PRODUCTS, IapStoreName } from '../services/iap.service';
import {
  FileNotificationsIap, identifiantApple, identifiantGoogle,
} from '../services/iap_notifications.service';
import logger from '../utils/logger';
import { repondreErreur } from '../utils/erreurs';

const svc = new IapService();
const file = new FileNotificationsIap(svc);

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
    repondreErreur(res, e, 422);
  }
};

/**
 * Webhooks des stores : inscrire, puis acquitter.
 *
 * Ils traitaient la notification pendant la requête et répondaient 200 quoi
 * qu'il arrive — un échec de traitement compris. Pour le store, 200 veut dire
 * « reçu, ne renvoie pas » : une panne de la base pendant un renouvellement,
 * et l'événement était perdu (constat I10).
 *
 * L'événement est désormais inscrit dans une file durable
 * (`iap_notifications.service.ts`) avant l'acquittement, puis traité — et
 * retraité — par une tâche de fond. Si l'inscription échoue, la réponse est
 * 503 : c'est alors le store qui réessaie. Un doublon est acquitté sans être
 * réinscrit.
 */
async function inscrire(res: Response, store: 'apple' | 'google', evenementId: string, charge: object) {
  try {
    const { doublon } = await file.recevoir(store, evenementId, charge);
    res.status(200).json({ recue: true, doublon });
    // Traitement immédiat, sans retenir la réponse : la tâche de fond ne
    // sert que de filet.
    setImmediate(() => { file.traiterEnAttente().catch(() => {}); });
  } catch (e: any) {
    logger.error(`[IAP] Notification ${store} non inscrite : ${e?.message ?? e}`);
    res.status(503).json({ message: 'Réception momentanément impossible, réessayez.' });
  }
}

/** POST /subscriptions/iap/apple-notifications */
export const appleNotifications = async (req: Request, res: Response) => {
  const { signedPayload } = req.body as { signedPayload?: string };
  if (!signedPayload) { res.status(200).json({ ignored: true }); return; }
  await inscrire(res, 'apple', identifiantApple(signedPayload), { signedPayload });
};

/** POST /subscriptions/iap/google-notifications — push Pub/Sub. */
export const googleNotifications = async (req: Request, res: Response) => {
  const message = req.body?.message;
  if (!message?.data) { res.status(200).json({ ignored: true }); return; }
  await inscrire(res, 'google', identifiantGoogle(message), { message });
};
