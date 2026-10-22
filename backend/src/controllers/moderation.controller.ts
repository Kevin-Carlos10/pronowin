import { Response } from 'express';

import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { ModerationService } from '../services/moderation.service';
import { repondreErreur } from '../utils/erreurs';

const svc = new ModerationService();

// ─── Membres ────────────────────────────────────────────────────────────────

export const signaler = async (req: AuthRequest, res: Response) => {
  try {
    const { comment_id, motif, detail } = req.body;
    await svc.signaler(req.userId!, comment_id, motif, detail);
    res.status(201).json({ message: 'Merci, le commentaire a été signalé.' });
  } catch (e) { repondreErreur(res, e); }
};

export const listeBloques = async (req: AuthRequest, res: Response) => {
  try {
    res.json({ data: await svc.listeBloques(req.userId!) });
  } catch (e) { repondreErreur(res, e); }
};

export const bloquer = async (req: AuthRequest, res: Response) => {
  try {
    await svc.bloquer(req.userId!, req.body.user_id);
    res.status(201).json({ message: 'Membre bloqué.' });
  } catch (e) { repondreErreur(res, e); }
};

export const debloquer = async (req: AuthRequest, res: Response) => {
  try {
    await svc.debloquer(req.userId!, req.params.userId);
    res.json({ message: 'Membre débloqué.' });
  } catch (e) { repondreErreur(res, e); }
};

// ─── Panneau d'administration ───────────────────────────────────────────────

export const commentairesSignales = async (req: AdminRequest, res: Response) => {
  try {
    const statut = req.query.statut === 'traites' ? 'traites' : 'en_attente';
    const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10) || 1);
    const parPage = 20;
    const { total, data } = await svc.commentairesSignales(statut, page, parPage);
    res.json({ data, total, page, per_page: parPage, total_pages: Math.max(1, Math.ceil(total / parPage)) });
  } catch (e) { repondreErreur(res, e); }
};

export const aTraiter = async (_req: AdminRequest, res: Response) => {
  try {
    res.json({ a_traiter: await svc.aTraiter() });
  } catch (e) { repondreErreur(res, e); }
};

export const trancher = async (req: AdminRequest, res: Response) => {
  try {
    const nom = req.acteurAdmin?.nom ?? 'Admin';
    res.json(await svc.trancher(req.params.commentId, req.body.decision, nom));
  } catch (e) { repondreErreur(res, e); }
};
