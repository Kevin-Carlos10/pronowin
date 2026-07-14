import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { FootballDataService } from './football_data.service';
import { NotificationService } from './notification.service';
import { settleBets } from './bankroll.service';

const fdSvc     = new FootballDataService();
const notifSvc  = new NotificationService();

// Mapper les statuts Football-Data.org vers nos statuts Prisma
function mapFDStatus(fdStatus: string): 'SCHEDULED' | 'LIVE' | 'FINISHED' | 'POSTPONED' | 'SUSPENDED' {
  switch (fdStatus) {
    case 'SCHEDULED':
    case 'TIMED':       return 'SCHEDULED';   // TIMED = match programm茅 avec heure confirm茅e
    case 'IN_PLAY':
    case 'PAUSED':      return 'LIVE';
    case 'FINISHED':
    case 'AWARDED':     return 'FINISHED';
    case 'POSTPONED':   return 'POSTPONED';
    case 'SUSPENDED':
    case 'CANCELLED':   return 'SUSPENDED';
    default:            return 'SCHEDULED';
  }
}

// Calcule WIN ou LOSS selon le type de pronostic et le score final
function _computeResult(
  type: string,
  home: number,
  away: number,
): 'WIN' | 'LOSS' | null {
  const total = home + away;
  const correct = (() => {
    switch (type.toLowerCase()) {
      case 'win1':    return home > away;
      case 'draw':    return home === away;
      case 'win2':    return away > home;
      case 'btts':    return home > 0 && away > 0;
      case 'over25':  return total > 2;
      case 'under25': return total < 3;
      case 'over35':  return total > 3;
      case 'under35': return total < 4;
      default:        return null;
    }
  })();
  if (correct === null) return null;
  return correct ? 'WIN' : 'LOSS';
}

export class PronosticsService {

  // Set en m茅moire pour 茅viter les doublons de notif "match bient么t"
  // (r茅initialis茅 au red茅marrage du serveur 鈥?acceptable car les matchs changent chaque jour)

  // 鈹€鈹€鈹€ CRON 鈥?Notifier "match dans 1h" 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  /**
   * 脌 appeler toutes les 15 minutes depuis index.ts.
   * Cherche les matchs programm茅s dans 45鈥?5 min avec un pronostic publi茅
   * et envoie une notification push 脿 tous les abonn茅s au topic "match_alerts".
   */
  async checkMatchesSoon(): Promise<{ notified: number }> {
    const now  = new Date();
    const from = new Date(now.getTime() + 45 * 60_000); // +45 min
    const to   = new Date(now.getTime() + 75 * 60_000); // +75 min

    const matches = await prisma.match.findMany({
      where: {
        matchDate: { gte: from, lte: to },
        status:    'SCHEDULED',
        alertSent: false,
        pronostic: { isPublished: true },
      },
      include: { pronostic: true },
    });

    let notified = 0;
    for (const m of matches) {
      try {
        await notifSvc.notifyMatchSoon(m.homeTeam, m.awayTeam, m.pronostic!.id, m.id);
        await prisma.match.update({ where: { id: m.id }, data: { alertSent: true } });
        notified++;
      } catch (err: any) {
        console.error(`[MatchSoon] Erreur notif ${m.homeTeam} vs ${m.awayTeam}:`, err.message);
      }
    }

    return { notified };
  }


  // 鈹€鈹€鈹€ ADMIN 鈥?R茅cup茅rer les matchs depuis Football-Data.org 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async fetchUpcomingMatchesForAdmin(competitionCode?: string) {
    const fdMatches = await fdSvc.getUpcomingMatches(competitionCode);

    // Upsert chaque match en base avec mapping des statuts
    const validMatches = fdMatches.filter((m) => {
      const data = fdSvc.formatForPronostic(m);
      return data.home_team && data.away_team;
    });

    const saved = await Promise.all(
      validMatches.map(async (m) => {
        const data       = fdSvc.formatForPronostic(m);
        const mappedStatus = mapFDStatus(m.status);

        return prisma.match.upsert({
          where:  { externalId: m.id },
          update: {
            status:    mappedStatus,
            homeScore: m.score.fullTime.home,
            awayScore: m.score.fullTime.away,
          },
          create: {
            externalId:   m.id,
            league:       data.league,
            leagueCode:   data.league_code,
            leagueLogo:   data.league_logo ?? null,
            homeTeam:     data.home_team,
            homeTeamFull: data.home_team_full ?? data.home_team,
            homeTeamLogo: data.home_team_logo ?? null,
            awayTeam:     data.away_team,
            awayTeamFull: data.away_team_full ?? data.away_team,
            awayTeamLogo: data.away_team_logo ?? null,
            matchDate:    new Date(data.match_date),
            status:       mappedStatus,
          },
        });
      })
    );

    // Inclure aussi les matchs LIVE déjà en DB (synchronisés par le cron)
    const savedIds = new Set(saved.map(m => m.id));
    const liveFromDb = await prisma.match.findMany({
      where: {
        status: 'LIVE',
        ...(competitionCode ? { leagueCode: competitionCode } : {}),
      },
    });
    const liveOnly = liveFromDb.filter(m => !savedIds.has(m.id));

    const allMatches = [...saved, ...liveOnly];

    // Ajouter l'info "a déjà un pronostic"
    const matchIds = allMatches.map(m => m.id);
    const existing = await prisma.pronostic.findMany({
      where:  { matchId: { in: matchIds } },
      select: { matchId: true, isPublished: true },
    });
    const pronoMap = new Map(existing.map(p => [p.matchId, p]));

    return allMatches
      .sort((a, b) => a.matchDate.getTime() - b.matchDate.getTime())
      .map(m => ({
        ...m,
        has_pronostic: pronoMap.has(m.id),
        is_published:  pronoMap.get(m.id)?.isPublished ?? false,
      }));
  }

  // 鈹€鈹€鈹€ SYNC AUTOMATIQUE DES SCORES 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  /**
   * R茅cup猫re les matchs live/termin茅s depuis football-data.org,
   * met 脿 jour les scores en base et calcule le r茅sultat (WIN/LOSS) des pronostics.
   * Appel茅 toutes les 5 minutes par le setInterval dans index.ts.
   */
  async syncMatchScores(): Promise<{ updated: number; resolved: number }> {
    let updated  = 0;
    let resolved = 0;

    // 1. R茅cup茅rer depuis l'API les matchs en cours / termin茅s
    const fdMatches = await fdSvc.getLiveAndRecentMatches();
    if (fdMatches.length === 0) return { updated, resolved };

    // 2. Mettre 脿 jour chaque match en base
    for (const m of fdMatches) {
      const mappedStatus = mapFDStatus(m.status);
      const homeScore    = m.score.fullTime.home ?? null;
      const awayScore    = m.score.fullTime.away ?? null;

      const match = await prisma.match.findUnique({ where: { externalId: m.id } });
      if (!match) continue;

      const unchanged =
        match.status === mappedStatus &&
        match.homeScore === homeScore &&
        match.awayScore === awayScore;
      if (unchanged) continue;

      const previousStatus = match.status;

      await prisma.match.update({
        where: { externalId: m.id },
        data:  { status: mappedStatus, homeScore, awayScore },
      });
      updated++;

      // R茅cup茅rer les utilisateurs qui ont mis ce match en favori
      const favorites = await prisma.userFavoriteMatch.findMany({
        where:  { matchId: match.id },
        select: { userId: true },
      });

      // Notifier si le match passe en LIVE
      if (mappedStatus === 'LIVE' && previousStatus !== 'LIVE') {
        const liveProno = await prisma.pronostic.findUnique({
          where: { matchId: match.id }, select: { id: true },
        });
        for (const fav of favorites) {
          notifSvc.sendToUser(fav.userId, {
            title: '鈿?Match en direct !',
            body:  `${match.homeTeam} vs ${match.awayTeam} vient de commencer.`,
            data:  {
              type:      'match_live',
              deep_link: liveProno ? `/pronostics/${liveProno.id}` : '',
              match_id:  match.id,
            },
          }).catch((err: any) => console.error("[PronoSvc]", err.message));
        }
      }

      // 3. Si le match est TERMIN脡 鈫?calculer le r茅sultat du pronostic
      if (mappedStatus === 'FINISHED' && homeScore !== null && awayScore !== null) {
        const prono = await prisma.pronostic.findUnique({
          where: { matchId: match.id },
        });

        // Notifier fin de match (score final) aux favoris
        if (favorites.length > 0) {
          const scoreStr = `${homeScore} - ${awayScore}`;
          for (const fav of favorites) {
            notifSvc.sendToUser(fav.userId, {
              title: `Fin de match : ${match.homeTeam} ${scoreStr} ${match.awayTeam}`,
              body:  'Le match est termin茅. Consultez le r茅sultat de votre pronostic.',
              data:  {
                type:      'match_finished',
                deep_link: prono ? `/pronostics/${prono.id}` : '',
                match_id:  match.id,
              },
            }).catch((err: any) => console.error("[PronoSvc]", err.message));
          }
        }

        if (prono && prono.isPublished && !prono.result) {
          const result = _computeResult(
            prono.predictionType as string,
            homeScore,
            awayScore,
          );
          if (result) {
            await prisma.pronostic.update({
              where: { id: prono.id },
              data:  { result },
            });
            resolved++;
            settleBets(prono.id, result).catch((err: any) => console.error("[PronoSvc]", err.message));
            console.log(`[ScoreSync] Pronostic ${prono.id} 鈫?${result} (${homeScore}-${awayScore})`);
            notifSvc.notifyMatchResult({
              homeTeam:    match.homeTeam,
              awayTeam:    match.awayTeam,
              homeScore,
              awayScore,
              result,
              pronosticId: prono.id,
            }).catch((err: any) => console.error("[PronoSvc]", err.message));

            // Notifier personnellement les utilisateurs favoris avec le r茅sultat de leur prono
            const emoji = result === 'WIN' ? '✅' : '❌';
            const label = result === 'WIN' ? 'Pronostic gagnant !' : 'Pronostic perdant';
            for (const fav of favorites) {
              notifSvc.sendToUser(fav.userId, {
                title: `${emoji} ${label}`,
                body:  `${match.homeTeam} ${homeScore}-${awayScore} ${match.awayTeam} 路 Prono : ${prono.predictionLabel}`,
                data:  {
                  type:      'prono_result',
                  deep_link: `/pronostics/${prono.id}`,
                  match_id:  match.id,
                },
              }).catch((err: any) => console.error("[PronoSvc]", err.message));
            }
          }
        }
      }
    }

    // 4. R茅soudre les pronostics publi茅s dont le match est d茅j脿 FINISHED en base
    //    (cas : pronostic publi茅 apr猫s la fin du match, ou serveur red茅marr茅 apr猫s la fin)
    const unresolvedPronos = await prisma.pronostic.findMany({
      where: {
        isPublished: true,
        result:      null,
        match:       { status: 'FINISHED', homeScore: { not: null }, awayScore: { not: null } },
      },
      include: { match: { select: { id: true, homeTeam: true, awayTeam: true, homeScore: true, awayScore: true } } },
    });
    for (const prono of unresolvedPronos) {
      const { homeScore, awayScore } = prono.match;
      const result = _computeResult(prono.predictionType as string, homeScore!, awayScore!);
      if (result) {
        await prisma.pronostic.update({ where: { id: prono.id }, data: { result } });
        resolved++;
        settleBets(prono.id, result).catch((err: any) => console.error("[PronoSvc]", err.message));
        console.log(`[ScoreSync] Pronostic ${prono.id} 鈫?${result} (backfill ${homeScore}-${awayScore})`);
        notifSvc.notifyMatchResult({
          homeTeam:    prono.match.homeTeam,
          awayTeam:    prono.match.awayTeam,
          homeScore:   homeScore!,
          awayScore:   awayScore!,
          result,
          pronosticId: prono.id,
        }).catch((err: any) => console.error("[PronoSvc]", err.message));
      }
    }

    console.log(`[ScoreSync] 鉁?${updated} matchs mis 脿 jour, ${resolved} r茅sultats calcul茅s`);
    return { updated, resolved };
  }

  // 鈹€鈹€鈹€ ADMIN 鈥?Cr茅er / Mettre 脿 jour un pronostic 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async upsertPronostic(params: {
    matchId:         string;
    analystId:       string;
    predictionType:  string;
    predictionLabel: string;
    oddsHome:        number;
    oddsDraw:        number;
    oddsAway:        number;
    oddsRecommended: number;
    confidenceScore: number;
    analystNote?:    string;
    isPremium:       boolean;
    publish:         boolean;
  }) {
    const match = await prisma.match.findUnique({ where: { id: params.matchId } });
    if (!match) throw new Error('Match introuvable.');
    if (match.status === 'FINISHED') throw new Error('Impossible de créer un pronostic pour un match terminé.');

    const data: Prisma.PronosticUncheckedCreateInput = {
      matchId:         params.matchId,
      analystId:       params.analystId,
      predictionType:  params.predictionType as any,
      predictionLabel: params.predictionLabel,
      oddsHome:        params.oddsHome,
      oddsDraw:        params.oddsDraw,
      oddsAway:        params.oddsAway,
      oddsRecommended: params.oddsRecommended,
      confidenceScore: params.confidenceScore,
      analystNote:     params.analystNote ?? null,
      isPremium:       params.isPremium,
      isPublished:     params.publish,
      publishedAt:     params.publish ? new Date() : null,
    };

    return prisma.pronostic.upsert({
      where:   { matchId: params.matchId },
      update:  { ...data, updatedAt: new Date() },
      create:  data,
      include: { match: true, analyst: { select: { name: true } } },
    });
  }

  // 鈹€鈹€鈹€ ADMIN 鈥?Publier / D茅publier 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async togglePublish(pronosticId: string, publish: boolean) {
    return prisma.pronostic.update({
      where: { id: pronosticId },
      data:  { isPublished: publish, publishedAt: publish ? new Date() : null },
    });
  }

  // 鈹€鈹€鈹€ Helper : filtre de date 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  private buildDateWhere(dateFilter?: string): Prisma.MatchWhereInput {
    const now      = new Date();
    const today    = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(today.getTime() + 86400000);
    const week     = new Date(today.getTime() + 7 * 86400000);
    const past30   = new Date(today.getTime() - 30 * 86400000);

    if (dateFilter === 'today')    return { matchDate: { gte: today,    lt: tomorrow } };
    if (dateFilter === 'tomorrow') return { matchDate: { gte: tomorrow, lt: new Date(tomorrow.getTime() + 86400000) } };
    if (dateFilter === 'past30')   return { matchDate: { gte: past30,   lt: tomorrow } };
    if (dateFilter === 'week')     return { matchDate: { gte: today,    lt: week } };

    // Format YYYY-MM-DD 鈥?jour sp茅cifique
    if (dateFilter && /^\d{4}-\d{2}-\d{2}$/.test(dateFilter)) {
      const d   = new Date(dateFilter + 'T00:00:00');
      const end = new Date(d.getTime() + 86400000);
      return { matchDate: { gte: d, lt: end } };
    }

    // Par d茅faut : semaine 脿 venir + 30 jours pass茅s
    return { matchDate: { gte: past30, lt: week } };
  }

  // 鈹€鈹€鈹€ PUBLIC 鈥?Liste pronostics publi茅s 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getPublishedPronostics(params: {
    userId:      string;
    dateFilter?: string;
    sport?:      string;
    leagueCode?: string;
    cursor?:     string;
    limit:       number;
  }) {
    const user = await prisma.user.findUnique({ where: { id: params.userId } });
    const isPremium = user?.subscriptionPlan === 'premium' &&
      (user.subscriptionExpiresAt ? user.subscriptionExpiresAt > new Date() : false);

    const dateWhere = this.buildDateWhere(params.dateFilter);

    const pronostics = await prisma.pronostic.findMany({
      where: {
        isPublished: true,
        match: {
          ...dateWhere,
          ...(params.leagueCode ? { leagueCode: params.leagueCode } : {}),
        },
      },
      include: {
        match:   true,
        analyst: { select: { name: true } },
      },
      orderBy: { match: { matchDate: 'asc' } },
      take:    params.limit,
      ...(params.cursor ? { cursor: { id: params.cursor }, skip: 1 } : {}),
    });

    const nextCursor = pronostics.length === params.limit
      ? pronostics[pronostics.length - 1].id
      : null;
    const data = pronostics.map(p => ({
      id:               p.id,
      league:           p.match.league,
      league_country:   p.match.leagueCode,
      home_team:        p.match.homeTeam,
      away_team:        p.match.awayTeam,
      home_team_logo:   p.match.homeTeamLogo,
      away_team_logo:   p.match.awayTeamLogo,
      match_date:       p.match.matchDate,
      status:           p.match.status.toLowerCase() === 'live'     ? 'live'
                      : p.match.status.toLowerCase() === 'finished' ? 'finished'
                      : 'upcoming',
      home_score:       p.match.homeScore,
      away_score:       p.match.awayScore,
      prediction_type:  p.predictionType,
      prediction_label: p.predictionLabel,
      odds_home:        p.oddsHome,
      odds_draw:        p.oddsDraw,
      odds_away:        p.oddsAway,
      odds_recommended: p.oddsRecommended,
      confidence_score: p.confidenceScore,
      is_premium:       p.isPremium,
      analyst_note:     p.isPremium && !isPremium ? null : p.analystNote,
      analyst_name:     p.analyst.name,
      result:           p.result,
      home_form_points: p.match.homeFormPoints,
      away_form_points: p.match.awayFormPoints,
    }));
    return { data, nextCursor, hasMore: nextCursor !== null };
  }

  // 鈹€鈹€鈹€ Tous les matchs (avec ou sans pronostic publi茅) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getAllMatches(params: {
    userId:      string;
    dateFilter?: string;
    sport?:      string;
    leagueCode?: string;
    cursor?:     string;
    limit:       number;
  }) {
    const user = await prisma.user.findUnique({ where: { id: params.userId } });
    const isPremium = user?.subscriptionPlan === 'premium' &&
      (user.subscriptionExpiresAt ? user.subscriptionExpiresAt > new Date() : false);

    const dateWhere = this.buildDateWhere(params.dateFilter);

    const matches = await prisma.match.findMany({
      where: {
        ...dateWhere,
        // Exclure les matchs annul茅s / report茅s ind茅finiment
        status: { notIn: ['POSTPONED', 'SUSPENDED'] },
        ...(params.leagueCode ? { leagueCode: params.leagueCode } : {}),
      },
      include: {
        pronostic: {
          include: { analyst: { select: { name: true } } },
        },
      },
      orderBy: { matchDate: 'asc' },
      take:    params.limit,
      ...(params.cursor ? { cursor: { id: params.cursor }, skip: 1 } : {}),
    });

    const nextCursor = matches.length === params.limit
      ? matches[matches.length - 1].id
      : null;
    const data = matches.map(m => {
      const p           = m.pronostic;
      const hasPronostic = !!p && p.isPublished;

      return {
        id:               m.id,
        league:           m.league,
        league_country:   m.leagueCode,
        home_team:        m.homeTeam,
        away_team:        m.awayTeam,
        home_team_logo:   m.homeTeamLogo,
        away_team_logo:   m.awayTeamLogo,
        match_date:       m.matchDate,
        status:           m.status.toLowerCase() === 'live' ? 'live'
                        : m.status.toLowerCase() === 'finished' ? 'finished'
                        : 'upcoming',
        home_score:       m.homeScore,
        away_score:       m.awayScore,
        has_pronostic:    hasPronostic,
        prediction_type:  hasPronostic ? p!.predictionType.toLowerCase()  : null,
        prediction_label: hasPronostic ? p!.predictionLabel               : null,
        odds_home:        hasPronostic ? p!.oddsHome                      : null,
        odds_draw:        hasPronostic ? p!.oddsDraw                      : null,
        odds_away:        hasPronostic ? p!.oddsAway                      : null,
        odds_recommended: hasPronostic ? p!.oddsRecommended               : null,
        confidence_score: hasPronostic ? p!.confidenceScore               : null,
        is_premium:       hasPronostic ? p!.isPremium                     : false,
        analyst_note:     hasPronostic && (!p!.isPremium || isPremium) ? p!.analystNote : null,
        analyst_name:     hasPronostic ? p!.analyst.name                  : null,
        result:           hasPronostic ? p!.result                        : null,
        home_form_points: m.homeFormPoints,
        away_form_points: m.awayFormPoints,
      };
    });
    return { data, nextCursor, hasMore: nextCursor !== null };
  }

  // 鈹€鈹€鈹€ Stats publiques (accueil mobile) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getPublicStats() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Tous les pronostics termin茅s (r茅sultat connu)
    const finished = await prisma.pronostic.findMany({
      where: { isPublished: true, result: { in: ['WIN', 'LOSS'] } },
      select: { result: true, publishedAt: true },
      orderBy: { publishedAt: 'desc' },
    });

    const totalFinished = finished.length;
    const wins          = finished.filter(p => p.result === 'WIN').length;
    const winRate       = totalFinished > 0
      ? Math.round((wins / totalFinished) * 100)
      : 0;

    // S茅rie actuelle (cons茅cutive depuis le plus r茅cent)
    let streak = 0;
    for (const p of finished) {
      if (p.result === 'WIN') streak++;
      else break;
    }

    // Pronostics publi茅s aujourd'hui
    const publishedToday = await prisma.pronostic.count({
      where: {
        isPublished: true,
        publishedAt: { gte: today },
      },
    });

    // Pronostics 脿 venir (status SCHEDULED, publi茅s)
    const upcoming = await prisma.pronostic.count({
      where: {
        isPublished: true,
        match: { status: 'SCHEDULED' },
      },
    });

    return { winRate, streak, totalFinished, wins, publishedToday, upcoming };
  }

  // 鈹€鈹€鈹€ Stats admin 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getAdminStats() {
    const [totalUsers, premiumUsers, pendingTx, totalPronostics, publishedToday] =
      await Promise.all([
        prisma.user.count({ where: { isActive: true } }),
        prisma.user.count({
          where: { subscriptionPlan: 'premium', subscriptionExpiresAt: { gt: new Date() } },
        }),
        prisma.transaction.count({ where: { status: 'pending' } }),
        prisma.pronostic.count(),
        prisma.pronostic.count({
          where: {
            isPublished: true,
            publishedAt: { gte: new Date(new Date().setHours(0, 0, 0, 0)) },
          },
        }),
      ]);

    return { totalUsers, premiumUsers, pendingTx, totalPronostics, publishedToday };
  }
}
