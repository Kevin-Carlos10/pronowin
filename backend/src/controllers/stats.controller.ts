import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { StatsService } from '../services/stats.service';

const svc = new StatsService();

export const getDashboard = async (req: AdminRequest, res: Response) => {
  const days = parseInt(req.query.days as string ?? '30');
  try { res.json(await svc.getDashboardStats(days)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getRevenueSeries = async (req: AdminRequest, res: Response) => {
  const days = parseInt(req.query.days as string ?? '30');
  try { res.json(await svc.getRevenueTimeSeries(days)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getUsersSeries = async (req: AdminRequest, res: Response) => {
  const days = parseInt(req.query.days as string ?? '30');
  try { res.json(await svc.getUsersTimeSeries(days)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getTopUsers = async (req: AdminRequest, res: Response) => {
  try { res.json(await svc.getTopUsers(10)); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};
