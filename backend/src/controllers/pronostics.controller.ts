import { Request, Response }  from 'express';
import { prisma } from '../lib/prisma';
import { AuthRequest }  from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { PronosticsService } from '../services/pronostics.service';
import { FootballDataService } from '../services/football_data.service';
import { NotificationService } from '../services/notification.service';
import { cache, CACHE_KEYS, CACHE_TTL } from '../services/cache.service';
import { analyzePronostic } from '../services/ai_prediction.service';
import { buildUserProfile, getPersonalizedPronostics } from '../services/personalized_ai.service';
import { settleBets }      from '../services/bankroll.service';
import { apiFootballService, apiFootballInsights } from '../services/api_football.service';
import { LEAGUE_INFO } from '../services/api_football.service';

const svc      = new PronosticsService();
const fdSvc    = new FootballDataService();
const notifSvc = new NotificationService();

/**
 * Statut premium effectif d'un utilisateur.
 *
 * Extrait ici parce que la clé de cache des listes en dépend : la réponse
 * n'est plus la même selon les droits de l'appelant.
 */
async function isUserPremium(userId: string): Promise<boolean> {
  const u = await prisma.user.findUnique({
    where: { id: userId }, select: { subscriptionPlan: true, subscriptionExpiresAt: true },
  });
  return u?.subscriptionPlan === 'premium'
    && (u.subscriptionExpiresAt ? u.subscriptionExpiresAt > new Date() : false);
}

// ── PUBLIC / UTILISATEUR ──────────────────────────────────────────────────────
/**
 * Décalage UTC du client, en minutes (`tz_offset`), tel que l'envoie le mobile.
 *
 * Le serveur découpait les journées dans son propre fuseau, le mobile dans
 * celui de l'appareil : un match de fin de soirée tombait alors d'un côté pour
 * l'un et de l'autre pour l'autre, ce qui faisait diverger le compteur du
 * bandeau et le nombre de cartes affichées.
 *
 * Borné à ±14 h, l'amplitude réelle des fuseaux : au-delà, la valeur est
 * ignorée plutôt que d'ouvrir une fenêtre de dates arbitraire depuis l'URL.
 */
const lireDecalage = (req: AuthRequest): number | undefined => {
  const brut = parseInt(req.query.tz_offset as string, 10);
  if (!Number.isFinite(brut) || Math.abs(brut) > 14 * 60) return undefined;
  return brut;
};

export const getPronostics = async (req: AuthRequest, res: Response) => {
  try {
    const includeAll = req.query.include_all === 'true';
    const cursor     = req.query.cursor as string | undefined;
    const limit      = Math.min(parseInt((req.query.limit as string) ?? '20') || 20, 50);

    const params = {
      userId:        req.userId,
      dateFilter:    req.query.date_filter as string,
      tzOffsetMin:   lireDecalage(req),
      sport:         req.query.sport as string,
      leagueCode:    req.query.league_code as string,
      status:        req.query.status as string,
      hasPronostic:  req.query.has_pronostic === 'true' ? true : undefined,
      cursor,
      limit,
    };

    // Le palier fait partie de la clé de cache : depuis que le serveur masque
    // le pronostic premium, la réponse dépend des droits de l'appelant. Sans
    // cette dimension, la première réponse mise en cache était resservie à
    // tout le monde — un invité pouvait recevoir la version complète d'un
    // abonné, et inversement un abonné voyait son propre pronostic verrouillé.
    const tier = !req.userId ? 'guest' : (await isUserPremium(req.userId) ? 'premium' : 'free');

    // Pas de cache sur les requêtes avec cursor (résultats dépendent du curseur)
    const cacheKey = cursor ? null : CACHE_KEYS.pronostics(
      `${tier}:${includeAll}:${params.dateFilter ?? ''}:${params.sport ?? ''}:${params.leagueCode ?? ''}:${params.status ?? ''}:${params.hasPronostic ?? ''}:${limit}`
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

// GET /pronostics/counts-by-day — comptage par jour pour le sélecteur de dates mobile
export const getCountsByDay = async (_req: AuthRequest, res: Response) => {
  try {
    const cacheKey = CACHE_KEYS.dayCounts;
    const cached = cache.get<Record<string, number>>(cacheKey);
    if (cached) { res.json(cached); return; }

    const counts = await svc.getMatchCountsByDay();
    cache.set(cacheKey, counts, CACHE_TTL.dayCounts);
    res.json(counts);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// GET /pronostics/day-summary — totaux réels (matchs / avec prono / live) pour un jour,
// indépendants de la pagination de la liste (qui ne couvre jamais tout le jour)
export const getDaySummary = async (req: AuthRequest, res: Response) => {
  try {
    const dateFilter = (req.query.date_filter as string) ?? '';
    const decalage   = lireDecalage(req);
    // Le décalage entre dans la clé : deux utilisateurs de fuseaux différents
    // n'ont pas le même « aujourd'hui », et se serviraient l'un à l'autre une
    // réponse fausse.
    const cacheKey = CACHE_KEYS.daySummary(`${dateFilter}:${decalage ?? ''}`);
    const cached = cache.get<any>(cacheKey);
    if (cached) { res.json(cached); return; }

    const summary = await svc.getDaySummary(dateFilter, decalage);
    cache.set(cacheKey, summary, CACHE_TTL.daySummary);
    res.json(summary);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getPerformance = async (req: AuthRequest, res: Response) => {
  try {
    const days   = Math.min(parseInt((req.query.days as string) ?? '30') || 30, 90);
    const since  = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const STAKE  = 1000; // mise fictive en FCFA

    const pronostics = await prisma.pronostic.findMany({
      where: {
        isPublished: true,
        result:      { not: null },
        match:       { status: 'FINISHED', matchDate: { gte: since } },
      },
      include: { match: { select: { league: true, matchDate: true } } },
      orderBy: { match: { matchDate: 'asc' } },
    });

    // Net simulé d'un pronostic pour la mise fictive STAKE — 0 pour un PUSH
    // (marché remboursé : ni gain ni perte), symétrique à settleBets().
    const _net = (p: (typeof pronostics)[number]): number =>
      p.result === 'WIN'  ? STAKE * p.oddsRecommended - STAKE
      : p.result === 'PUSH' ? 0
      : -STAKE;

    const total    = pronostics.length;
    const decisive = pronostics.filter(p => p.result !== 'PUSH');
    const wins     = decisive.filter(p => p.result === 'WIN').length;
    const losses   = decisive.filter(p => p.result === 'LOSS').length;
    // Le taux de réussite et le ROI excluent les remboursés — ni victoire ni
    // défaite, la mise fictive n'a jamais été réellement "à risque".
    const winRate  = decisive.length > 0 ? Math.round((wins / decisive.length) * 100) : 0;

    const netGain      = pronostics.reduce((sum, p) => sum + _net(p), 0);
    const totalStaked  = decisive.length * STAKE;
    const roi = totalStaked > 0 ? Math.round((netGain / totalStaked) * 100 * 10) / 10 : 0;

    // Meilleure série (un PUSH n'interrompt pas une série de victoires, il est ignoré)
    let bestStreak = 0, currentStreak = 0;
    for (const p of pronostics) {
      if (p.result === 'WIN') { currentStreak++; bestStreak = Math.max(bestStreak, currentStreak); }
      else if (p.result === 'LOSS') currentStreak = 0;
    }

    // Ligue la plus rentable
    const byLeague: Record<string, { wins: number; total: number; net: number }> = {};
    for (const p of pronostics) {
      const l = p.match.league;
      if (!byLeague[l]) byLeague[l] = { wins: 0, total: 0, net: 0 };
      byLeague[l].total++;
      if (p.result === 'WIN') byLeague[l].wins++;
      byLeague[l].net += _net(p);
    }
    const bestLeague = Object.entries(byLeague)
      .sort((a, b) => b[1].net - a[1].net)
      .map(([league, s]) => ({
        league,
        wins:     s.wins,
        total:    s.total,
        win_rate: s.total > 0 ? Math.round(s.wins / s.total * 100) : 0,
        net_gain: Math.round(s.net),
      }));

    // Évolution du solde simulé jour par jour
    let runningBalance = 0;
    const balanceHistory = pronostics.map(p => {
      runningBalance += _net(p);
      return {
        date:    p.match.matchDate,
        balance: Math.round(runningBalance),
        result:  p.result,
      };
    });

    // Stats par semaine (7 derniers jours vs 7 précédents)
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const thisWeek = pronostics.filter(p => p.match.matchDate >= weekAgo);
    const thisWeekDecisive = thisWeek.filter(p => p.result !== 'PUSH');
    const weekWins = thisWeekDecisive.filter(p => p.result === 'WIN').length;

    res.json({
      period_days:      days,
      stake_reference:  STAKE,
      total_pronostics: total,
      wins,
      losses,
      pushes:           total - decisive.length,
      win_rate:         winRate,
      roi,
      simulated_net:    Math.round(netGain),
      best_streak:      bestStreak,
      best_leagues:     bestLeague.slice(0, 5),
      balance_history:  balanceHistory,
      this_week: {
        total:    thisWeek.length,
        wins:     weekWins,
        win_rate: thisWeekDecisive.length > 0 ? Math.round(weekWins / thisWeekDecisive.length * 100) : 0,
      },
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getDailyFree = async (_req: Request, res: Response) => {
  try {
    const prono = await svc.getDailyFreePronostic();
    if (!prono) { res.status(404).json({ message: 'Aucun prono du jour disponible.' }); return; }
    res.json(prono);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const setDailyFree = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.setDailyFreePronostic(req.params.id);
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// GET /pronostics/for-you — recommandations IA personnalisées
export const getForYou = async (req: AuthRequest, res: Response) => {
  try {
    const userId  = req.userId!;
    const limit   = Math.min(parseInt((req.query.limit as string) ?? '10') || 10, 20);

    const profile = await buildUserProfile(userId);
    const recs    = await getPersonalizedPronostics(userId, profile, limit);

    res.json({
      profile: {
        total_bets:     profile.totalBets,
        win_rate:       profile.winRate,
        top_leagues:    profile.topLeagues,
        top_bet_types:  profile.topBetTypes,
        odds_sweet_min: profile.oddsSweetMin,
        odds_sweet_max: profile.oddsSweetMax,
        is_new_user:    profile.isEmpty,
      },
      recommendations: recs,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getLeagues = async (_req: AuthRequest, res: Response) => {
  try { res.json(await apiFootballService.getCompetitions()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getPronosticDetail = async (req: AuthRequest, res: Response) => {
  try {
    // Accepte un id de pronostic OU de match — même raison que les autres
    // endpoints du détail match (cf. findPronoByIdOrMatchId).
    const [prono, user] = await Promise.all([
      prisma.pronostic.findFirst({
        where:   { OR: [{ id: req.params.id }, { matchId: req.params.id }] },
        include: { match: true, analyst: { select: { name: true } } },
      }),
      // Invité : pas d'userId. `findUnique` avec un id undefined lève une
      // erreur Prisma, d'où la garde.
      req.userId
        ? prisma.user.findUnique({
            where:  { id: req.userId },
            select: { subscriptionPlan: true, subscriptionExpiresAt: true },
          })
        : Promise.resolve(null),
    ]);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const userIsPremium = user?.subscriptionPlan === 'premium' &&
      (!user.subscriptionExpiresAt || user.subscriptionExpiresAt > new Date());

    // Le pronostic premium est FILTRÉ, plus bloqué.
    //
    // Un 403 renvoyait une page d'erreur : ni compositions, ni classement, ni
    // face-à-face — alors que rien de tout cela n'est payant. L'utilisateur
    // gratuit voyait un mur au lieu d'une raison de s'abonner, et l'invité
    // n'entrait même pas. On sert désormais toute la donnée du match, et on
    // retire les seuls champs qui constituent l'offre payante.
    const locked = prono.isPremium && !userIsPremium;

    res.json({
      // `locked` dit au client d'afficher la carte pronostic verrouillée
      // plutôt que de croire à une absence de données.
      locked,
      requires_auth: !req.userId,
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
      is_premium:       prono.isPremium,
      // Données du match — jamais payantes, elles viennent d'API-Football.
      home_form_points: prono.match.homeFormPoints,
      away_form_points: prono.match.awayFormPoints,
      odds_home:        prono.oddsHome,
      odds_draw:        prono.oddsDraw,
      odds_away:        prono.oddsAway,
      // Le pronostic lui-même : c'est ce qui se vend.
      prediction_type:  locked ? null : prono.predictionType,
      prediction_label: locked ? null : prono.predictionLabel,
      odds_recommended: locked ? null : prono.oddsRecommended,
      confidence_score: locked ? null : prono.confidenceScore,
      analyst_note:     locked ? null : prono.analystNote,
      analyst_name:     locked ? null : prono.analyst.name,
      ai_probability:   locked ? null : prono.aiProbability,
      ai_explanation:   locked ? null : prono.aiExplanation,
      // Le résultat reste visible : il prouve la fiabilité passée et c'est
      // précisément l'argument de vente.
      result:           prono.result,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /pronostics/:id/score — score + statut uniquement (polling live léger) */
export const getPronosticScore = async (req: AuthRequest, res: Response) => {
  try {
    // Accepte un id de pronostic OU de match : la page détail relaie celui que
    // lui a transmis l'écran d'origine (cf. findPronoByIdOrMatchId). Sans ça,
    // le score live ne se rafraîchissait jamais depuis l'onglet Pronostics.
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Introuvable.' }); return; }
    res.json({
      homeScore: prono.match.homeScore,
      awayScore: prono.match.awayScore,
      status:    prono.match.status,
      // Minute de jeu — l'écran de direct affichait un score sans jamais dire
      // où on en était dans le match.
      elapsed:   prono.match.elapsedMinutes,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// ── ADMIN ─────────────────────────────────────────────────────────────────────
export const fetchUpcoming = async (req: AdminRequest, res: Response) => {
  try {
    const competition = req.query.competition as string | undefined;
    const search      = req.query.search as string | undefined;
    const date        = req.query.date as string | undefined;
    const mine        = req.query.mine === '1';
    const live        = req.query.live === '1';

    // "Mes pronostics", une date précise et "Match en direct" se lisent
    // directement en base — pas besoin de la clé API.
    if (!date && !mine && !live && !process.env.API_FOOTBALL_KEY) {
      res.status(400).json({
        message: 'API_FOOTBALL_KEY manquante dans .env',
        help: 'Inscrivez-vous sur https://www.api-football.com',
      });
      return;
    }

    // La page de liste demande un plafond, l'export CSV et la recherche
    // globale n'en passent aucun : les plafonner tronquerait un export sans
    // rien dire. Le total avant troncature part en en-tête, le corps reste un
    // tableau — trois appelants s'appuient sur cette forme.
    const brut   = req.query.limit as string | undefined;
    const limite = brut && /^\d+$/.test(brut) ? Math.min(parseInt(brut, 10), 2000) : undefined;
    const { items, total } = await svc.fetchUpcomingMatchesForAdmin(
      competition, search, date, mine, live, limite);
    res.setHeader('X-Total-Count', String(total));
    const data = items;
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
      marketName:      b.market_name,
      marketValue:     b.market_value,
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

/** GET /pronostics/admin/leagues — liste blanche des compétitions visibles dans le flux public */
export const getLeagueVisibility = async (_req: AdminRequest, res: Response) => {
  try {
    const leagues = await svc.listLeagueVisibility();
    res.json(leagues);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** POST /pronostics/admin/leagues/:code — active/désactive une compétition */
export const setLeagueVisibility = async (req: AdminRequest, res: Response) => {
  try {
    const { league, visible } = req.body;
    if (typeof league !== 'string' || !league.trim()) {
      res.status(400).json({ message: 'league requis.' }); return;
    }
    const isVisible = visible === true || visible === 'true';
    const row = await svc.setLeagueVisibility(req.params.code, league, isVisible);
    // Le flux public ("Tous les matchs") lit ce filtre à chaque requête —
    // invalider le cache (préfixe "pronostics:", couvre aussi day-counts/day-summary)
    // pour que le changement soit immédiat.
    cache.del('pronostics:');
    res.json(row);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

/** POST /pronostics/admin/leagues-bulk — bascule un lot de compétitions d'un coup */
export const setLeagueVisibilityBulk = async (req: AdminRequest, res: Response) => {
  try {
    const { leagues, visible } = req.body;
    if (!Array.isArray(leagues) || leagues.length === 0) {
      res.status(400).json({ message: 'leagues doit être un tableau non vide.' }); return;
    }
    const isVisible = visible === true || visible === 'true';
    const result = await svc.setLeagueVisibilityBulk(leagues, isVisible);
    cache.del('pronostics:');
    res.json(result);
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

/** PATCH /pronostics/admin/pronostic/:id/result — forcer WIN/LOSS/null manuellement */
export const setPronosticResult = async (req: AdminRequest, res: Response) => {
  try {
    const { result } = req.body; // 'WIN' | 'LOSS' | 'PUSH' | null
    if (result !== 'WIN' && result !== 'LOSS' && result !== 'PUSH' && result !== null) {
      res.status(400).json({ message: 'result doit être WIN, LOSS, PUSH ou null.' }); return;
    }
    const p = await prisma.pronostic.update({
      where: { id: req.params.id },
      data:  { result },
    });
    cache.del('pronostics:');
    cache.del(CACHE_KEYS.publicStats);
    cache.del(CACHE_KEYS.adminStats);
    // Régler automatiquement les paris bankroll liés à ce pronostic
    if (result === 'WIN' || result === 'LOSS' || result === 'PUSH') {
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

/** GET /admin/match/:matchId/odds — cotes 1xBet live via API-Football */
export const getMatchOdds = async (req: AdminRequest, res: Response) => {
  try {
    const match = await prisma.match.findUnique({ where: { id: req.params.matchId } });
    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }
    const dateStr = match.matchDate.toISOString().slice(0, 10);
    const fixtureId = match.source === 'API_FOOTBALL' ? match.externalId : undefined;
    const odds = await apiFootballService.getOdds1xBet(match.homeTeam, match.awayTeam, dateStr, fixtureId);
    if (!odds) { res.status(422).json({ message: 'Cotes indisponibles pour ce match.' }); return; }
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


// ─── Enrichissements API-Football (plan Pro) ─────────────────────────────────
//
// Tous ces endpoints sont *optionnels* : ils enrichissent un match, ils ne le
// définissent pas. Une panne côté fournisseur doit se traduire par un 503 que
// le mobile masque, jamais par une page de match cassée.

/** Un match n'a d'enrichissement que s'il vient d'API-Football avec un id. */
function fixtureIdDe(match: { source: string; externalId: number | null }): number | null {
  return match.source === 'API_FOOTBALL' && match.externalId ? match.externalId : null;
}

/**
 * GET /pronostics/:id/insights — « Pourquoi ce pronostic ».
 *
 * Réunit le modèle statistique du fournisseur (probabilités 1X2, sept axes de
 * comparaison) et le profil de buts par tranche horaire des deux équipes.
 * Deux à trois requêtes API au premier appel, puis cache 6 h / 24 h.
 */
export const getMatchInsights = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const fixtureId = fixtureIdDe(prono.match);
    if (!fixtureId) { res.status(404).json({ message: 'Données détaillées indisponibles pour ce match.' }); return; }

    const prediction = await apiFootballInsights.getPrediction(fixtureId);
    if (!prediction) { res.status(503).json({ message: 'Analyse indisponible.' }); return; }

    // Les statistiques de saison n'ont de sens qu'en championnat : sur un tour
    // de coupe, la « saison » de la compétition n'a pas de tableau de buts.
    const [statsHome, statsAway] = prediction.leagueId && prediction.season
      ? await Promise.all([
          prediction.homeTeamId
            ? apiFootballInsights.getTeamSeasonStats(
                prediction.leagueId, prediction.season, prediction.homeTeamId)
            : null,
          prediction.awayTeamId
            ? apiFootballInsights.getTeamSeasonStats(
                prediction.leagueId, prediction.season, prediction.awayTeamId)
            : null,
        ])
      : [null, null];

    res.json({
      advice:         prediction.advice,
      winner_name:    prediction.winnerName,
      winner_comment: prediction.winnerComment,
      percent: {
        home: prediction.percentHome,
        draw: prediction.percentDraw,
        away: prediction.percentAway,
      },
      under_over:  prediction.underOver,
      comparisons: prediction.comparisons,
      form: { home: prediction.formHome, away: prediction.formAway },
      clean_sheet:      { home: prediction.cleanSheetHome,    away: prediction.cleanSheetAway },
      failed_to_score:  { home: prediction.failedToScoreHome, away: prediction.failedToScoreAway },
      goals_by_minute: {
        home: statsHome?.goalsForByMinute ?? null,
        away: statsAway?.goalsForByMinute ?? null,
      },
      goals_average: {
        home: statsHome?.goalsForAverage ?? null,
        away: statsAway?.goalsForAverage ?? null,
      },
      home_team: prono.match.homeTeam,
      away_team: prono.match.awayTeam,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/**
 * GET /pronostics/:id/live-odds — cotes qui suivent le match.
 *
 * Le service ne filtre jamais `/odds/live` par fixture : un seul appel couvre
 * tous les matchs en cours, et le cache de 2 minutes est partagé.
 */
export const getLiveOdds = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }
    if (prono.match.status !== 'LIVE') {
      res.status(400).json({ message: 'Cotes en direct réservées aux matchs en cours.' });
      return;
    }

    const fixtureId = fixtureIdDe(prono.match);
    if (!fixtureId) { res.status(404).json({ message: 'Données détaillées indisponibles pour ce match.' }); return; }

    const odds = await apiFootballInsights.getLiveOdds(fixtureId);
    if (!odds) { res.status(503).json({ message: 'Cotes en direct indisponibles.' }); return; }

    res.json({
      elapsed: odds.elapsed,
      markets: odds.markets,
      // Cote d'ouverture du pronostic, pour situer la variation.
      opening_odd: prono.oddsRecommended,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /pronostics/:id/ratings — notes des joueurs d'un match terminé. */
export const getPlayerRatings = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }
    if (prono.match.status !== 'FINISHED') {
      res.status(400).json({ message: 'Notes disponibles après le coup de sifflet final.' });
      return;
    }

    const fixtureId = fixtureIdDe(prono.match);
    if (!fixtureId) { res.status(404).json({ message: 'Données détaillées indisponibles pour ce match.' }); return; }

    const ratings = await apiFootballInsights.getPlayerRatings(fixtureId);
    if (!ratings?.length) { res.status(503).json({ message: 'Notes indisponibles.' }); return; }

    res.json({
      home_team: prono.match.homeTeam,
      away_team: prono.match.awayTeam,
      players:   ratings,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /pronostics/top-scorers?league=PL — meilleurs buteurs d'une compétition. */
export const getTopScorers = async (req: AuthRequest, res: Response) => {
  try {
    const code = (req.query.league as string) ?? '';
    const info = LEAGUE_INFO(code);
    if (!info) { res.status(400).json({ message: 'Compétition inconnue.' }); return; }

    const scorers = await apiFootballInsights.getTopScorers(info.id, info.season);
    if (!scorers) { res.status(503).json({ message: 'Classement des buteurs indisponible.' }); return; }
    res.json(scorers);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/**
 * GET /pronostics/admin/match/:matchId/prediction — avis du modèle, côté admin.
 *
 * Sert à orienter le choix du marché dans le formulaire, à côté des cotes
 * 1xBet. C'est une aide à la décision, pas une automatisation : la publication
 * reste un geste humain.
 */
export const getAdminPrediction = async (req: AdminRequest, res: Response) => {
  try {
    const match = await prisma.match.findUnique({ where: { id: req.params.matchId } });
    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }

    const fixtureId = fixtureIdDe(match);
    if (!fixtureId) { res.status(404).json({ message: 'Données détaillées indisponibles pour ce match.' }); return; }

    const prediction = await apiFootballInsights.getPrediction(fixtureId);
    if (!prediction) { res.status(503).json({ message: 'Avis du modèle indisponible.' }); return; }
    res.json(prediction);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getH2H = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const externalId = prono.match.externalId;
    if (!externalId) { res.status(404).json({ message: 'ID externe manquant.' }); return; }

    // Deux fournisseurs identifient les matchs différemment : football-data.org
    // par externalId direct, API-Football par ID d'équipe (retrouvé via date + noms).
    const h2h = prono.match.source === 'API_FOOTBALL'
      ? await apiFootballService.getH2H(
          prono.match.homeTeam, prono.match.awayTeam,
          new Date(prono.match.matchDate).toISOString().split('T')[0], 10,
        )
      : await fdSvc.getH2H(externalId, 10);

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

// Compositions d'équipe — uniquement disponibles côté API-Football (source unique désormais)
export const getLineups = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    if (prono.match.source !== 'API_FOOTBALL') {
      res.json({ available: false, home: null, away: null });
      return;
    }

    const lineups = await apiFootballService.getLineups(
      prono.match.homeTeam, prono.match.awayTeam,
      new Date(prono.match.matchDate).toISOString().split('T')[0],
    );

    if (!lineups) { res.status(503).json({ message: 'Compositions indisponibles.' }); return; }
    res.json(lineups);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// Blessures / suspensions — uniquement disponibles côté API-Football
export const getInjuries = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    if (prono.match.source !== 'API_FOOTBALL') { res.json([]); return; }

    const injuries = await apiFootballService.getInjuries(
      prono.match.homeTeam, prono.match.awayTeam,
      new Date(prono.match.matchDate).toISOString().split('T')[0],
    );

    if (injuries === null) { res.status(503).json({ message: 'Blessures indisponibles.' }); return; }
    res.json(injuries);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// Classement de la ligue du match — grandes ligues suivies uniquement
export const getStandings = async (req: AuthRequest, res: Response) => {
  try {
    const prono = await findPronoByIdOrMatchId(req.params.id);
    if (!prono) { res.status(404).json({ message: 'Pronostic introuvable.' }); return; }

    const standings = await apiFootballService.getStandings(prono.match.leagueCode);
    if (standings === null) { res.status(503).json({ message: 'Classement indisponible.' }); return; }
    res.json(standings);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// Analyse statistique d'un pronostic : probabilité calculée à partir de la
// cote et de la forme, plus une explication du calcul. Aucun modèle génératif
// n'est appelé (cf. ai_prediction.service.ts).
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
    const p = match.pronostic;
    res.json({
      ...match,
      has_pronostic: !!p,
      is_published:  p?.isPublished ?? false,
      // Le formulaire admin (pronostic_form.ejs) attend du snake_case — Prisma
      // renvoie du camelCase par défaut, d'où ce remappage explicite.
      pronostic: p ? {
        id:                p.id,
        prediction_type:   p.predictionType,
        prediction_label:  p.predictionLabel,
        market_name:       p.marketName,
        market_value:      p.marketValue,
        odds_home:         p.oddsHome,
        odds_draw:         p.oddsDraw,
        odds_away:         p.oddsAway,
        odds_recommended:  p.oddsRecommended,
        confidence_score:  p.confidenceScore,
        analyst_note:      p.analystNote,
        is_premium:        p.isPremium,
        is_published:      p.isPublished,
        result:            p.result,
        createdAt:         p.createdAt,
        updatedAt:         p.updatedAt,
        publishedAt:       p.publishedAt,
      } : null,
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
