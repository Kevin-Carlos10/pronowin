import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { StatsService } from '../services/stats.service';
import { prisma } from '../lib/prisma';

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

// GET /admin/stats/online — utilisateurs actifs ces 2 dernières minutes (jamais caché)
export const getOnlineCount = async (_req: AdminRequest, res: Response) => {
  try {
    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000);
    const count = await prisma.user.count({
      where: { isActive: true, lastSeenAt: { gte: twoMinAgo } },
    });
    res.json({ count });
  } catch (e: any) { res.status(500).json({ count: 0 }); }
};

// GET /admin/stats/signups?days=14 — inscriptions par jour (format dashboard)
export const getSignups = async (req: AdminRequest, res: Response) => {
  const days  = Math.min(parseInt(req.query.days as string ?? '14'), 90);
  const start = new Date(Date.now() - days * 86400000);
  try {
    const users = await prisma.user.findMany({
      where:   { createdAt: { gte: start } },
      select:  { createdAt: true },
      orderBy: { createdAt: 'asc' },
    });

    const byDay: Record<string, number> = {};
    for (let i = 0; i < days; i++) {
      const d = new Date(start.getTime() + i * 86400000);
      byDay[d.toISOString().slice(0, 10)] = 0;
    }
    for (const u of users) {
      const key = u.createdAt.toISOString().slice(0, 10);
      if (byDay[key] !== undefined) byDay[key]++;
    }

    const labels = Object.keys(byDay).map(d =>
      new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })
    );
    const values = Object.values(byDay);
    const oneWeekAgo = new Date(Date.now() - 7 * 86400000);
    const newThisWeek = users.filter(u => u.createdAt >= oneWeekAgo).length;

    res.json({ labels, values, newThisWeek });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// GET /admin/stats/pronostics — taux de succès (format dashboard)
export const getPronosticsStats = async (_req: AdminRequest, res: Response) => {
  try {
    const [won, lost, pending] = await Promise.all([
      prisma.pronostic.count({ where: { result: 'WIN' } }),
      prisma.pronostic.count({ where: { result: 'LOSS' } }),
      prisma.pronostic.count({ where: { result: null, isPublished: true } }),
    ]);
    res.json({ won, lost, pending });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
