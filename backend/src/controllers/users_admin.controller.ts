import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { UsersAdminService } from '../services/users_admin.service';

const svc = new UsersAdminService();

export const getUsers = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.getUsers({
      page:    parseInt(req.query.page    as string ?? '1'),
      perPage: parseInt(req.query.per_page as string ?? '20'),
      search:  req.query.search  as string,
      plan:    req.query.plan    as string,
      status:  req.query.status  as string,
      sortBy:  req.query.sort_by as string,
      sortDir: (req.query.sort_dir as 'asc' | 'desc') ?? 'desc',
    });
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getUserDetail = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.getUserDetail(req.params.id)); }
  catch (e: any) { res.status(404).json({ message: e.message }); }
};

export const toggleSuspend = async (req: AdminRequest, res: Response) => {
  try {
    const suspend = req.body.suspend === true || req.body.suspend === 'true';
    res.json(await svc.toggleSuspend(req.params.id, suspend, req.body.reason));
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const grantPremium = async (req: AdminRequest, res: Response) => {
  try {
    const days = parseInt(req.body.duration_days ?? '30');
    res.json(await svc.grantPremium(req.params.id, days, req.adminId!));
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const revokePremium = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.revokePremium(req.params.id)); }
  catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const sendNotification = async (req: AdminRequest, res: Response) => {
  const { title, body } = req.body;
  if (!title || !body) { res.status(422).json({ message: 'Titre et message requis.' }); return; }
  try { res.json(await svc.sendNotification(req.params.id, title, body)); }
  catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const updatePseudo = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.updatePseudo(req.params.id, req.body.pseudo)); }
  catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const exportCsv = async (req: AdminRequest, res: Response) => {
  try {
    const csv = await svc.exportCsv(req.query.plan as string);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="pronowin_users_${new Date().toISOString().split('T')[0]}.csv"`);
    res.send('\uFEFF' + csv); // BOM pour Excel
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getStats()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};
