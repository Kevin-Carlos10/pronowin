import { Router } from 'express';
import { authMiddleware, optionalAuthMiddleware, premiumMiddleware }  from '../middleware/auth.middleware';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/pronostics.controller';

const r = Router();

// ── Public (sans auth) ────────────────────────────────────────────────────────
r.get ('/daily',     C.getDailyFree);

// ── Navigation ouverte aux invités (contenu premium filtré côté service) ──────
r.get ('/',              optionalAuthMiddleware, C.getPronostics);
r.get ('/leagues',       optionalAuthMiddleware, C.getLeagues);
r.get ('/counts-by-day', optionalAuthMiddleware, C.getCountsByDay);
r.get ('/day-summary',   optionalAuthMiddleware, C.getDaySummary);

// ── Utilisateur connecté ───────────────────────────────────────────────────────
r.get ('/stats',       authMiddleware, C.getPublicStats);
// Bilan global des pronostics publiés — aucune donnée propre à l'utilisateur
// (getPerformance n'utilise pas req.user). C'est l'argument de confiance de
// l'app : il doit être visible avant de créer un compte.
r.get ('/performance', optionalAuthMiddleware, C.getPerformance);
// Avant `/:id` : sans cela Express prendrait « top-scorers » pour un identifiant.
r.get ('/top-scorers', optionalAuthMiddleware, C.getTopScorers);
r.get ('/for-you',     authMiddleware, premiumMiddleware, C.getForYou);
r.get ('/history',   authMiddleware, C.getHistory);
// ── Détail d'un match : ouvert aux invités ────────────────────────────────────
//
// Ces six endpoints ne servent que de la donnée API-Football (score, stats,
// compositions, blessures, classements, confrontations). Ce n'est pas le
// produit vendu — le produit, c'est le pronostic, l'analyse et les
// commentaires, qui restent filtrés. Les fermer n'empêchait personne de payer,
// ça empêchait juste d'entrer.
r.get ('/:id/score',       optionalAuthMiddleware, C.getPronosticScore);
r.get ('/:id/h2h',         optionalAuthMiddleware, C.getH2H);
r.get ('/:id/lineups',     optionalAuthMiddleware, C.getLineups);
r.get ('/:id/injuries',    optionalAuthMiddleware, C.getInjuries);
r.get ('/:id/standings',   optionalAuthMiddleware, C.getStandings);
r.get ('/:id/match-stats', optionalAuthMiddleware, C.getMatchStats);
r.get ('/:id/insights',    optionalAuthMiddleware, C.getMatchInsights);
r.get ('/:id/live-odds',   optionalAuthMiddleware, C.getLiveOdds);
r.get ('/:id/ratings',     optionalAuthMiddleware, C.getPlayerRatings);

// L'analyse statistique reste le cœur de l'offre payante.
r.get ('/:id/ai-analyze',  authMiddleware, premiumMiddleware, C.getAiAnalysis);

// Le détail est accessible à tous ; le contenu premium est filtré, pas bloqué.
r.get ('/:id',             optionalAuthMiddleware, C.getPronosticDetail);

// ── Admin ─────────────────────────────────────────────────────────────────────
r.get ('/admin/leagues',                   adminMiddleware, C.getLeagueVisibility);
// Chemin frère et non enfant de `/admin/leagues/:code` : un code de
// compétition ne peut donc jamais être confondu avec l'action groupée.
r.post('/admin/leagues-bulk',              adminMiddleware, C.setLeagueVisibilityBulk);
r.post('/admin/leagues/:code',             adminMiddleware, C.setLeagueVisibility);
r.get ('/admin/upcoming',                  adminMiddleware, C.fetchUpcoming);
r.get ('/admin/stats',                     adminMiddleware, C.getAdminStats);
r.get ('/admin/match/:matchId/odds',       adminMiddleware, C.getMatchOdds);
r.get ('/admin/match/:matchId/prediction', adminMiddleware, C.getAdminPrediction);
r.get ('/admin/match/:matchId',            adminMiddleware, C.getMatchFromDB);
r.post('/admin/pronostic',                 adminMiddleware, C.upsertPronostic);
r.patch('/admin/pronostic/:id/publish',    adminMiddleware, C.togglePublish);
r.patch('/admin/pronostic/:id/result',     adminMiddleware, C.setPronosticResult);
r.patch('/admin/pronostic/:id/set-daily',  adminMiddleware, C.setDailyFree);
r.post ('/admin/sync-scores',              adminMiddleware, C.syncScores);

export default r;
