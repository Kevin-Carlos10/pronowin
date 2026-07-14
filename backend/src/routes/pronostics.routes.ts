import { Router } from 'express';
import { authMiddleware, premiumMiddleware }  from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/pronostics.controller';

const r = Router();

// ── Utilisateur ───────────────────────────────────────────────────────────────
r.get ('/stats',      authMiddleware, C.getPublicStats);
r.get ('/history',   authMiddleware, C.getHistory);
r.get ('/',          authMiddleware, C.getPronostics);
r.get ('/leagues',   authMiddleware, C.getLeagues);
r.get ('/:id/score',       authMiddleware, C.getPronosticScore);
r.get ('/:id/h2h',         authMiddleware, C.getH2H);
// Analyses IA et stats détaillées = réservées aux membres premium
r.get ('/:id/ai-analyze',  authMiddleware, premiumMiddleware, C.getAiAnalysis);
r.get ('/:id/match-stats', authMiddleware, C.getMatchStats);
// Le détail est accessible à tous, mais le contenu premium est filtré dans le controller
r.get ('/:id',             authMiddleware, C.getPronosticDetail);

// ── Admin ─────────────────────────────────────────────────────────────────────
r.get ('/admin/upcoming',                  adminMiddleware, C.fetchUpcoming);
r.get ('/admin/stats',                     adminMiddleware, C.getAdminStats);
r.get ('/admin/match/:matchId/odds',       adminMiddleware, C.getMatchOdds);
r.get ('/admin/match/:matchId',            adminMiddleware, C.getMatchFromDB);
r.post('/admin/pronostic',                 adminMiddleware, C.upsertPronostic);
r.patch('/admin/pronostic/:id/publish',    adminMiddleware, C.togglePublish);
r.patch('/admin/pronostic/:id/result',     adminMiddleware, C.setPronosticResult);
r.post ('/admin/sync-scores',              adminMiddleware, C.syncScores);

export default r;
