import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { AuthRequest } from '../middleware/auth.middleware';
import { creerPaiement, rapprocherPaiement, traiterWebhook } from '../services/geniuspay.service';
import { repondreErreur } from '../utils/erreurs';
import { journal } from '../utils/logger';

/** Ouvre un paiement Mobile Money et renvoie l'adresse de la page GeniusPay. */
export const creer = async (req: AuthRequest, res: Response) => {
  try { res.status(201).json(await creerPaiement(req.userId!, String(req.body?.plan ?? ''))); }
  catch (e: any) { repondreErreur(res, e); }
};

/**
 * Dernière relecture de chaque paiement chez GeniusPay. L'application
 * interroge l'état toutes les quelques secondes au retour du paiement :
 * sans ce frein, chacune de ses questions deviendrait un appel à GeniusPay.
 */
const derniereRelecture = new Map<string, number>();
const INTERVALLE_RELECTURE_MS = 5_000;

/** L'état d'un paiement de l'utilisateur, relu chez GeniusPay s'il est en cours. */
export const etat = async (req: AuthRequest, res: Response) => {
  try {
    let ligne = await prisma.paiementGeniusPay.findFirst({
      where: { id: String(req.params.id), userId: req.userId! } });
    if (!ligne) { res.status(404).json({ message: 'Paiement introuvable.' }); return; }
    const enCours = !ligne.premiumAccordeLe && ['pending', 'processing'].includes(ligne.statut);
    if (enCours && Date.now() - (derniereRelecture.get(ligne.id) ?? 0) > INTERVALLE_RELECTURE_MS) {
      derniereRelecture.set(ligne.id, Date.now());
      if (derniereRelecture.size > 10_000) derniereRelecture.clear();
      ligne = (await rapprocherPaiement(ligne.id).catch((e: Error) => {
        journal.error('[GeniusPay] Relecture', { id: ligne!.id, message: e.message });
        return ligne;
      })) ?? ligne;
    }
    // La fin du Premium, pour la confirmation affichée par l'application.
    const expireLe = ligne.premiumAccordeLe
      ? (await prisma.user.findUnique({ where: { id: req.userId! },
          select: { subscriptionExpiresAt: true } }))?.subscriptionExpiresAt ?? null
      : null;
    res.json({
      id: ligne.id, statut: ligne.statut, plan: ligne.plan, montant: ligne.montant,
      premium_active: !!ligne.premiumAccordeLe, expire_le: expireLe,
    });
  } catch (e: any) { repondreErreur(res, e); }
};

/**
 * Webhook GeniusPay. Pas d'authMiddleware : l'authenticité vient de la
 * signature HMAC, et le webhook ne fait que déclencher une relecture du
 * paiement chez GeniusPay. Le corps arrive brut (analyseurs_json.ts).
 */
export const webhook = async (req: Request, res: Response) => {
  const corps = Buffer.isBuffer(req.body) ? req.body : Buffer.alloc(0);
  try {
    res.status(await traiterWebhook(req.headers, corps)).json({ recu: true });
  } catch (e: any) {
    journal.error('[GeniusPay] Webhook', { message: e?.message });
    res.status(500).json({ recu: false });
  }
};
