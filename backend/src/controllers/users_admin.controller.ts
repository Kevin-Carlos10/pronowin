import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { FiltresUtilisateurs, UsersAdminService } from '../services/users_admin.service';
import { lirePagination } from '../utils/pagination';
import { repondreErreur } from '../utils/erreurs';

const svc = new UsersAdminService();

export const getOnlineUsers = async (_req: AdminRequest, res: Response) => {
  try {
    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
    const users = await (await import('../lib/prisma')).prisma.user.findMany({
      where:   { isActive: true, lastSeenAt: { gte: twoMinAgo } },
      orderBy: { lastSeenAt: 'desc' },
      select:  { id: true, pseudo: true, phoneNumber: true, email: true, subscriptionPlan: true, lastSeenAt: true, countryCode: true },
    });
    res.json({ total: users.length, users });
  } catch (e: any) { repondreErreur(res, e); }
};

/** Les filtres de la liste, lus de la même façon pour l'écran et l'export. */
function filtresDe(req: AdminRequest): FiltresUtilisateurs {
  const texte = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined);
  return {
    search:   texte(req.query.search),
    plan:     texte(req.query.plan),
    status:   texte(req.query.status),
    dateFrom: texte(req.query.date_from),
    dateTo:   texte(req.query.date_to),
    minTx:    parseInt(req.query.min_tx as string ?? '') || undefined,
  };
}

export const getUsers = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.getUsers({
      ...lirePagination(req.query),
      ...filtresDe(req),
      sortBy:   req.query.sort_by   as string,
      sortDir: (req.query.sort_dir  as 'asc' | 'desc') ?? 'desc',
    });
    res.json(result);
  } catch (e: any) { repondreErreur(res, e); }
};

/** PATCH /admin/users/bulk/suspend — suspendre / réactiver un lot de comptes */
export const bulkSuspend = async (req: AdminRequest, res: Response) => {
  try {
    const suspend = req.body.suspend === true || req.body.suspend === 'true';
    res.json(await svc.bulkSuspend(req.body.user_ids, suspend, req.body.reason));
  } catch (e: any) { repondreErreur(res, e, 400); }
};

/** POST /admin/users/bulk/notify — notifier un lot de comptes */
export const bulkNotify = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.bulkNotify(req.body.user_ids, req.body.title, req.body.body));
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const getUserDetail = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.getUserDetail(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 404); }
};

export const toggleSuspend = async (req: AdminRequest, res: Response) => {
  try {
    const suspend = req.body.suspend === true || req.body.suspend === 'true';
    res.json(await svc.toggleSuspend(req.params.id, suspend, req.body.reason));
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const grantPremium = async (req: AdminRequest, res: Response) => {
  try {
    const days = parseInt(req.body.duration_days ?? '30');
    res.json(await svc.grantPremium(req.params.id, days, req.adminId!));
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const revokePremium = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.revokePremium(req.params.id)); }
  catch (e: any) { repondreErreur(res, e, 400); }
};

export const sendNotification = async (req: AdminRequest, res: Response) => {
  const { title, body } = req.body;
  if (!title || !body) { res.status(422).json({ message: 'Titre et message requis.' }); return; }
  try { res.json(await svc.sendNotification(req.params.id, title, body)); }
  catch (e: any) { repondreErreur(res, e, 400); }
};

export const updatePseudo = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.updatePseudo(req.params.id, req.body.pseudo)); }
  catch (e: any) { repondreErreur(res, e, 400); }
};

export const exportCsv = async (req: AdminRequest, res: Response) => {
  try {
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="pronowin_users_${new Date().toISOString().split('T')[0]}.csv"`);
    res.write('\uFEFF' + svc.exportCsvHeader() + '\n'); // BOM pour Excel
    // Les mêmes filtres que la liste : l'export ne recevait que le plan.
    for await (const row of svc.exportCsvRows(filtresDe(req))) {
      res.write(row + '\n');
    }
    res.end();
  } catch (e: any) {
    if (res.headersSent) res.end();
    else repondreErreur(res, e);
  }
};

export const getStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getStats()); }
  catch (e: any) { repondreErreur(res, e); }
};
