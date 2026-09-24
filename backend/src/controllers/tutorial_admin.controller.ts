import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { TutorialAdminService } from '../services/tutorial_admin.service';
import { repondreErreur } from '../utils/erreurs';

const svc = new TutorialAdminService();

export const getAll = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.getAll({
      search:   req.query.search   as string,
      category: req.query.category as string,
      level:    req.query.level    as string,
      page:     parseInt(req.query.page     as string ?? '1'),
      perPage:  parseInt(req.query.per_page as string ?? '20'),
    }));
  } catch (e: any) { repondreErreur(res, e); }
};

export const getCategories = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getDistinctCategories()); }
  catch (e: any) { repondreErreur(res, e); }
};

export const getLevels = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getDistinctLevels()); }
  catch (e: any) { repondreErreur(res, e); }
};

export const getOne = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.getOne(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 404); }
};

export const create = async (req: AdminRequest, res: Response) => {
  try {
    const t = await svc.create({
      title:           req.body.title,
      description:     req.body.description,
      level:           req.body.level,
      category:        req.body.category,
      authorName:      req.body.author_name,
      durationSeconds: req.body.duration_seconds ? parseInt(req.body.duration_seconds) : 0,
      isPremium:       req.body.is_premium === 'true' || req.body.is_premium === true,
      videoUrl:        req.body.video_url    || undefined,
      thumbnailUrl:    req.body.thumbnail_url || undefined,
    });
    res.status(201).json(t);
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const update = async (req: AdminRequest, res: Response) => {
  try {
    const t = await svc.update(req.params.id, {
      title:           req.body.title,
      description:     req.body.description,
      level:           req.body.level,
      category:        req.body.category,
      authorName:      req.body.author_name,
      durationSeconds: req.body.duration_seconds ? parseInt(req.body.duration_seconds) : undefined,
      isPremium:       req.body.is_premium !== undefined
                         ? (req.body.is_premium === 'true' || req.body.is_premium === true)
                         : undefined,
      videoUrl:        req.body.video_url,
      thumbnailUrl:    req.body.thumbnail_url,
    });
    res.json(t);
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const remove = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.delete(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 400); }
};

export const togglePremium = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.togglePremium(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 400); }
};

export const getStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getStats()); }
  catch (e: any) { repondreErreur(res, e); }
};

export const seed = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.seed()); }
  catch (e: any) { repondreErreur(res, e); }
};
