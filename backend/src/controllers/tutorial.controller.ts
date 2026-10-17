import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { TutorialService } from '../services/tutorial.service';
import { repondreErreur } from '../utils/erreurs';
import { requeteIphone, tutorielDePari } from '../utils/sans_pari';

const svc = new TutorialService();

// Version iPhone : aucun tutoriel de pari, ni dans la liste, ni par son
// identifiant, ni dans la progression (utils/sans_pari.ts).

export const getAll = async (req: AuthRequest, res: Response) => {
  try {
    const tous = await svc.getAll({
      category: req.query.category as string | undefined,
      level:    req.query.level    as string | undefined,
      userId:   req.userId,
    });
    res.json(requeteIphone(req.headers) ? tous.filter(t => !tutorielDePari(t)) : tous);
  } catch (e: any) { repondreErreur(res, e); }
};

export const getOne = async (req: AuthRequest, res: Response) => {
  try {
    const t = await svc.getOne(req.params.id, req.userId);
    if (requeteIphone(req.headers) && tutorielDePari(t)) {
      res.status(404).json({ message: 'Tutoriel introuvable.' });
      return;
    }
    res.json(t);
  }
  catch (e: any) { repondreErreur(res, e, 404); }
};

export const markProgress = async (req: AuthRequest, res: Response) => {
  try {
    if (!req.userId) { res.status(401).json({ message: 'Non authentifié.' }); return; }
    const watchedSeconds = parseInt(req.body.watched_seconds ?? '0');
    const completed      = req.body.completed === true || req.body.completed === 'true';
    await svc.markProgress(req.userId, req.params.id, watchedSeconds, completed);
    res.json({ success: true });
  } catch (e: any) { repondreErreur(res, e); }
};

export const getProgress = async (req: AuthRequest, res: Response) => {
  try {
    if (!req.userId) { res.status(401).json({ message: 'Non authentifié.' }); return; }
    const progression = await svc.getProgress(req.userId);
    res.json(requeteIphone(req.headers)
      ? progression.filter(p => !tutorielDePari(p.tutorial))
      : progression);
  } catch (e: any) { repondreErreur(res, e); }
};
