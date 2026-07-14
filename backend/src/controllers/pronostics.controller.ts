import { Request, Response }  from 'express';
import { prisma } from '../lib/prisma';
import { AuthRequest }  from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { PronosticsService } from '../services/pronostics.service';
import { FootballDataService } from '../services/football_data.service';
import { NotificationService } from '../services/notification.service';
import { OddsService } from '../services/odds.service';
import { cache, CACHE_KEYS, CACHE_TTL } from '../services/cache.service';
import { analyzePronostic } from '../services/ai_prediction.service';
import { settleBets }      from '../services/bankroll.service';
import { apiFootballService } from '../services/api_football.service';

const svc      = new PronosticsService();
const fdSvc    = new FootballDataService();
const notifSvc = new NotificationService();
const oddsSvc  = new OddsService();

// ── PUBLIC / UTILISATEUR ──────────────────────────────────────────────────────
export const getPronostics = async (req: AuthRequest, res: Response) => {
  try {
    const includeAll = req.query.include_all === 'true';
    const cursor     = req.query.cursor as string | undefined;
    const limit      = Math.min(parseInt((req.query.limit as string) ?? '20') || 20, 50);

    const params = {
      userId:      req.userId!,
      dateFilter:  req.query.date_filter as string,
      sport:       req.query.sport as string,
      leagueCode:  req.query.league_code as string,
      cursor,
      limit,
    };

    // Pas de cache sur les requêtes avec cursor (résultats dépendent du curseur)
    const cacheKey = cursor ? null : CACHE_KEYS.pronostics(
      `${includeAll}:${params.dateFilter ?? ''}:${params.sport ?? ''}:${params.leagueCode ?? ''}:${limit}`
    );
    if (cacheKey) {
      const cached = cache.get<any>(cacheKey);
      if (cached) { res.json(cached); return; }
    }

    const result = includeAll
      ? await svc.getAllMatches(params)
      : await svc.getPublishedPronostics(params);

    if (cacheKey) cache.set(cacheKey, result, CACHE_TTL.pronostics);
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getLeagues = async (_req: AuthRequest, res: Response) => {
  try { res.json(await fdSvc.getCompetitions()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getPronosticDetail = async (req: AuthRequest, res: Response) => {
  try {
    const [prono, user] = await Promise.all([
      prisma.pronostic.findUnique({
        where:   { id: req.params.id },
        include: { match: true, analyst: { select: { name: true } } },
      }),
      prisma.user.findUnique({
        where:  { id: req.userId! },
        select: { subscriptionPlan: true, subscriptionExpiresAt: true },
      }),
    ]);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const userIsPremium = user?.subscriptionPlan === 'premium' &&
      (!user.subscriptionExpiresAt || user.subscriptionExpiresAt > new Date());

    // Bloquer l'accès complet au pronostic premium pour les non-premium
    if (prono.isPremium && !userIsPremium) {
      res.status(403).json({ message: 'Accès réservé aux membres Premium.', code: 'PREMIUM_REQUIRED' });
      return;
    }

    res.json({
      id:               prono.id,
      league:           prono.match.league,
      league_country:   prono.match.leagueCode,
      home_team:        prono.match.homeTeam,
      away_team:        prono.match.awayTeam,
      home_team_logo:   prono.match.homeTeamLogo,
      away_team_logo:   prono.match.awayTeamLogo,
      match_date:       prono.match.matchDate,
      status:           prono.match.status.toLowerCase(),
      home_score:       prono.match.homeScore,
      away_score:       prono.match.awayScore,
      prediction_type:  prono.predictionType,
      prediction_label: prono.predictionLabel,
      odds_home:        prono.oddsHome,
      odds_draw:        prono.oddsDraw,
      odds_away:        prono.oddsAway,
      odds_recommended: prono.oddsRecommended,
      confidence_score: prono.confidenceScore,
      is_premium:       prono.isPremium,
      analyst_note:     prono.analystNote,
      analyst_name:     prono.analyst.name,
      home_form_points: prono.match.homeFormPoints,
      away_form_points: prono.match.awayFormPoints,
      ai_probability:   prono.aiProbability,
      ai_explanation:   prono.aiExplanation,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /pronostics/:id/score — score + statut uniquement (polling live léger) */
export const getPronosticScore = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await prisma.pronostic.findUnique({
      where:  { id: req.params.id },
      select: { match: { select: { homeScore: true, awayScore: true, status: true } } },
    });
    if (!prono) { res.status(404).json({ message: 'Introuvable.' }); return; }
    res.json({
      homeScore: prono.match.homeScore,
      awayScore: prono.match.awayScore,
      status:    prono.match.status,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const fetchUpcoming = async (req: AdminRequest, res: Response) => {
  try {
    // Vérifier que la clé API est configurée
    if (!process.env.FOOTBALL_DATA_API_KEY) {
      res.status(400).json({
        message: 'FOOTBALL_DATA_API_KEY manquante dans .env',
        help: 'Inscrivez-vous sur https://www.football-data.org/client/register',
      });
      return;
    }

    const competition = req.query.competition as string | undefined;
    const data = await svc.fetchUpcomingMatchesForAdmin(competition);
    res.json(data);

  } catch (e: any) {
    // Erreur explicite Football-Data (403, email non vérifié, etc.)
    res.status(500).json({
      message: e.message,
      help: e.message.includes('email non vérifié')
        ? 'Vérifiez votre email sur football-data.org puis réessayez.'
        : 'Vérifiez votre clé API dans backend/.env',
    });
  }
};

export const upsertPronostic = async (req: AdminRequest, res: Response) => {
  try {
    const b       = req.body;
    const publish = b.publish === true || b.publish === 'true';
    const p = await svc.upsertPronostic({
      matchId:         b.match_id,
      analystId:       req.adminId!,
      predictionType:  b.prediction_type,
      predictionLabel: b.prediction_label,
      oddsHome:        parseFloat(b.odds_home),
      oddsDraw:        parseFloat(b.odds_draw),
      oddsAway:        parseFloat(b.odds_away),
      oddsRecommended: parseFloat(b.odds_recommended),
      confidenceScore: parseInt(b.confidence_score),
      analystNote:     b.analyst_note,
      isPremium:       b.is_premium === true || b.is_premium === 'true',
      publish,
    });
    // Notifier dès la création si déjà publié
    if (publish) {
      const match = await prisma.match.findUnique({ where: { id: b.match_id } });
      if (match) {
        notifSvc.notifyPronosticPublished({
          homeTeam:        match.homeTeam,
          awayTeam:        match.awayTeam,
          pronosticId:     p.id,
          predictionLabel: b.prediction_label,
          isPremium:       b.is_premium === true || b.is_premium === 'true',
          matchStatus:     match.status,
        }).catch(() => {});
      }
    }
    cache.del('pronostics:');
    cache.del(CACHE_KEYS.publicStats);
    res.status(201).json(p);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const togglePublish = async (req: AdminRequest, res: Response) => {
  try {
    const publish = req.body.publish === true || req.body.publish === 'true';
    const p = await svc.togglePublish(req.params.id, publish);
    // Notifier seulement à la publication (pas à la dépublication)
    if (publish) {
      const prono = await prisma.pronostic.findUnique({
        where:   { id: req.params.id },
        include: { match: true },
      });
      if (prono) {
        notifSvc.notifyPronosticPublished({
          homeTeam:        prono.match.homeTeam,
          awayTeam:        prono.match.awayTeam,
          pronosticId:     prono.id,
          predictionLabel: prono.predictionLabel,
          isPremium:       prono.isPremium,
          matchStatus:     prono.match.status,
        }).catch(() => {});
      }
    }
    // Invalider le cache des pronostics après publication/dépublication
    cache.del('pronostics:');
    cache.del(CACHE_KEYS.publicStats);
    res.json(p);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

/** PATCH /pronostics/admin/pronostic/:id/result — forcer WIN/LOSS/null manuellement */
export const setPronosticResult = async (req: AdminRequest, res: Response) => {
  try {
    const { result } = req.body; // 'WIN' | 'LOSS' | null
    if (result !== 'WIN' && result !== 'LOSS' && result !== null) {
      res.status(400).json({ message: 'result doit être WIN, LOSS ou null.' }); return;
    }
    const p = await prisma.pronostic.update({
      where: { id: req.params.id },
      data:  { result },
    });
    cache.del('pronostics:');
    cache.del(CACHE_KEYS.publicStats);
    cache.del(CACHE_KEYS.adminStats);
    // Régler automatiquement les paris bankroll liés à ce pronostic
    if (result === 'WIN' || result === 'LOSS') {
      settleBets(req.params.id, result).catch(() => {});
    }
    res.json(p);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

// ── SYNC SCORES (admin ou cron interne) ───────────────────────────────────────
export const syncScores = async (_req: AdminRequest, res: Response) => {
  try {
    const result = await svc.syncMatchScores();
    // Invalider le cache après sync (scores peuvent avoir changé)
    cache.del('pronostics:');
    cache.del(CACHE_KEYS.publicStats);
    cache.del(CACHE_KEYS.adminStats);
    res.json({ message: 'Sync terminée.', ...result });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /pronostics/history?days=30 — résultats des 30 derniers jours */
export const getHistory = async (req: AuthRequest, res: Response) => {
  try {
    const days  = Math.min(parseInt((req.query.days as string) ?? '30') || 30, 90);
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const pronostics = await prisma.pronostic.findMany({
      where: {
        isPublished: true,
        result:      { not: null },
        match:       { status: 'FINISHED', matchDate: { gte: since } },
      },
      include: {
        match: {
          select: {
            id: true, league: true, leagueCode: true,
            homeTeam: true, awayTeam: true,
            homeTeamLogo: true, awayTeamLogo: true,
            homeScore: true, awayScore: true, matchDate: true,
          },
        },
      },
      orderBy: { match: { matchDate: 'desc' } },
    });

    res.json(pronostics.map(p => ({
      id:              p.id,
      predictionLabel: p.predictionLabel,
      predictionType:  p.predictionType,
      oddsRecommended: p.oddsRecommended,
      confidenceScore: p.confidenceScore,
      isPremium:       p.isPremium,
      result:          p.result,   // 'WIN' | 'LOSS'
      match:           p.match,
    })));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getPublicStats = async (_req: Request, res: Response) => {
  try {
    const cached = cache.get<any>(CACHE_KEYS.publicStats);
    if (cached) { res.json(cached); return; }
    const data = await svc.getPublicStats();
    cache.set(CACHE_KEYS.publicStats, data, CACHE_TTL.stats);
    res.json(data);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getAdminStats = async (_req: AdminRequest, res: Response) => {
  try {
    const cached = cache.get<any>(CACHE_KEYS.adminStats);
    if (cached) { res.json(cached); return; }
    const data = await svc.getAdminStats();
    cache.set(CACHE_KEYS.adminStats, data, CACHE_TTL.stats);
    res.json(data);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /admin/match/:matchId/odds — cotes live depuis The Odds API */
export const getMatchOdds = async (req: AdminRequest, res: Response) => {
  try {
    const match = await prisma.match.findUnique({ where: { id: req.params.matchId } });
    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }
    const odds = await oddsSvc.getOddsForMatch(match.homeTeam, match.awayTeam, match.league);
    res.json(odds);
  } catch (e: any) { res.status(422).json({ message: e.message }); }
};

// H2H — historique des confrontations directes
// Cherche un pronostic par son ID OU par le matchId — car la liste renvoie des match UUIDs
async function findPronoByIdOrMatchId(id: string) {
  const byProno = await prisma.pronostic.findUnique({ where: { id }, include: { match: true } });
  if (byProno) return byProno;
  return prisma.pronostic.findUnique({ where: { matchId: id }, include: { match: true } });
}

export const getH2H = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const externalId = prono.match.externalId;
    if (!externalId) { res.status(404).json({ message: 'ID externe manquant.' }); return; }

    const h2h = await fdSvc.getH2H(externalId, 10);
    if (!h2h) { res.status(503).json({ message: 'Données H2H indisponibles.' }); return; }

    // Filtrer seulement les matchs terminés + formater
    const finished = h2h.matches
      .filter(m => m.status === 'FINISHED' && m.score.fullTime.home !== null)
      .slice(0, 8)
      .map(m => ({
        date:      m.utcDate,
        home_team: m.homeTeam.shortName || m.homeTeam.name,
        away_team: m.awayTeam.shortName || m.awayTeam.name,
        home_score: m.score.fullTime.home,
        away_score: m.score.fullTime.away,
        winner:     m.score.winner, // 'HOME_TEAM' | 'AWAY_TEAM' | 'DRAW'
        league:     m.competition.name,
      }));

    res.json({
      aggregates:  h2h.aggregates,
      matches:     finished,
      home_team:   prono.match.homeTeam,
      away_team:   prono.match.awayTeam,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// Analyse IA d'un pronostic (ML probability + explication Claude)
export const getAiAnalysis = async (req: AuthRequest, res: Response) => {
  try {
    const result = await analyzePronostic(req.params.id);
    res.json(result);
  } catch (e: any) {
    res.status(e.message === 'Pronostic not found' ? 404 : 500).json({ message: e.message });
  }
};

// Récupérer un match depuis la base de données (pour le formulaire d'édition)
export const getMatchFromDB = async (req: AdminRequest, res: Response) => {
  try {
    const match = await prisma.match.findUnique({
      where:   { id: req.params.matchId },
      include: { pronostic: true },
    });
    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }
    res.json({
      ...match,
      has_pronostic: !!match.pronostic,
      is_published:  match.pronostic?.isPublished ?? false,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// GET /pronostics/:id/match-stats — stats détaillées d'un match terminé via API-Football
export const getMatchStats = async (req: AuthRequest, res: Response) => {
  try {
    // Cherche d'abord par pronostic ID, sinon directement par match ID
    let match: any = null;

    const pronostic = await prisma.pronostic.findUnique({
      where:   { id: req.params.id },
      include: { match: true },
    });
    if (pronostic) {
      match = pronostic.match;
    } else {
      match = await prisma.match.findUnique({ where: { id: req.params.id } });
    }

    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }
    if (match.status !== 'FINISHED') {
      res.status(400).json({ message: 'Les stats ne sont disponibles que pour les matchs terminés.' });
      return;
    }

    const matchDate = new Date(match.matchDate).toISOString().split('T')[0];
    const stats = await apiFootballService.getMatchStats(
      match.leagueCode ?? '',
      match.homeTeam,
      match.awayTeam,
      matchDate,
    );

    if (!stats) { res.status(404).json({ message: 'Stats non disponibles pour ce match.' }); return; }
    res.json(stats);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
