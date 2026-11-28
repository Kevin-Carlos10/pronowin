import { Request, Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { creerPaiement, etatPaiement, traiterWebhook } from '../services/geniuspay.service';
import { repondreErreur } from '../utils/erreurs';
import { journal } from '../utils/logger';

/** Ouvre un paiement Mobile Money et renvoie l'adresse de la page GeniusPay. */
export const creer = async (req: AuthRequest, res: Response) => {
  try { res.status(201).json(await creerPaiement(req.userId!, String(req.body?.plan ?? ''))); }
  catch (e: any) { repondreErreur(res, e); }
};

/** L'état d'un paiement de l'utilisateur, relu chez GeniusPay s'il est en cours. */
export const etat = async (req: AuthRequest, res: Response) => {
  try { res.json(await etatPaiement(req.userId!, String(req.params.id))); }
  catch (e: any) { repondreErreur(res, e); }
};

/**
 * Webhook GeniusPay. Pas d'authMiddleware : l'authenticité vient de la
 * signature HMAC, et le webhook ne fait que déclencher une relecture du
 * paiement chez GeniusPay. Le corps arrive brut (analyseurs_json.ts).
 */
export const webhook = async (req: Request, res: Response) => {
  const corps = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  try {
    const { code, relecture } = await traiterWebhook(req.headers, corps);
    // Répondre d'abord : GeniusPay attend moins de 5 secondes.
    res.status(code).json({ recu: true });
    await relecture?.catch((e: Error) =>
      journal.error('[GeniusPay] Relecture après webhook', { message: e.message }));
  } catch (e: any) {
    journal.error('[GeniusPay] Webhook', { message: e?.message });
    if (!res.headersSent) res.status(500).json({ recu: false });
  }
};
