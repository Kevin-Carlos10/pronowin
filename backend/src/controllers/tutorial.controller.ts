import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { TutorialService } from '../services/tutorial.service';

const svc = new TutorialService();

export const getAll = async (req: AuthRequest, res: Response) => {
  try {
    res.json(await svc.getAll({
      category: req.query.category as string | undefined,
      level:    req.query.level    as string | undefined,
      userId:   req.userId,
    }));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getOne = async (req: AuthRequest, res: Response) => {
  try { res.json(await svc.getOne(req.params.id, req.userId)); }
  catch (e: any) { res.status(404).json({ message: e.message }); }
};

export const markProgress = async (req: AuthRequest, res: Response) => {
  try {
    if (!req.userId) { res.status(401).json({ message: 'Non authentifié.' }); return; }
    const watchedSeconds = parseInt(req.body.watched_seconds ?? '0');
    const completed      = req.body.completed === true || req.body.completed === 'true';
    await svc.markProgress(req.userId, req.params.id, watchedSeconds, completed);
    res.json({ success: true });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getProgress = async (req: AuthRequest, res: Response) => {
  try {
    if (!req.userId) { res.status(401).json({ message: 'Non authentifié.' }); return; }
    res.json(await svc.getProgress(req.userId));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
