import { Prisma, MatchSource, Match } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { ApiFootballService, apiFootballService, mapAFStatus, matchStatusPriority } from './api_football.service';
import { NotificationService } from './notification.service';
import { settleBets } from './bankroll.service';
// Moteur de règlement — extrait dans son propre module pour être testable
// sans base de données (cf. settlement.ts).
import { _resolvePronosticResult, type ScoreLine } from './settlement';

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
  /**
   * Filtre de compétition du panneau admin.
   *
   * La valeur vide signifiait « grandes ligues + amicaux » et il fallait
   * choisir « ALL » pour tout voir — alors que l'appel API ramène de toute
   * façon l'intégralité des matchs (7 requêtes par jour, quel que soit le
   * filtre) et que le tri se fait ensuite en mémoire. Le défaut jetait donc
   * 90 % de ce qui était déjà payé.
   *
   * Désormais : vide (ou 'ALL', conservé pour les liens existants) = tout,
   * 'MAJORS' = les grandes ligues et les amicaux, sinon la ligue demandée.
   */
  private static readonly MAJORS = 'MAJORS';

  /** Nombre maximum de matchs rendus par la liste admin. */
  private static readonly PLAFOND_LISTE = 400;

  /**
   * Ordre d'importance des compétitions dans la vue « Tout ».
   *
   * Triée par date seule, la liste ouvrait sur l'AFC Women's Champions League
   * et la 3. Division norvégienne — ce sont simplement les premiers coups
   * d'envoi de la journée. Les rencontres qu'on pronostique se trouvaient
   * plusieurs centaines de lignes plus bas, hors du plafond d'affichage.
   *
   * Quatre rangs, aucun palmarès inventé dans le code :
   *   1. les compétitions cartographiées (LEAGUE_MAP), dans l'ordre ci-dessous ;
   *   2. celles que l'administrateur a activées dans /admin/leagues — sa
   *      propre déclaration de ce qui compte, qu'il peut changer sans toucher
   *      au code ;
   *   3. les amicaux : ils ont leur place dans le catalogue mais aucun enjeu
   *      sportif, donc derrière tout ce qui a été explicitement retenu ;
   *   4. le reste.
   *
   * À rang égal, l'ordre chronologique reprend la main.
   */
  private static readonly ORDRE_MAJEURES = [
    'WC',        // Coupe du monde
    'CL',        // Ligue des champions
    'PL', 'PD', 'SA', 'BL1', 'FL1',   // les cinq grands championnats
  ];

  private static readonly RANG_ACTIVEE = 100;
  private static readonly RANG_AMICAL  = 150;
  private static readonly RANG_AUTRE   = 200;

  /** Codes des compétitions activées pour le flux public. */
  private async _codesActives(): Promise<Set<string>> {
    try {
      const rows = await prisma.leagueVisibility.findMany({
        where:  { isVisible: true },
        select: { leagueCode: true },
      });
      return new Set(rows.map(r => r.leagueCode));
    } catch {
      return new Set();
    }
  }

  private static _rangLigue(code: string, actives: Set<string>): number {
    const i = PronosticsService.ORDRE_MAJEURES.indexOf(code);
    if (i >= 0) return i;
    if (actives.has(code))    return PronosticsService.RANG_ACTIVEE;
    if (code === 'FRIENDLY')  return PronosticsService.RANG_AMICAL;
    return PronosticsService.RANG_AUTRE;
  }

  /** Clause Prisma correspondant au filtre — pour les vues lues en base. */
  private static _clauseLigue(code?: string): Prisma.MatchWhereInput {
    if (code === PronosticsService.MAJORS) {
      return { leagueCode: { in: ApiFootballService.majorLeagueCodes() } };
    }
    if (code && code !== 'ALL') return { leagueCode: code };
    return {};
  }

  /** Même filtre, en prédicat — pour les fixtures encore en mémoire. */
  private static _gardeLigue(code?: string): (leagueCode: string) => boolean {
    if (code === PronosticsService.MAJORS) {
      const majors = ApiFootballService.majorLeagueCodes();
      return c => majors.includes(c);
    }
    if (code && code !== 'ALL') return c => c === code;
    return () => true;
  }

  async fetchUpcomingMatchesForAdmin(
    competitionCode?: string, search?: string, date?: string,
    mine?: boolean, live?: boolean, limite?: number,
  ) {
    // "Match en direct" → uniquement les matchs actuellement en cours,
    // lecture DB pure (statut tenu à jour par le cron de sync).
    if (live) return this._liveMatches(competitionCode, search, limite);

    // "Mes pronostics" → tous les matchs déjà pronostiqués, toutes dates et
    // tous statuts confondus (y compris terminés). Sans ça, un match qui se
    // termine sort de toutes les vues (l'API ne renvoie que les matchs à
    // venir) et devient introuvable sans deviner sa date exacte.
    if (mine) return this._myPronostics(competitionCode, search, limite);

    // Une date précise → on regarde ce qu'on a déjà en base (passé, en cours
    // ou à venir, terminé y compris) plutôt que d'interroger l'API, qui ne
    // renvoie que les matchs pas-encore-commencés des 7 prochains jours.
    // Couvre le besoin "revoir les pronostics déjà publiés avec leur résultat".
    if (date) return this._matchesForDate(date, competitionCode, search, limite);

    // Source unique : API-Football couvre à la fois les grandes ligues, les
    // amicaux et tout le reste — un seul fetch, filtré ensuite selon le mode
    // demandé (vue par défaut restreinte / une ligue précise / absolument tout).
    const fixtures = await apiFootballService.getAllUpcomingFixtures();

    interface NormalizedMatch {
      external_id:     number;
      source:          MatchSource;
      league:          string;
      league_code:     string;
      league_country:  string | null;
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

    const garde = PronosticsService._gardeLigue(competitionCode);
    const normalized: NormalizedMatch[] = fixtures
      .map(f => ({ ...apiFootballService.formatFixtureForPronostic(f), source: MatchSource.API_FOOTBALL }))
      .filter(data => garde(data.league_code));

    const validMatches = normalized.filter(data => data.home_team && data.away_team);

    // Écriture groupée.
    //
    // Un `upsert` par match, c'était un aller-retour par ligne : acceptable
    // sur la cinquantaine de matchs de la vue restreinte, intenable dès qu'on
    // affiche tout (plusieurs milliers de rencontres à venir). On lit l'existant
    // en une requête, on insère les nouveaux en une seule, et on ne met à jour
    // que les lignes dont le score ou le statut a réellement changé — en
    // pratique une poignée.
    const idsExternes = validMatches.map(d => d.external_id);
    const dejaEnBase  = await prisma.match.findMany({
      where: { externalId: { in: idsExternes }, source: MatchSource.API_FOOTBALL },
    });
    const parId = new Map(dejaEnBase.map(m => [m.externalId, m]));

    const aCreer = validMatches
      .filter(d => !parId.has(d.external_id))
      .map(d => {
        const st = mapAFStatus(d.status);
        return {
          externalId:     d.external_id,
          source:         d.source,
          league:         d.league,
          leagueCode:     d.league_code,
          leagueCountry:  d.league_country ?? null,
          leagueLogo:     d.league_logo ?? null,
          homeTeam:       d.home_team,
          homeTeamFull:   d.home_team_full ?? d.home_team,
          homeTeamLogo:   d.home_team_logo ?? null,
          awayTeam:       d.away_team,
          awayTeamFull:   d.away_team_full ?? d.away_team,
          awayTeamLogo:   d.away_team_logo ?? null,
          matchDate:      new Date(d.match_date),
          status:         st,
          statusPriority: matchStatusPriority(st),
          homeScore:      d.home_score,
          awayScore:      d.away_score,
        };
      });

    if (aCreer.length) {
      // `skipDuplicates` : deux onglets ouverts simultanément insèrent le même
      // match sans que l'un fasse échouer l'autre.
      await prisma.match.createMany({ data: aCreer, skipDuplicates: true });
    }

    const aMettreAJour = validMatches.filter(d => {
      const actuel = parId.get(d.external_id);
      if (!actuel) return false;
      const st = mapAFStatus(d.status);
      return actuel.status    !== st
          || actuel.homeScore !== d.home_score
          || actuel.awayScore !== d.away_score
          || (actuel.leagueCountry == null && d.league_country != null);
    });

    await Promise.all(aMettreAJour.map(d => {
      const st = mapAFStatus(d.status);
      return prisma.match.update({
        where: { externalId_source: { externalId: d.external_id, source: d.source } },
        data: {
          status:         st,
          statusPriority: matchStatusPriority(st),
          homeScore:      d.home_score,
          awayScore:      d.away_score,
          ...(d.league_country ? { leagueCountry: d.league_country } : {}),
        },
      });
    }));

    // Relecture en une requête : les créations n'ont pas rendu leurs lignes.
    const saved = await prisma.match.findMany({
      where: { externalId: { in: idsExternes }, source: MatchSource.API_FOOTBALL },
    });

    // Inclure aussi les matchs LIVE déjà en DB (synchronisés par le cron) —
    // en respectant le même filtre de ligue que la liste principale, sinon
    // un match LIVE d'une ligue exotique fuiterait dans la vue par défaut.
    const savedIds = new Set(saved.map(m => m.id));
    const liveFromDb = await prisma.match.findMany({
      where: {
        status: 'LIVE',
        ...PronosticsService._clauseLigue(competitionCode),
      },
    });
    const liveOnly = liveFromDb.filter(m => !savedIds.has(m.id));

    const allMatches = [...saved, ...liveOnly];
    return this._attachPronosticsAndFilter(allMatches, search, 'asc', limite, true);
  }

  /** Matchs d'une date précise déjà en base (tous statuts confondus) — pour revoir les pronostics passés/terminés. */
  private async _matchesForDate(date: string, competitionCode?: string, search?: string, limite?: number) {
    const dayStart = new Date(`${date}T00:00:00.000Z`);
    const dayEnd   = new Date(`${date}T23:59:59.999Z`);

    const matches = await prisma.match.findMany({
      where: {
        matchDate: { gte: dayStart, lte: dayEnd },
        ...PronosticsService._clauseLigue(competitionCode),
      },
    });

    return this._attachPronosticsAndFilter(matches, search, 'asc', limite);
  }

  /**
   * Uniquement les matchs actuellement en cours — requête DB pure (le statut
   * LIVE est tenu à jour par le cron syncMatchScores, y compris via le filet
   * de sécurité anti-blocage). Même respect du filtre de ligue que les
   * autres vues admin.
   */
  private async _liveMatches(competitionCode?: string, search?: string, limite?: number) {
    const matches = await prisma.match.findMany({
      where: {
        status: 'LIVE',
        ...PronosticsService._clauseLigue(competitionCode),
      },
    });

    return this._attachPronosticsAndFilter(matches, search, 'asc', limite);
  }

  /**
   * Tous les matchs déjà pronostiqués (publiés ou brouillons), toutes dates et
   * tous statuts confondus — requête DB pure, aucun appel API. C'est ici qu'un
   * admin retrouve un match qu'il a pronostiqué même une fois celui-ci terminé
   * et sorti de la fenêtre "7 prochains jours" de l'API.
   */
  private async _myPronostics(competitionCode?: string, search?: string, limite?: number) {
    const matches = await prisma.match.findMany({
      where: {
        pronostic: { isNot: null },
        ...PronosticsService._clauseLigue(competitionCode),
      },
      orderBy: { matchDate: 'desc' },
      take: 200,
    });

    // desc : review des pronostics passés — le plus récent (souvent déjà
    // joué) en premier, plutôt que trié par ancienneté croissante.
    return this._attachPronosticsAndFilter(matches, search, 'desc', limite);
  }

  /** Attache à chaque match les infos du pronostic associé (résultat, cote, confiance...) + filtre texte. */
  private async _attachPronosticsAndFilter(
    matches: Match[], search?: string, sortOrder: 'asc' | 'desc' = 'asc',
    limite?: number, classerParLigue = false,
  ) {
    const matchIds = matches.map(m => m.id);
    const existing = await prisma.pronostic.findMany({
      where:  { matchId: { in: matchIds } },
      select: {
        id: true, matchId: true, isPublished: true, isPremium: true,
        predictionLabel: true, confidenceScore: true, oddsRecommended: true,
        result: true, createdAt: true,
        // Le pronostic « gratuit du jour » : l'administrateur doit voir lequel
        // est en vitrine, sinon il ne peut pas le choisir en connaissance de
        // cause. La colonne existait, elle n'était exposée nulle part.
        isDailyFree: true,
      },
    });
    const pronoMap = new Map(existing.map(p => [p.matchId, p]));

    // Le classement par compétition doit précéder le plafond : trier après
    // aurait seulement réordonné les 400 premiers matchs par date, c'est-à-dire
    // exactement ceux qu'on cherche à ne plus voir en tête.
    const actives = classerParLigue ? await this._codesActives() : new Set<string>();

    const result = matches
      .sort((a, b) => {
        if (classerParLigue) {
          const ra = PronosticsService._rangLigue(a.leagueCode, actives);
          const rb = PronosticsService._rangLigue(b.leagueCode, actives);
          if (ra !== rb) return ra - rb;
        }
        return sortOrder === 'desc'
          ? b.matchDate.getTime() - a.matchDate.getTime()
          : a.matchDate.getTime() - b.matchDate.getTime();
      })
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
            is_daily_free:     prono.isDailyFree,
          } : null,
        };
      });

    const filtres = !search?.trim() ? result : (() => {
      const q = search.trim().toLowerCase();
      return result.filter(m =>
        m.homeTeam.toLowerCase().includes(q) ||
        m.awayTeam.toLowerCase().includes(q) ||
        m.league.toLowerCase().includes(q)
      );
    })();

    // Plafond d'affichage, appliqué seulement si l'appelant en demande un.
    //
    // Avec « Tout » par défaut, la fenêtre de 7 jours dépasse le millier de
    // rencontres : la page de liste en demande 400. L'export CSV et la
    // recherche globale, eux, n'en passent aucun — les plafonner aurait
    // tronqué un export en silence, exactement ce qu'on veut éviter.
    //
    // Le total réel voyage à part : posé sur un tableau, il disparaîtrait à la
    // sérialisation JSON.
    return {
      items: limite && filtres.length > limite ? filtres.slice(0, limite) : filtres,
      total: filtres.length,
    };
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
      elapsed:     f.fixture.status.elapsed ?? null,
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
        elapsed:     fixture.fixture.status.elapsed ?? null,
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
      // La minute n'a de sens que pendant le match : on la remet à null dès
      // qu'il est terminé, sinon un match fini resterait figé « 90' ».
      const elapsed      = mappedStatus === 'LIVE' ? m.elapsed : null;
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
        // La minute change à chaque cycle sur un direct : sans elle dans la
        // comparaison, le raccourci « rien n'a changé » aurait gelé le
        // chronomètre tant que le score restait identique.
        match.elapsedMinutes === elapsed &&
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
          elapsedMinutes: elapsed,
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
  /**
   * Fenêtre de dates d'une requête.
   *
   * `tzOffsetMin` est le décalage du **client**, tel que le renvoie
   * `DateTime.now().timeZoneOffset.inMinutes` côté Flutter (60 pour UTC+1).
   * Sans lui, le serveur découpait les journées dans *son* fuseau et le mobile
   * dans celui de l'appareil : un match à 00h30 heure locale se retrouvait
   * compté la veille par le serveur et le jour même par l'application. C'est
   * ce qui faisait diverger le compteur du bandeau et le nombre de cartes
   * réellement affichées dans la section « En direct ».
   *
   * Absent, on retombe sur l'ancien comportement — le fuseau du serveur — pour
   * ne pas casser les appels qui ne le transmettent pas encore.
   */
  private buildDateWhere(dateFilter?: string, tzOffsetMin?: number): Prisma.MatchWhereInput {
    const decalage = Number.isFinite(tzOffsetMin as number)
      ? (tzOffsetMin as number) * 60000
      : null;

    /** Minuit du jour de l'utilisateur contenant `instant`, exprimé en UTC. */
    const minuitLocal = (instant: Date): Date => {
      if (decalage === null) {
        return new Date(instant.getFullYear(), instant.getMonth(), instant.getDate());
      }
      const local = new Date(instant.getTime() + decalage);
      const jour  = Date.UTC(
        local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate());
      return new Date(jour - decalage);
    };

    const now      = new Date();
    const today    = minuitLocal(now);
    const tomorrow = new Date(today.getTime() + 86400000);
    const week     = new Date(today.getTime() + 7 * 86400000);
    const past30   = new Date(today.getTime() - 30 * 86400000);

    const yesterday = new Date(today.getTime() - 86400000);

    if (dateFilter === 'yesterday') return { matchDate: { gte: yesterday, lt: today } };
    if (dateFilter === 'today')    return { matchDate: { gte: today,    lt: tomorrow } };
    if (dateFilter === 'tomorrow') return { matchDate: { gte: tomorrow, lt: new Date(tomorrow.getTime() + 86400000) } };
    if (dateFilter === 'past30')   return { matchDate: { gte: past30,   lt: tomorrow } };
    if (dateFilter === 'week')     return { matchDate: { gte: today,    lt: week } };

    // Format YYYY-MM-DD — jour spécifique, lui aussi dans le fuseau du client.
    if (dateFilter && /^\d{4}-\d{2}-\d{2}$/.test(dateFilter)) {
      const d = decalage === null
        ? new Date(dateFilter + 'T00:00:00')
        : new Date(new Date(dateFilter + 'T00:00:00.000Z').getTime() - decalage);
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
    /** Décalage UTC du client en minutes — voir buildDateWhere(). */
    tzOffsetMin?: number;
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

    const dateWhere = this.buildDateWhere(params.dateFilter, params.tzOffsetMin);

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
      // Minute de jeu, null hors direct.
      elapsed:          p.match.elapsedMinutes,
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
      // Minute de jeu, null hors direct.
      elapsed:          p.match.elapsedMinutes,
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

  /**
   * ADMIN — Compétitions vues récemment (60j), fusionnées avec l'état de
   * visibilité configuré.
   *
   * Le panneau admin liste plusieurs centaines de compétitions ; le nom seul
   * ne permet pas de décider laquelle mérite d'être publiée. On joint donc le
   * volume de matchs sur la fenêtre et le nombre de rencontres encore à venir
   * — une ligue à fort historique mais sans match futur est hors saison, et
   * l'activer n'apporterait rien au flux.
   */
  async listLeagueVisibility() {
    const now    = new Date();
    const cutoff = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000);

    const [recent, configured, totals, upcoming] = await Promise.all([
      prisma.match.findMany({
        distinct: ['leagueCode'],
        where:    { matchDate: { gte: cutoff } },
        // Trié du plus récent au plus ancien : `distinct` conserve la première
        // ligne rencontrée, donc le logo et le libellé les plus à jour.
        select:   { leagueCode: true, league: true, leagueLogo: true, leagueCountry: true },
        orderBy:  { matchDate: 'desc' },
      }),
      prisma.leagueVisibility.findMany(),
      prisma.match.groupBy({
        by:     ['leagueCode'],
        where:  { matchDate: { gte: cutoff } },
        _count: { _all: true },
      }),
      prisma.match.groupBy({
        by:     ['leagueCode'],
        where:  { matchDate: { gte: now } },
        _count: { _all: true },
      }),
    ]);

    const visMap   = new Map(configured.map(c => [c.leagueCode, c]));
    const totalMap = new Map(totals.map(t   => [t.leagueCode, t._count._all]));
    const nextMap  = new Map(upcoming.map(u => [u.leagueCode, u._count._all]));

    type Row = {
      leagueCode: string; league: string; leagueLogo: string | null;
      leagueCountry: string | null;
      isVisible: boolean; matchCount: number; upcomingCount: number;
    };

    // Fusionne : une ligue déjà configurée mais sans match dans la fenêtre de
    // 60j (ex. hors saison) ne doit pas disparaître du panneau admin.
    const merged = new Map<string, Row>();
    for (const m of recent) {
      merged.set(m.leagueCode, {
        leagueCode:    m.leagueCode,
        league:        m.league,
        leagueCountry: m.leagueCountry ?? null,
        leagueLogo:    m.leagueLogo ?? null,
        isVisible:     visMap.get(m.leagueCode)?.isVisible ?? false,
        matchCount:    totalMap.get(m.leagueCode) ?? 0,
        upcomingCount: nextMap.get(m.leagueCode)  ?? 0,
      });
    }
    for (const c of configured) {
      if (!merged.has(c.leagueCode)) {
        merged.set(c.leagueCode, {
          leagueCode:    c.leagueCode,
          league:        c.league,
          leagueCountry: null,
          leagueLogo:    null,
          isVisible:     c.isVisible,
          matchCount:    totalMap.get(c.leagueCode) ?? 0,
          upcomingCount: nextMap.get(c.leagueCode)  ?? 0,
        });
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

  /**
   * ADMIN — Même bascule, appliquée à un lot de compétitions.
   *
   * Ouvrir le flux à une vingtaine de ligues se faisait bascule par bascule,
   * soit autant d'allers-retours HTTP. La transaction garantit en plus qu'on
   * ne se retrouve pas avec une sélection à moitié appliquée.
   */
  async setLeagueVisibilityBulk(
    items: { leagueCode: string; league: string }[],
    isVisible: boolean,
  ) {
    // Dédoublonne : deux entrées sur le même code feraient échouer la
    // transaction (deux écritures concurrentes sur la même clé primaire).
    const uniq = new Map(items
      .filter(i => typeof i?.leagueCode === 'string' && i.leagueCode.trim())
      .map(i => [i.leagueCode, { leagueCode: i.leagueCode, league: String(i.league ?? i.leagueCode) }]));

    if (uniq.size === 0) throw new Error('Aucune compétition valide fournie.');

    await prisma.$transaction([...uniq.values()].map(({ leagueCode, league }) =>
      prisma.leagueVisibility.upsert({
        where:  { leagueCode },
        update: { isVisible, league },
        create: { leagueCode, league, isVisible },
      })));

    return { updated: uniq.size, isVisible };
  }

  // 鈹€鈹€鈹€ Tous les matchs (avec ou sans pronostic publi茅) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  async getAllMatches(params: {
    userId?:       string;
    dateFilter?:   string;
    /** Décalage UTC du client en minutes — voir buildDateWhere(). */
    tzOffsetMin?:  number;
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

    const dateWhere = this.buildDateWhere(params.dateFilter, params.tzOffsetMin);
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
  async getDaySummary(
    dateFilter?: string,
    tzOffsetMin?: number,
  ): Promise<{ total: number; withPronostic: number; live: number }> {
    const dateWhere = this.buildDateWhere(dateFilter, tzOffsetMin);
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
    // Vitrine gratuite du jour : le tableau de bord doit pouvoir signaler
    // qu'aucune n'est designee — l'application retombe alors sur un tri, et
    // c'est lui qui decide de ce que voient les visiteurs non abonnes.
    const debutJour = new Date(new Date().setHours(0, 0, 0, 0));
    const finJour   = new Date(new Date().setHours(23, 59, 59, 999));
    const vitrineDuJour = await prisma.pronostic.count({
      where: {
        isPublished: true, isDailyFree: true,
        match: { matchDate: { gte: debutJour, lte: finJour } },
      },
    });
    const publiablesAujourdhui = await prisma.pronostic.count({
      where: { isPublished: true, match: { matchDate: { gte: debutJour, lte: finJour } } },
    });

    return { totalUsers, premiumUsers, pendingTx, totalPronostics, publishedToday,
             vitrineDuJour, publiablesAujourdhui };
  }
}
