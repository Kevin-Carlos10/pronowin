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

/**
 * Fenêtre temporelle commune aux statistiques.
 *
 * `all=1` (bouton « Tout ») lève la borne. On filtre sur `createdAt`, non nul
 * par schéma : `publishedAt` peut manquer sur d'anciennes lignes, et une ligne
 * exclue en silence d'un taux de réussite est pire qu'un périmètre approximatif.
 */
function periodWhere(req: AdminRequest, field = 'createdAt') {
  if (req.query.all === '1' || req.query.all === 'true') return {};
  const days = Math.max(1, Math.min(parseInt(req.query.days as string ?? '30') || 30, 3650));
  return { [field]: { gte: new Date(Date.now() - days * 86400000) } };
}

// GET /admin/stats/pronostics?days=30 — taux de succès sur la période
export const getPronosticsStats = async (req: AdminRequest, res: Response) => {
  try {
    // Le sélecteur de période de la page Statistiques n'était pas transmis :
    // le taux affiché portait sur tout l'historique quel que soit le choix.
    const period = periodWhere(req);
    const [won, lost, pending] = await Promise.all([
      prisma.pronostic.count({ where: { ...period, result: 'WIN'  } }),
      prisma.pronostic.count({ where: { ...period, result: 'LOSS' } }),
      prisma.pronostic.count({ where: { ...period, result: null, isPublished: true } }),
    ]);
    res.json({ won, lost, pending });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/**
 * GET /admin/stats/monthly — 12 derniers mois : inscriptions et revenus.
 *
 * La page Statistiques appelait déjà cet endpoint, qui n'a jamais existé : le
 * 404 était absorbé par un `?.` côté client et le graphique restait
 * désespérément vide, sous un titre promettant « Inscriptions vs Revenus ».
 * « Revenu » reprend la définition de getRevenueTimeSeries : les abonnements
 * Premium encaissés. Elle portait sur les dépôts, qui n'existent plus.
 */
export const getMonthly = async (_req: AdminRequest, res: Response) => {
  try {
    const now   = new Date();
    const start = new Date(now.getFullYear(), now.getMonth() - 11, 1);

    const [users, txs] = await Promise.all([
      prisma.user.findMany({
        where: { createdAt: { gte: start } }, select: { createdAt: true },
      }),
      prisma.subscription.findMany({
        where:  { createdAt: { gte: start } },
        select: { amountPaid: true, createdAt: true },
      }),
    ]);

    const key   = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const slots = new Map<string, { month: string; label: string; new_users: number; revenue: number }>();
    for (let i = 0; i < 12; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() - 11 + i, 1);
      slots.set(key(d), {
        month: key(d),
        label: d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' }),
        new_users: 0, revenue: 0,
      });
    }
    for (const u of users)  { const s = slots.get(key(u.createdAt)); if (s) s.new_users++; }
    for (const t of txs)    { const s = slots.get(key(t.createdAt)); if (s) s.revenue += t.amountPaid; }

    res.json([...slots.values()].map(s => ({ ...s, revenue: Math.round(s.revenue) })));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/**
 * GET /admin/stats/leagues?days=30 — taux de réussite par compétition.
 *
 * La donnée la plus actionnable pour un service de pronostics : elle dit où
 * l'on prédit bien et où l'on se trompe. Les compétitions sans aucun pronostic
 * réglé sont écartées — un taux calculé sur zéro n'informe personne.
 */
export const getLeaguePerformance = async (req: AdminRequest, res: Response) => {
  try {
    const rows = await prisma.pronostic.findMany({
      where:  { ...periodWhere(req), result: { in: ['WIN', 'LOSS', 'PUSH'] } },
      select: { result: true, oddsRecommended: true, match: { select: { league: true, leagueLogo: true } } },
    });

    const byLeague = new Map<string, { league: string; logo: string | null;
                                       won: number; lost: number; push: number; oddsSum: number }>();
    for (const r of rows) {
      const name = r.match?.league ?? '—';
      const acc  = byLeague.get(name)
        ?? { league: name, logo: r.match?.leagueLogo ?? null, won: 0, lost: 0, push: 0, oddsSum: 0 };
      if (r.result === 'WIN')  acc.won++;
      if (r.result === 'LOSS') acc.lost++;
      if (r.result === 'PUSH') acc.push++;
      acc.oddsSum += r.oddsRecommended ?? 0;
      byLeague.set(name, acc);
    }

    const out = [...byLeague.values()].map(a => {
      const decided = a.won + a.lost;          // les remboursements ne comptent pas
      const total   = decided + a.push;
      return {
        league: a.league, logo: a.logo,
        won: a.won, lost: a.lost, push: a.push, total,
        win_rate: decided > 0 ? Math.round((a.won / decided) * 100) : null,
        avg_odds: total > 0 ? +(a.oddsSum / total).toFixed(2) : null,
      };
    })
    // Volume d'abord : un 100 % sur 1 pronostic n'est pas un résultat.
    .sort((a, b) => b.total - a.total || (b.win_rate ?? 0) - (a.win_rate ?? 0));

    res.json(out);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
