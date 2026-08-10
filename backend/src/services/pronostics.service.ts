import { Prisma, MatchSource, Match } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { ApiFootballService, apiFootballService, mapAFStatus, matchStatusPriority } from './api_football.service';
import { NotificationService } from './notification.service';
import { settleBets } from './bankroll.service';

const notifSvc  = new NotificationService();

// Filet de sécurité anti-blocage (syncMatchScores) : throttle par match pour
// éviter de re-questionner à chaque cycle de sync (jusqu'à toutes les 30s
// désormais, 24h/24) des matchs dont l'API ne renverra jamais de statut
// final (amicaux/jeunes/féminines mal alimentés). Sans ça, mesuré en
// conditions réelles : ~27 requêtes/min en continu rien que pour ~30 matchs
// jamais résolus, de quoi épuiser le quota Pro (7 500/j) en 3-4h.
// 45 min (et non 30) pour garder de la marge maintenant que le scan
// principal tourne 24h/24 au lieu de 18h/24 avec blackout.
const staleRetryBackoff = new Map<number, number>(); // externalId → dernier essai (ms)
const STALE_RETRY_INTERVAL = 45 * 60 * 1000; // 45 min entre deux tentatives sur le même match

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

// ─── Règlement des marchés "personnalisés" (predictionType === 'other') ──────
// marketName/marketValue sont stockés en anglais brut (cohérence avec l'API
// — cf. pronostic_form.ejs), c'est donc sur ce format qu'on parse ici.

type ScoreLine = { home: number; away: number };

function _winner(s: ScoreLine): 'Home' | 'Draw' | 'Away' {
  if (s.home > s.away) return 'Home';
  if (s.away > s.home) return 'Away';
  return 'Draw';
}

function _secondHalf(ft: ScoreLine, fh: ScoreLine): ScoreLine {
  return { home: ft.home - fh.home, away: ft.away - fh.away };
}

function _parseOverUnder(value: string): { over: boolean; line: number } | null {
  const m = value.match(/^(Over|Under)\s+(\d+(?:\.\d+)?)$/);
  if (!m) return null;
  return { over: m[1] === 'Over', line: parseFloat(m[2]) };
}

function _overUnderResult(over: boolean, line: number, total: number): 'WIN' | 'LOSS' | 'PUSH' {
  if (total === line) return 'PUSH'; // seulement possible sur une ligne ronde (Over 2.0, Over 3.0...)
  return (total > line) === over ? 'WIN' : 'LOSS';
}

function _parseExactScore(value: string): ScoreLine | null {
  const m = value.match(/^(\d+):(\d+)$/);
  if (!m) return null;
  return { home: parseInt(m[1], 10), away: parseInt(m[2], 10) };
}

function _parseCombo(value: string): [string, string] | null {
  const parts = value.split('/');
  return parts.length === 2 ? [parts[0], parts[1]] : null;
}

function _parseHandicapValue(value: string): { side: 'Home' | 'Away'; line: number } | null {
  const m = value.match(/^(Home|Away)\s*([+-]?\d+(?:\.\d+)?)$/);
  if (!m) return null;
  return { side: m[1] as 'Home' | 'Away', line: parseFloat(m[2]) };
}

/** Résultat d'un handicap sur une ligne entière ou demi-entière (push possible uniquement sur ligne entière). */
function _handicapOutcome(side: 'Home' | 'Away', line: number, s: ScoreLine): 'WIN' | 'LOSS' | 'PUSH' {
  const teamScore = side === 'Home' ? s.home : s.away;
  const oppScore  = side === 'Home' ? s.away : s.home;
  const adjusted  = teamScore + line;
  if (adjusted > oppScore) return 'WIN';
  if (adjusted < oppScore) return 'LOSS';
  return 'PUSH';
}

/**
 * Handicap asiatique complet, y compris les lignes à quart (-0.25, -0.75...)
 * qui n'existent pas en pari classique : elles scindent virtuellement la
 * mise en deux moitiés sur les deux lignes demi-entières adjacentes.
 * Notre système n'a que 3 états (pas de "demi-victoire") : gagné+remboursé
 * devient WIN net, perdu+remboursé devient LOSS net — c'est la convention
 * standard des calculateurs de handicap asiatique.
 */
function _asianHandicapResult(side: 'Home' | 'Away', line: number, s: ScoreLine): 'WIN' | 'LOSS' | 'PUSH' {
  const quarterUnits  = Math.round(line * 4);
  const isQuarterLine = Math.abs(line * 4 - quarterUnits) < 1e-9 && quarterUnits % 2 !== 0;
  if (!isQuarterLine) return _handicapOutcome(side, line, s);

  const lower = Math.floor(line * 2) / 2;
  const upper = lower + 0.5;
  const outcomes = [_handicapOutcome(side, lower, s), _handicapOutcome(side, upper, s)];
  if (outcomes.every(o => o === 'WIN'))  return 'WIN';
  if (outcomes.every(o => o === 'LOSS')) return 'LOSS';
  return outcomes.includes('WIN') ? 'WIN' : 'LOSS'; // moitié gagnée/remboursée ou perdue/remboursée
}

/**
 * Règle un pronostic "marché personnalisé" à partir du marketName/marketValue
 * bruts 1xBet. Couvre la quasi-totalité des ~31 marchés proposés dans
 * l'admin ; retourne null pour les cas non couverts ("To Qualify", qui n'a
 * pas de sens sur un match simple — concept aller-retour) ou quand une
 * donnée nécessaire manque (score mi-temps absent pour un marché "MT").
 */
function _computeCustomMarketResult(
  marketName: string,
  marketValue: string,
  ft: ScoreLine,
  fh: ScoreLine | null,
): 'WIN' | 'LOSS' | 'PUSH' | null {
  const sh = fh ? _secondHalf(ft, fh) : null;
  const isWDA = (v: string) => v === 'Home' || v === 'Draw' || v === 'Away';

  switch (marketName) {
    case 'Match Winner':
      return isWDA(marketValue) ? (_winner(ft) === marketValue ? 'WIN' : 'LOSS') : null;
    case 'First Half Winner':
      return fh && isWDA(marketValue) ? (_winner(fh) === marketValue ? 'WIN' : 'LOSS') : null;
    case 'Second Half Winner':
      return sh && isWDA(marketValue) ? (_winner(sh) === marketValue ? 'WIN' : 'LOSS') : null;

    case 'Both Teams Score':
      return marketValue === 'Yes' || marketValue === 'No'
        ? ((ft.home > 0 && ft.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;
    case 'Both Teams Score - First Half':
      return fh && (marketValue === 'Yes' || marketValue === 'No')
        ? ((fh.home > 0 && fh.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;
    case 'Both Teams To Score - Second Half':
      return sh && (marketValue === 'Yes' || marketValue === 'No')
        ? ((sh.home > 0 && sh.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;

    case 'Goals Over/Under': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.home + ft.away) : null;
    }
    case 'Goals Over/Under First Half': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.home + fh.away) : null;
    }
    case 'Goals Over/Under - Second Half': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.home + sh.away) : null;
    }
    case 'Total - Home': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.home) : null;
    }
    case 'Total - Away': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.away) : null;
    }
    case 'Home Team Total Goals(1st Half)': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.home) : null;
    }
    case 'Away Team Total Goals(1st Half)': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.away) : null;
    }
    case 'Home Team Total Goals(2nd Half)': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.home) : null;
    }
    case 'Away Team Total Goals(2nd Half)': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.away) : null;
    }

    case 'Exact Score': {
      const s = _parseExactScore(marketValue);
      return s ? (s.home === ft.home && s.away === ft.away ? 'WIN' : 'LOSS') : null;
    }
    case 'Correct Score - First Half': {
      const s = fh && _parseExactScore(marketValue);
      return fh && s ? (s.home === fh.home && s.away === fh.away ? 'WIN' : 'LOSS') : null;
    }
    case 'Correct Score - Second Half': {
      const s = sh && _parseExactScore(marketValue);
      return sh && s ? (s.home === sh.home && s.away === sh.away ? 'WIN' : 'LOSS') : null;
    }

    case 'Highest Scoring Half': {
      if (!fh || !sh) return null;
      const fhTotal = fh.home + fh.away, shTotal = sh.home + sh.away;
      const actual = fhTotal > shTotal ? '1st Half' : fhTotal < shTotal ? '2nd Half' : 'Draw';
      return actual === marketValue ? 'WIN' : 'LOSS';
    }

    case 'HT/FT Double': {
      const combo = fh && _parseCombo(marketValue);
      return fh && combo ? (_winner(fh) === combo[0] && _winner(ft) === combo[1] ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance': {
      const combo = _parseCombo(marketValue);
      return combo ? (combo.includes(_winner(ft)) ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance - First Half': {
      const combo = fh && _parseCombo(marketValue);
      return fh && combo ? (combo.includes(_winner(fh)) ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance - Second Half': {
      const combo = sh && _parseCombo(marketValue);
      return sh && combo ? (combo.includes(_winner(sh)) ? 'WIN' : 'LOSS') : null;
    }

    case 'Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? (((ft.home + ft.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Odd/Even - First Half':
      return fh && (marketValue === 'Odd' || marketValue === 'Even')
        ? (((fh.home + fh.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Odd/Even - Second Half':
      return sh && (marketValue === 'Odd' || marketValue === 'Even')
        ? (((sh.home + sh.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Home Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? ((ft.home % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Away Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? ((ft.away % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;

    case 'Asian Handicap': {
      const h = _parseHandicapValue(marketValue);
      return h ? _asianHandicapResult(h.side, h.line, ft) : null;
    }
    case 'Asian Handicap First Half': {
      const h = fh && _parseHandicapValue(marketValue);
      return fh && h ? _asianHandicapResult(h.side, h.line, fh) : null;
    }
    case 'Asian Handicap (2nd Half)': {
      const h = sh && _parseHandicapValue(marketValue);
      return sh && h ? _asianHandicapResult(h.side, h.line, sh) : null;
    }

    // "To Qualify" (concept aller-retour) et tout marché non reconnu restent
    // en résolution manuelle via les boutons WIN/LOSS/Remboursé de l'admin.
    default:
      return null;
  }
}

/** Point d'entrée unique de règlement — dispatche vers les 8 types connus ou le moteur de marchés personnalisés. */
function _resolvePronosticResult(
  prono: { predictionType: string; marketName: string | null; marketValue: string | null },
  ft: ScoreLine,
  fh: ScoreLine | null,
): 'WIN' | 'LOSS' | 'PUSH' | null {
  if (prono.predictionType === 'other') {
    if (!prono.marketName || !prono.marketValue) return null;
    return _computeCustomMarketResult(prono.marketName, prono.marketValue, ft, fh);
  }
  return _computeResult(prono.predictionType, ft.home, ft.away);
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
  async fetchUpcomingMatchesForAdmin(competitionCode?: string, search?: string, date?: string, mine?: boolean, live?: boolean) {
    // "Match en direct" → uniquement les matchs actuellement en cours,
    // lecture DB pure (statut tenu à jour par le cron de sync).
    if (live) return this._liveMatches(competitionCode, search);

    // "Mes pronostics" → tous les matchs déjà pronostiqués, toutes dates et
    // tous statuts confondus (y compris terminés). Sans ça, un match qui se
    // termine sort de toutes les vues (l'API ne renvoie que les matchs à
    // venir) et devient introuvable sans deviner sa date exacte.
    if (mine) return this._myPronostics(competitionCode, search);

    // Une date précise → on regarde ce qu'on a déjà en base (passé, en cours
    // ou à venir, terminé y compris) plutôt que d'interroger l'API, qui ne
    // renvoie que les matchs pas-encore-commencés des 7 prochains jours.
    // Couvre le besoin "revoir les pronostics déjà publiés avec leur résultat".
    if (date) return this._matchesForDate(date, competitionCode, search);

    // Source unique : API-Football couvre à la fois les grandes ligues, les
    // amicaux et tout le reste — un seul fetch, filtré ensuite selon le mode
    // demandé (vue par défaut restreinte / une ligue précise / absolument tout).
    const fixtures = await apiFootballService.getAllUpcomingFixtures();

    interface NormalizedMatch {
      external_id:     number;
      source:          MatchSource;
      league:          string;
      league_code:     string;
      league_logo:     string | null;
      home_team:       string;
      home_team_full:  string | null;
      home_team_logo:  string | null;
      away_team:       string;
      away_team_full:  string | null;
      away_team_logo:  string | null;
      match_date:      string;
      status:          string;
      home_score:      number | null;
      away_score:      number | null;
    }

    const majorCodes = ApiFootballService.majorLeagueCodes();
    const normalized: NormalizedMatch[] = fixtures
      .map(f => ({ ...apiFootballService.formatFixtureForPronostic(f), source: MatchSource.API_FOOTBALL }))
      .filter(data => {
        if (competitionCode === 'ALL') return true;
        if (competitionCode)           return data.league_code === competitionCode;
        // Pas de filtre → vue par défaut : grandes ligues suivies + amicaux uniquement
        return majorCodes.includes(data.league_code);
      });

    // Upsert chaque match en base avec mapping des statuts
    const validMatches = normalized.filter(data => data.home_team && data.away_team);

    const saved = await Promise.all(
      validMatches.map(async (data) => {
        const mappedStatus = mapAFStatus(data.status);

        return prisma.match.upsert({
          where: {
            externalId_source: { externalId: data.external_id, source: data.source },
          },
          update: {
            status:         mappedStatus,
            statusPriority: matchStatusPriority(mappedStatus),
            homeScore:      data.home_score,
            awayScore:      data.away_score,
          },
          create: {
            externalId:     data.external_id,
            source:         data.source,
            league:         data.league,
            leagueCode:     data.league_code,
            leagueLogo:     data.league_logo ?? null,
            homeTeam:       data.home_team,
            homeTeamFull:   data.home_team_full ?? data.home_team,
            homeTeamLogo:   data.home_team_logo ?? null,
            awayTeam:       data.away_team,
            awayTeamFull:   data.away_team_full ?? data.away_team,
            awayTeamLogo:   data.away_team_logo ?? null,
            matchDate:      new Date(data.match_date),
            status:         mappedStatus,
            statusPriority: matchStatusPriority(mappedStatus),
          },
        });
      })
    );

    // Inclure aussi les matchs LIVE déjà en DB (synchronisés par le cron) —
    // en respectant le même filtre de ligue que la liste principale, sinon
    // un match LIVE d'une ligue exotique fuiterait dans la vue par défaut.
    const savedIds = new Set(saved.map(m => m.id));
    const liveFromDb = await prisma.match.findMany({
      where: {
        status: 'LIVE',
        ...(competitionCode === 'ALL'
          ? {}
          : competitionCode
            ? { leagueCode: competitionCode }
            : { leagueCode: { in: majorCodes } }),
      },
    });
    const liveOnly = liveFromDb.filter(m => !savedIds.has(m.id));

    const allMatches = [...saved, ...liveOnly];
    return this._attachPronosticsAndFilter(allMatches, search);
  }

  /** Matchs d'une date précise déjà en base (tous statuts confondus) — pour revoir les pronostics passés/terminés. */
  private async _matchesForDate(date: string, competitionCode?: string, search?: string) {
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);

    const majorCodes = ApiFootballService.majorLeagueCodes();
    const matches = await prisma.match.findMany({
      where: {
        matchDate: { gte: dayStart, lte: dayEnd },
        ...(competitionCode === 'ALL' ? {}
          : competitionCode ? { leagueCode: competitionCode }
          : { leagueCode: { in: majorCodes } }),
      },
    });

    return this._attachPronosticsAndFilter(matches, search);
  }

  /**
   * Uniquement les matchs actuellement en cours — requête DB pure (le statut
   * LIVE est tenu à jour par le cron syncMatchScores, y compris via le filet
   * de sécurité anti-blocage). Même respect du filtre de ligue que les
   * autres vues admin.
   */
  private async _liveMatches(competitionCode?: string, search?: string) {
    const majorCodes = ApiFootballService.majorLeagueCodes();
    const matches = await prisma.match.findMany({
      where: {
        status: 'LIVE',
        ...(competitionCode === 'ALL' ? {}
          : competitionCode ? { leagueCode: competitionCode }
          : { leagueCode: { in: majorCodes } }),
      },
    });

    return this._attachPronosticsAndFilter(matches, search);
  }

  /**
   * Tous les matchs déjà pronostiqués (publiés ou brouillons), toutes dates et
   * tous statuts confondus — requête DB pure, aucun appel API. C'est ici qu'un
   * admin retrouve un match qu'il a pronostiqué même une fois celui-ci terminé
   * et sorti de la fenêtre "7 prochains jours" de l'API.
   */
  private async _myPronostics(competitionCode?: string, search?: string) {
    const matches = await prisma.match.findMany({
      where: {
        pronostic: { isNot: null },
        ...(competitionCode && competitionCode !== 'ALL' ? { leagueCode: competitionCode } : {}),
      },
      orderBy: { matchDate: 'desc' },
      take: 200,
    });

    // desc : review des pronostics passés — le plus récent (souvent déjà
    // joué) en premier, plutôt que trié par ancienneté croissante.
    return this._attachPronosticsAndFilter(matches, search, 'desc');
  }

  /** Attache à chaque match les infos du pronostic associé (résultat, cote, confiance...) + filtre texte. */
  private async _attachPronosticsAndFilter(matches: Match[], search?: string, sortOrder: 'asc' | 'desc' = 'asc') {
    const matchIds = matches.map(m => m.id);
    const existing = await prisma.pronostic.findMany({
      where:  { matchId: { in: matchIds } },
      select: {
        id: true, matchId: true, isPublished: true, isPremium: true,
        predictionLabel: true, confidenceScore: true, oddsRecommended: true,
        result: true, createdAt: true,
      },
    });
    const pronoMap = new Map(existing.map(p => [p.matchId, p]));

    const result = matches
      .sort((a, b) => sortOrder === 'desc'
        ? b.matchDate.getTime() - a.matchDate.getTime()
        : a.matchDate.getTime() - b.matchDate.getTime())
      .map(m => {
        const prono = pronoMap.get(m.id);
        return {
          ...m,
          has_pronostic: !!prono,
          is_published:  prono?.isPublished ?? false,
          pronostic: prono ? {
            id:                prono.id,
            tip:               prono.predictionLabel,
            prediction_label:  prono.predictionLabel,
            confidence_score:  prono.confidenceScore,
            odds:              prono.oddsRecommended,
            is_premium:        prono.isPremium,
            published:         prono.isPublished,
            result:            prono.result,
            createdAt:         prono.createdAt,
          } : null,
        };
      });

    if (!search?.trim()) return result;
    const q = search.trim().toLowerCase();
    return result.filter(m =>
      m.homeTeam.toLowerCase().includes(q) ||
      m.awayTeam.toLowerCase().includes(q) ||
      m.league.toLowerCase().includes(q)
    );
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

    // 1. Récupérer depuis l'API les matchs en cours / terminés (source unique)
    const afAll = await apiFootballService.getAllLiveAndRecentFixtures();

    const unified = afAll.map(f => ({
      externalId:  f.fixture.id,
      source:      MatchSource.API_FOOTBALL,
      status:      mapAFStatus(f.fixture.status.short),
      matchDate:   new Date(f.fixture.date),
      homeScore:   f.goals.home ?? null,
      awayScore:   f.goals.away ?? null,
      homeScoreHT: f.score?.halftime.home ?? null,
      awayScoreHT: f.score?.halftime.away ?? null,
    }));

    // 1bis. Filet de sécurité : tout match encore LIVE (ou SCHEDULED depuis
    // trop longtemps) en base, mais absent du scan ci-dessus (hors de la
    // fenêtre des 2 derniers jours — décalage de fuseau horaire, panne
    // ponctuelle...), est revérifié individuellement pour ne jamais rester
    // bloqué "EN DIRECT" indéfiniment.
    // Plafonné et priorisé sur les plus récemment en retard — évite qu'un
    // grand nombre d'amicaux jamais résolus (report indéfini, mauvaise
    // donnée source...) ne consomme le quota API à chaque cycle de sync.
    const staleThreshold = new Date(Date.now() - 3 * 60 * 60 * 1000); // 3h après le coup d'envoi théorique
    const coveredIds = new Set(unified.map(u => u.externalId));
    const stuckMatches = await prisma.match.findMany({
      where: {
        source:    MatchSource.API_FOOTBALL,
        status:    { in: ['LIVE', 'SCHEDULED'] },
        matchDate: { lt: staleThreshold },
      },
      // Les plus anciens en retard d'abord : un tri décroissant laissait le flux
      // continu de matchs tout juste en retard (petites ligues) remplir le
      // plafond à chaque cycle, ce qui empêchait à vie certains matchs bloqués
      // depuis longtemps (ex. un match CL replanifié) d'être jamais retentés.
      orderBy: { matchDate: 'asc' },
      take: 40,
    });
    // Purge les entrées de plus de 24h — la liste de matchs bloqués change en
    // continu, pas besoin de les garder plus longtemps que le throttle lui-même.
    for (const [extId, ts] of staleRetryBackoff) {
      if (Date.now() - ts > 24 * 60 * 60 * 1000) staleRetryBackoff.delete(extId);
    }

    for (const m of stuckMatches) {
      if (coveredIds.has(m.externalId)) continue;
      const lastAttempt = staleRetryBackoff.get(m.externalId);
      if (lastAttempt && Date.now() - lastAttempt < STALE_RETRY_INTERVAL) continue;
      staleRetryBackoff.set(m.externalId, Date.now());

      const fixture = await apiFootballService.getFixtureById(m.externalId);
      if (!fixture) continue;
      unified.push({
        externalId:  fixture.fixture.id,
        source:      MatchSource.API_FOOTBALL,
        status:      mapAFStatus(fixture.fixture.status.short),
        matchDate:   new Date(fixture.fixture.date),
        homeScore:   fixture.goals.home ?? null,
        awayScore:   fixture.goals.away ?? null,
        homeScoreHT: fixture.score?.halftime.home ?? null,
        awayScoreHT: fixture.score?.halftime.away ?? null,
      });
      coveredIds.add(m.externalId);
    }

    if (unified.length === 0) return { updated, resolved };

    // 2. Mettre à jour chaque match en base
    for (const m of unified) {
      const mappedStatus = m.status;
      const homeScore    = m.homeScore;
      const awayScore    = m.awayScore;
      // Ne jamais écraser un score mi-temps déjà connu par un null (l'API ne
      // renvoie plus la mi-temps une fois le match terminé sur certains scans).
      const homeScoreHT  = m.homeScoreHT;
      const awayScoreHT  = m.awayScoreHT;
      const externalKey  = { externalId: m.externalId, source: m.source };

      const match = await prisma.match.findUnique({ where: { externalId_source: externalKey } });
      if (!match) continue;

      const nextHomeScoreHT = homeScoreHT ?? match.homeScoreHT;
      const nextAwayScoreHT = awayScoreHT ?? match.awayScoreHT;
      // La source peut replanifier un match après notre dernier scan (report,
      // correction d'horaire) — on aligne notre date sur la sienne pour ne pas
      // rester bloqué sur une date périmée (ex. recherche de cotes par date).
      const dateChanged = m.matchDate.getTime() !== match.matchDate.getTime();

      const unchanged =
        match.status === mappedStatus &&
        match.homeScore === homeScore &&
        match.awayScore === awayScore &&
        match.homeScoreHT === nextHomeScoreHT &&
        match.awayScoreHT === nextAwayScoreHT &&
        !dateChanged;
      if (unchanged) continue;

      const previousStatus = match.status;

      await prisma.match.update({
        where: { externalId_source: externalKey },
        data:  {
          status:         mappedStatus,
          statusPriority: matchStatusPriority(mappedStatus),
          homeScore, awayScore,
          homeScoreHT: nextHomeScoreHT, awayScoreHT: nextAwayScoreHT,
          matchDate:   m.matchDate,
        },
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
          }, 'match').catch((err: any) => console.error("[PronoSvc]", err.message));
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
            }, 'match').catch((err: any) => console.error("[PronoSvc]", err.message));
          }
        }

        if (prono && prono.isPublished && !prono.result) {
          const result = _resolvePronosticResult(
            prono,
            { home: homeScore, away: awayScore },
            nextHomeScoreHT !== null && nextAwayScoreHT !== null
              ? { home: nextHomeScoreHT, away: nextAwayScoreHT } : null,
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
            const emoji = result === 'WIN' ? '✅' : result === 'PUSH' ? '🔄' : '❌';
            const label = result === 'WIN' ? 'Pronostic gagnant !' : result === 'PUSH' ? 'Pronostic remboursé' : 'Pronostic perdant';
            for (const fav of favorites) {
              notifSvc.sendToUser(fav.userId, {
                title: `${emoji} ${label}`,
                body:  `${match.homeTeam} ${homeScore}-${awayScore} ${match.awayTeam} 路 Prono : ${prono.predictionLabel}`,
                data:  {
                  type:      'prono_result',
                  deep_link: `/pronostics/${prono.id}`,
                  match_id:  match.id,
                },
              }, 'match').catch((err: any) => console.error("[PronoSvc]", err.message));
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
      include: { match: { select: {
        id: true, homeTeam: true, awayTeam: true, homeScore: true, awayScore: true,
        homeScoreHT: true, awayScoreHT: true,
      } } },
    });
    for (const prono of unresolvedPronos) {
      const { homeScore, awayScore, homeScoreHT, awayScoreHT } = prono.match;
      const result = _resolvePronosticResult(
        prono,
        { home: homeScore!, away: awayScore! },
        homeScoreHT !== null && awayScoreHT !== null ? { home: homeScoreHT, away: awayScoreHT } : null,
      );
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
    marketName?:     string;
    marketValue?:    string;
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
      // Uniquement renseigné quand predictionType === 'other' (marché hors des 8 connus)
      marketName:      params.predictionType === 'other' ? (params.marketName  ?? null) : null,
      marketValue:     params.predictionType === 'other' ? (params.marketValue ?? null) : null,
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

    return prisma.$transaction(async (tx) => {
      const pronostic = await tx.pronostic.upsert({
        where:   { matchId: params.matchId },
        update:  { ...data, updatedAt: new Date() },
        create:  data,
        include: { match: true, analyst: { select: { name: true } } },
      });
      // Garder la colonne dénormalisée du match synchronisée (utilisée pour
      // trier "prono d'abord" dans getAllMatches).
      await tx.match.update({
        where: { id: params.matchId },
        data:  { hasPublishedPronostic: params.publish },
      });
      return pronostic;
    });
  }

  // 鈹€鈹€鈹€ ADMIN 鈥?Publier / D茅publier 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async togglePublish(pronosticId: string, publish: boolean) {
    return prisma.$transaction(async (tx) => {
      const pronostic = await tx.pronostic.update({
        where: { id: pronosticId },
        data:  { isPublished: publish, publishedAt: publish ? new Date() : null },
      });
      await tx.match.update({
        where: { id: pronostic.matchId },
        data:  { hasPublishedPronostic: publish },
      });
      return pronostic;
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
    userId?:     string;
    dateFilter?: string;
    sport?:      string;
    leagueCode?: string;
    cursor?:     string;
    limit:       number;
  }) {
    const user = params.userId
      ? await prisma.user.findUnique({ where: { id: params.userId } })
      : null;
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
      // LIVE d'abord — Pronostic→Match est une relation obligatoire (pas de
      // NULL possible ici, contrairement à Match→Pronostic ailleurs dans ce
      // fichier), donc un orderBy relationnel classique suffit.
      orderBy: [
        { match: { statusPriority: 'asc' } },
        { match: { matchDate: 'asc' } },
      ],
      take:    params.limit,
      ...(params.cursor ? { cursor: { id: params.cursor }, skip: 1 } : {}),
    });

    const nextCursor = pronostics.length === params.limit
      ? pronostics[pronostics.length - 1].id
      : null;
    const data = pronostics.map(p => {
      const locked = p.isPremium && !isPremium;
      return {
      id:               p.id,
      // Le mobile (Accueil) s'appuie sur match_id pour le bouton favori —
      // sans ce champ, le bouton ne s'affichait jamais sur les cartes de
      // "Pronostics du jour" (matchId.isNotEmpty toujours faux côté client).
      match_id:         p.matchId,
      league:           p.match.league,
      league_country:   p.match.leagueCode,
      home_team:        p.match.homeTeam,
      away_team:        p.match.awayTeam,
      home_team_logo:   p.match.homeTeamLogo,
      away_team_logo:   p.match.awayTeamLogo,
      match_date:       p.match.matchDate,
      locked,
      status:           p.match.status.toLowerCase() === 'live'     ? 'live'
                      : p.match.status.toLowerCase() === 'finished' ? 'finished'
                      : 'upcoming',
      home_score:       p.match.homeScore,
      away_score:       p.match.awayScore,
      // Le pronostic premium était servi en clair à tout le monde : seule
      // `analyst_note` était masquée. Le mobile floutait la carte côté client,
      // mais un simple appel à /pronostics sans jeton rendait tous les picks
      // payants lisibles. Le masquage doit être fait par le serveur.
      prediction_type:  locked ? null : p.predictionType,
      prediction_label: locked ? null : p.predictionLabel,
      odds_home:        p.oddsHome,
      odds_draw:        p.oddsDraw,
      odds_away:        p.oddsAway,
      odds_recommended: locked ? null : p.oddsRecommended,
      confidence_score: locked ? null : p.confidenceScore,
      is_premium:       p.isPremium,
      analyst_note:     locked ? null : p.analystNote,
      analyst_name:     p.analyst.name,
      result:           p.result,
      home_form_points: p.match.homeFormPoints,
      away_form_points: p.match.awayFormPoints,
      };
    });
    return { data, nextCursor, hasMore: nextCursor !== null };
  }

  // ─── Prono gratuit du jour ────────────────────────────────────────────────────
  async getDailyFreePronostic() {
    const today = new Date();
    const start = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0);
    const end   = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59);

    const prono = await prisma.pronostic.findFirst({
      where: {
        isPublished:  true,
        isDailyFree:  true,
        match: { matchDate: { gte: start, lte: end } },
      },
      include: { match: true, analyst: { select: { name: true } } },
    });

    if (!prono) {
      const fallback = await prisma.pronostic.findFirst({
        where: {
          isPublished: true,
          isPremium:   false,
          match: { matchDate: { gte: start, lte: end } },
        },
        orderBy: { match: { matchDate: 'asc' } },
        include: { match: true, analyst: { select: { name: true } } },
      });
      if (!fallback) return null;
      return this._formatDailyProno(fallback);
    }

    return this._formatDailyProno(prono);
  }

  async setDailyFreePronostic(pronosticId: string) {
    await prisma.pronostic.updateMany({
      where: { isDailyFree: true },
      data:  { isDailyFree: false },
    });
    return prisma.pronostic.update({
      where: { id: pronosticId },
      data:  { isDailyFree: true, isPremium: false },
    });
  }

  private _formatDailyProno(p: any) {
    return {
      id:               p.id,
      league:           p.match.league,
      league_country:   p.match.leagueCode,
      home_team:        p.match.homeTeam,
      away_team:        p.match.awayTeam,
      home_team_logo:   p.match.homeTeamLogo,
      away_team_logo:   p.match.awayTeamLogo,
      match_date:       p.match.matchDate,
      status:           p.match.status.toLowerCase() === 'finished' ? 'finished'
                      : p.match.status.toLowerCase() === 'live'     ? 'live'
                      : 'upcoming',
      home_score:       p.match.homeScore,
      away_score:       p.match.awayScore,
      prediction_type:  p.predictionType,
      prediction_label: p.predictionLabel,
      odds_recommended: p.oddsRecommended,
      odds_home:        p.oddsHome,
      odds_draw:        p.oddsDraw,
      odds_away:        p.oddsAway,
      confidence_score: p.confidenceScore,
      is_premium:       false,
      is_daily_free:    true,
      analyst_note:     p.analystNote,
      analyst_name:     p.analyst.name,
      result:           p.result,
      home_form_points: p.match.homeFormPoints,
      away_form_points: p.match.awayFormPoints,
    };
  }

  // --- Liste blanche de ligues (visibilité publique) --------------------------
  /**
   * Filtre à combiner (AND) avec le where existant des endpoints publics
   * (getAllMatches/getDaySummary/getMatchCountsByDay) : un match reste inclus
   * si sa ligue est dans la liste blanche, OU s'il a lui-même un pronostic
   * publié (décision éditoriale déjà prise par l'admin en le publiant).
   * N'affecte jamais la découverte admin.
   */
  private async _visibleLeaguesFilter(): Promise<Prisma.MatchWhereInput> {
    const rows = await prisma.leagueVisibility.findMany({
      where:  { isVisible: true },
      select: { leagueCode: true },
    });
    return {
      OR: [
        { leagueCode: { in: rows.map(r => r.leagueCode) } },
        { hasPublishedPronostic: true },
      ],
    };
  }

  /** ADMIN — Compétitions vues récemment (60j), fusionnées avec l'état de visibilité configuré. */
  async listLeagueVisibility() {
    const cutoff = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000);
    const [recent, configured] = await Promise.all([
      prisma.match.findMany({
        distinct: ['leagueCode'],
        where:    { matchDate: { gte: cutoff } },
        select:   { leagueCode: true, league: true },
        orderBy:  { matchDate: 'desc' },
      }),
      prisma.leagueVisibility.findMany(),
    ]);

    const visMap = new Map(configured.map(c => [c.leagueCode, c]));
    // Fusionne : une ligue déjà configurée mais sans match dans la fenêtre de
    // 60j (ex. hors saison) ne doit pas disparaître du panneau admin.
    const merged = new Map<string, { leagueCode: string; league: string; isVisible: boolean }>();
    for (const m of recent) {
      merged.set(m.leagueCode, {
        leagueCode: m.leagueCode,
        league:     m.league,
        isVisible:  visMap.get(m.leagueCode)?.isVisible ?? false,
      });
    }
    for (const c of configured) {
      if (!merged.has(c.leagueCode)) {
        merged.set(c.leagueCode, { leagueCode: c.leagueCode, league: c.league, isVisible: c.isVisible });
      }
    }
    return [...merged.values()].sort((a, b) => a.league.localeCompare(b.league));
  }

  /** ADMIN — Active/désactive une ligue dans le flux public. */
  async setLeagueVisibility(leagueCode: string, league: string, isVisible: boolean) {
    return prisma.leagueVisibility.upsert({
      where:  { leagueCode },
      update: { isVisible, league },
      create: { leagueCode, league, isVisible },
    });
  }

  // 鈹€鈹€鈹€ Tous les matchs (avec ou sans pronostic publi茅) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getAllMatches(params: {
    userId?:       string;
    dateFilter?:   string;
    sport?:        string;
    leagueCode?:   string;
    status?:       string; // 'upcoming' | 'live' | 'finished' — filtre serveur, cohérent avec la pagination
    hasPronostic?: boolean; // true = uniquement les matchs avec un pronostic publié par l'admin
    cursor?:       string;
    limit:         number;
  }) {
    const user = params.userId
      ? await prisma.user.findUnique({ where: { id: params.userId } })
      : null;
    const isPremium = user?.subscriptionPlan === 'premium' &&
      (user.subscriptionExpiresAt ? user.subscriptionExpiresAt > new Date() : false);

    const dateWhere = this.buildDateWhere(params.dateFilter);
    const statusWhere = params.status === 'upcoming' ? 'SCHEDULED'
                       : params.status === 'live'     ? 'LIVE'
                       : params.status === 'finished' ? 'FINISHED'
                       : undefined;

    const visibleLeaguesFilter = await this._visibleLeaguesFilter();

    const matches = await prisma.match.findMany({
      where: {
        ...dateWhere,
        ...visibleLeaguesFilter,
        // Exclure les matchs annulés / reportés indéfiniment
        status: statusWhere ?? { notIn: ['POSTPONED', 'SUSPENDED'] },
        ...(params.leagueCode ? { leagueCode: params.leagueCode } : {}),
        ...(params.hasPronostic ? { pronostic: { isPublished: true } } : {}),
      },
      include: {
        pronostic: {
          include: { analyst: { select: { name: true } } },
        },
      },
      // Priorité aux matchs avec un pronostic publié par l'admin (avant ceux
      // encore "en cours d'analyse"), puis par heure de coup d'envoi — pour
      // que ce critère tienne dès la pagination, pas seulement au sein d'une
      // page déjà chargée côté mobile.
      orderBy: [
        { statusPriority: 'asc' },
        { hasPublishedPronostic: 'desc' },
        { matchDate: 'asc' },
      ],
      take:    params.limit,
      ...(params.cursor ? { cursor: { id: params.cursor }, skip: 1 } : {}),
    });

    const nextCursor = matches.length === params.limit
      ? matches[matches.length - 1].id
      : null;
    const data = matches.map(m => {
      const p           = m.pronostic;
      const hasPronostic = !!p && p.isPublished;
      const mLocked      = hasPronostic && p!.isPremium && !isPremium;

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
        // Idem : le pick payant ne doit jamais quitter le serveur pour qui n'y
        // a pas droit.
        locked:           mLocked,
        prediction_type:  hasPronostic && !mLocked ? p!.predictionType.toLowerCase() : null,
        prediction_label: hasPronostic && !mLocked ? p!.predictionLabel              : null,
        odds_home:        hasPronostic ? p!.oddsHome                      : null,
        odds_draw:        hasPronostic ? p!.oddsDraw                      : null,
        odds_away:        hasPronostic ? p!.oddsAway                      : null,
        odds_recommended: hasPronostic && !mLocked ? p!.oddsRecommended   : null,
        confidence_score: hasPronostic && !mLocked ? p!.confidenceScore   : null,
        is_premium:       hasPronostic ? p!.isPremium                     : false,
        analyst_note:     hasPronostic && !mLocked ? p!.analystNote       : null,
        analyst_name:     hasPronostic ? p!.analyst.name                  : null,
        result:           hasPronostic ? p!.result                        : null,
        home_form_points: m.homeFormPoints,
        away_form_points: m.awayFormPoints,
      };
    });
    return { data, nextCursor, hasMore: nextCursor !== null };
  }

  /**
   * Totaux réels pour un jour donné (tous matchs confondus, indépendamment de
   * la pagination) — la barre de stats du jour affichait un compte de
   * pronostics faux car basé sur les seuls matchs déjà chargés (souvent 0 si
   * les premiers matchs du jour, triés par heure, n'ont pas encore de prono).
   */
  async getDaySummary(dateFilter?: string): Promise<{ total: number; withPronostic: number; live: number }> {
    const dateWhere = this.buildDateWhere(dateFilter);
    const visibleLeaguesFilter = await this._visibleLeaguesFilter();
    const baseWhere: Prisma.MatchWhereInput = {
      ...dateWhere, ...visibleLeaguesFilter,
      status: { notIn: ['POSTPONED', 'SUSPENDED'] },
    };

    const [total, withPronostic, live] = await Promise.all([
      prisma.match.count({ where: baseWhere }),
      prisma.match.count({ where: { ...baseWhere, pronostic: { isPublished: true } } }),
      prisma.match.count({ where: { ...dateWhere, ...visibleLeaguesFilter, status: 'LIVE' } }),
    ]);

    return { total, withPronostic, live };
  }

  /**
   * Nombre de matchs par jour sur la fenêtre visible du sélecteur de dates
   * mobile (30 jours passés + 7 à venir) — indépendant de la pagination par
   * jour sélectionné, qui ne renvoie jamais que le jour en cours. Sans ça,
   * les badges du sélecteur de dates ne peuvent afficher un compte correct
   * que pour le jour actuellement sélectionné.
   */
  async getMatchCountsByDay(): Promise<Record<string, number>> {
    const dateWhere = this.buildDateWhere(undefined); // past30 → week (fenêtre par défaut)
    const visibleLeaguesFilter = await this._visibleLeaguesFilter();
    const matches = await prisma.match.findMany({
      where: { ...dateWhere, ...visibleLeaguesFilter, status: { notIn: ['POSTPONED', 'SUSPENDED'] } },
      select: { matchDate: true },
    });

    // Clé YYYY-MM-DD en heure locale serveur — cohérent avec buildDateWhere()
    // ci-dessus, qui construit ses bornes "aujourd'hui"/"jour précis" de la
    // même façon (composants locaux, pas UTC).
    const counts: Record<string, number> = {};
    for (const m of matches) {
      const d   = m.matchDate;
      const key = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
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

    // activeUsers calculé à part (non caché) via /admin/stats/online
    return { totalUsers, premiumUsers, pendingTx, totalPronostics, publishedToday };
  }
}
