import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/stats.controller';

const r = Router();
r.use(adminMiddleware);

r.get('/dashboard',    C.getDashboard);        // GET /admin/stats/dashboard?days=30
r.get('/revenue',      C.getRevenueSeries);   // GET /admin/stats/revenue?days=30
r.get('/users',        C.getUsersSeries);      // GET /admin/stats/users?days=30
r.get('/top-users',    C.getTopUsers);         // GET /admin/stats/top-users
r.get('/signups',      C.getSignups);          // GET /admin/stats/signups?days=14  (dashboard)
r.get('/pronostics',   C.getPronosticsStats);  // GET /admin/stats/pronostics?days=30
r.get('/monthly',      C.getMonthly);          // GET /admin/stats/monthly          (12 mois)
r.get('/leagues',      C.getLeaguePerformance);// GET /admin/stats/leagues?days=30
r.get('/online',       C.getOnlineCount);      // GET /admin/stats/online           (non caché)

export default r;
