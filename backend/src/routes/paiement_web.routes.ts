import { Router, Request, Response } from 'express';
import {
  envoyerCode, lireJetonPaiement, offreWeb, payer, suivre, verifierCode,
} from '../services/paiement_web.service';
import { repondreErreur } from '../utils/erreurs';

/**
 * Paiement Mobile Money depuis le site (pronowin.space/premium).
 *
 * Identification par code e-mail, puis un jeton de paiement de 30 minutes
 * (paiement_web.service.ts) — jamais une session de l'application.
 */
const r = Router();

function compteDuJeton(req: Request, res: Response): string | null {
  const entete = req.headers.authorization ?? '';
  const userId = lireJetonPaiement(entete.startsWith('Bearer ') ? entete.slice(7) : undefined);
  if (!userId) res.status(401).json({ message: 'Identification expirée : recommence avec ton adresse e-mail.' });
  return userId;
}

r.get('/offre', (_req, res) => { res.json(offreWeb()); });

r.post('/code', async (req, res) => {
  try { res.json(await envoyerCode(req.body?.email)); }
  catch (e: any) { repondreErreur(res, e); }
});

r.post('/verifier', async (req, res) => {
  try { res.json(await verifierCode(req.body?.email, req.body?.code)); }
  catch (e: any) { repondreErreur(res, e); }
});

r.post('/payer', async (req, res) => {
  const userId = compteDuJeton(req, res);
  if (!userId) return;
  try { res.status(201).json(await payer(userId, req.body?.plan)); }
  catch (e: any) { repondreErreur(res, e); }
});

r.get('/etat/:id', async (req, res) => {
  const userId = compteDuJeton(req, res);
  if (!userId) return;
  try { res.json(await suivre(userId, String(req.params.id))); }
  catch (e: any) { repondreErreur(res, e); }
});

export default r;
