import axios, { AxiosError, AxiosInstance } from 'axios';
import type { H2HResult, H2HMatch } from './football_data.service';
import { ApiFootballInsights } from './api_football_insights.service';
import { zoneDepuisDescription } from './zones_classement';
import { traduireAbsence, estSuspension } from './traduction_absences';

// Mapping Football-Data.org codes → API-Football league IDs + saison de repli.
//
// ⚠️ `season` n'est PLUS la source de vérité — c'est un simple filet. La saison
// réellement en cours est demandée à l'API (`saisonCourante()` ci-dessous), et
// ces valeurs ne servent que si cette requête échoue.
//
// Pourquoi ce changement : ces nombres devaient être incrémentés à la main
// chaque mois d'août. Personne ne l'a fait, et la panne est muette — l'écran
// affiche un classement parfaitement formé, celui de la saison précédente.
// C'est ainsi qu'en août 2026 les six championnats servaient encore la table
// finale de 2025-2026, avec 38 journées jouées pour un match de 1re journée.
//
// season = année de DÉBUT de la saison (2026 = saison 2026-2027).
const LEAGUE_MAP: Record<string, { id: number; season: number }> = {
  WC:       { id: 1,   season: 2026 },
  PL:       { id: 39,  season: 2026 },
  BL1:      { id: 78,  season: 2026 },
  SA:       { id: 135, season: 2026 },
  PD:       { id: 140, season: 2026 },
  FL1:      { id: 61,  season: 2026 },
  CL:       { id: 2,   season: 2026 },
  // "World - Friendlies" — absent de football-data.org, disponible uniquement
  // via API-Football. Season = année civile en cours (convention API-Football
  // pour les compétitions sans saison fixe).
  FRIENDLY: { id: 10,  season: new Date().getFullYear() },
};

/**
 * Identifiant et saison API-Football d'un code de compétition interne.
 *
 * `LEAGUE_MAP` est privé au module ; ce lecteur l'expose sans rendre la table
 * modifiable de l'extérieur.
 */
export const LEAGUE_INFO = (code: string): { id: number; season: number } | null =>
  LEAGUE_MAP[code] ?? null;

// ─── Saison courante, demandée à l'API plutôt que devinée ────────────────────

const saisonCache = new Map<string, { annee: number; ts: number }>();
// Une saison change une fois par an : 24 h de cache coûtent 7 requêtes par jour
// sur un quota de 7 500, et suppriment une corvée annuelle.
const SAISON_CACHE_TTL = 24 * 60 * 60 * 1000;

/**
 * Année de la saison en cours pour une compétition, telle que l'API la déclare.
 *
 * `GET /leagues?id=<id>` renvoie toutes les saisons connues, dont une seule
 * porte `current: true`. C'est la seule réponse fiable : une heuristique sur le
 * calendrier (« après juillet, saison = année en cours ») se tromperait sur les
 * compétitions à cheval, sur celles qui suivent l'année civile, et sur la Coupe
 * du Monde.
 *
 * En cas d'échec, on retombe sur la valeur de `LEAGUE_MAP` — mieux vaut un
 * classement possiblement daté qu'un onglet vide — mais l'échec est journalisé,
 * car c'est exactement la situation qui a produit le défaut d'origine.
 */
export async function saisonCourante(leagueCode: string): Promise<number | null> {
  const league = LEAGUE_MAP[leagueCode];
  if (!league) return null;

  const cached = saisonCache.get(leagueCode);
  if (cached && Date.now() - cached.ts < SAISON_CACHE_TTL) return cached.annee;

  try {
    const r = await apiFootballService.httpClient.get('/leagues', {
      params: { id: league.id },
    });
    const saisons: any[] = r.data?.response?.[0]?.seasons ?? [];
    const courante = saisons.find(s => s?.current === true)?.year;

    if (typeof courante === 'number') {
      if (courante !== league.season) {
        console.info(
          `[ApiFootball] ${leagueCode} : saison courante ${courante} ` +
          `(repli codé en dur : ${league.season}).`);
      }
      saisonCache.set(leagueCode, { annee: courante, ts: Date.now() });
      return courante;
    }
    console.warn(`[ApiFootball] ${leagueCode} : aucune saison « current » renvoyée.`);
  } catch (err) {
    const e = err as AxiosError;
    console.warn(`[ApiFootball] ${leagueCode} : saison courante illisible —`,
                 (e.response?.data as any) ?? e.message);
  }
  return league.season;
}

/** Noms lisibles des compétitions suivies par défaut (dropdown admin/mobile). */
const LEAGUE_NAMES: Record<string, string> = {
  WC:       'Coupe du Monde',
  PL:       'Premier League',
  BL1:      'Bundesliga',
  SA:       'Serie A',
  PD:       'La Liga',
  FL1:      'Ligue 1',
  CL:       'Champions League',
  FRIENDLY: 'Matchs amicaux',
};

// ─── Amicaux (fixtures) ─────────────────────────────────────────────────────

export interface AFFixture {
  // `elapsed` : minute de jeu, renvoyée uniquement pendant un match en cours.
  // C'est l'information n°1 d'un direct — un 0-0 à la 10e et un 0-0 à la 85e
  // ne valent pas la même chose pour un parieur.
  fixture: { id: number; date: string; status: { short: string; elapsed?: number | null } };
  league:  { id: number; name: string; logo: string | null; country?: string | null };
  teams: {
    home: { id: number; name: string; logo: string | null };
    away: { id: number; name: string; logo: string | null };
  };
  goals: { home: number | null; away: number | null };
  // Score à la mi-temps — nécessaire pour régler les marchés "1ère/2ème MT"
  // (Vainqueur 1ère MT, HT/FT, Handicap/Total par mi-temps...). Absent tant
  // que la mi-temps n'a pas été atteinte.
  score?: { halftime: { home: number | null; away: number | null } };
}

/** Statuts courts API-Football → statut interne unifié avec mapFDStatus(). */
export function mapAFStatus(afStatus: string): 'SCHEDULED' | 'LIVE' | 'FINISHED' | 'POSTPONED' | 'SUSPENDED' {
  switch (afStatus) {
    case 'TBD':
    case 'NS':                        return 'SCHEDULED';
    case '1H': case 'HT': case '2H':
    case 'ET': case 'BT': case 'P':
    case 'INT':                       return 'LIVE';
    case 'FT': case 'AET': case 'PEN':
    case 'AWD': case 'WO':            return 'FINISHED';
    case 'PST':                       return 'POSTPONED';
    case 'SUSP': case 'CANC': case 'ABD': return 'SUSPENDED';
    default:                          return 'SCHEDULED';
  }
}

/**
 * Rang de tri dénormalisé (Match.statusPriority) — LIVE avant SCHEDULED avant
 * FINISHED, pour que la pagination `getAllMatches` fasse remonter les matchs
 * en direct tôt même quand ils ne sont pas les premiers par heure de coup
 * d'envoi (un match LIVE parmi 300 matchs du jour peut sinon rester hors des
 * premières pages tant que l'utilisateur n'a pas beaucoup scrollé).
 */
export function matchStatusPriority(
  status: 'SCHEDULED' | 'LIVE' | 'FINISHED' | 'POSTPONED' | 'SUSPENDED',
): number {
  switch (status) {
    case 'LIVE':      return 0;
    case 'SCHEDULED': return 1;
    case 'FINISHED':  return 2;
    default:          return 3;
  }
}

export interface MatchEvent {
  minute:   number;
  extra:    number | null;
  team:     string;
  player:   string;
  assist:   string | null;
  type:     'Goal' | 'Card' | 'subst' | string;
  detail:   string; // 'Normal Goal', 'Yellow Card', 'Red Card', etc.
}

export interface MatchStat {
  label: string;
  home:  string | number | null;
  away:  string | number | null;
}

export interface MatchStatsResult {
  fixture_id: number;
  events:     MatchEvent[];
  stats:      MatchStat[];
  home_team:  string;
  away_team:  string;
}

// Cache simple en mémoire — les stats d'un match terminé ne changent plus
const statsCache = new Map<string, { data: MatchStatsResult; ts: number }>();
const CACHE_TTL = 24 * 60 * 60 * 1000; // 24h pour les matchs terminés

// Cache des fixtures par date — partagé par la découverte de matchs ET la sync
// des scores en direct. TTL calé juste sous l'intervalle de sync live (30s,
// cf. index.ts) : un TTL plus long annulerait le bénéfice de l'intervalle
// resserré en resservant la même donnée déjà vue à chaque tick.
const friendliesCache = new Map<string, { data: AFFixture[]; ts: number }>();
const FRIENDLIES_CACHE_TTL = 25 * 1000; // 25 secondes

// ─── Compositions d'équipe ──────────────────────────────────────────────────

export interface LineupPlayer {
  id:     number | null; // photo : https://media.api-sports.io/football/players/{id}.png
  name:   string;
  number: number | null;
  pos:    string | null; // G, D, M, F
  /** Position sur le terrain, "ligne:colonne" (ex. "1:1" gardien, "2:3"). null
   *  pour les remplaçants, que l'API ne place pas. */
  grid:   string | null;
}

export interface TeamLineup {
  formation:   string | null;
  coach:       string | null;
  /// Photo de l entraineur, fournie a cote de son nom dans la meme reponse.
  coachPhoto:  string | null;
  startXI:     LineupPlayer[];
  substitutes: LineupPlayer[];
}

export interface LineupsResult {
  /** false tant que les clubs n'ont pas encore publié leurs compositions. */
  available: boolean;
  home: TeamLineup | null;
  away: TeamLineup | null;
}

// Compositions publiées peu avant le coup d'envoi — cache court pour rester à jour.
const lineupsCache = new Map<string, { data: LineupsResult; ts: number }>();
const LINEUPS_CACHE_TTL = 2 * 60 * 1000; // 2 minutes

// ─── Blessures / suspensions ────────────────────────────────────────────────

export interface InjuredPlayer {
  name:   string;
  team:   'home' | 'away';
  type:   string; // "Injured", "Suspended", "Missing Fixture"...
  /// Motif **deja traduit** : l ecran n a plus a connaitre l anglais.
  reason: string;
  /// Photo du joueur, fournie dans la meme reponse et jamais lue.
  photo:  string | null;
  /// Suspension (carton) plutot qu indisponibilite physique — l icone change.
  suspension: boolean;
}

const injuriesCache = new Map<string, { data: InjuredPlayer[]; ts: number }>();
const INJURIES_CACHE_TTL = 30 * 60 * 1000; // 30 minutes — évolue peu dans la journée

// ─── Cotes (1xBet) ───────────────────────────────────────────────────────────

/** ID bookmaker "1xBet" sur API-Football — cf. GET /odds/bookmakers. */
const XBET_BOOKMAKER_ID = 11;

export type KnownPredictionType =
  'win1' | 'draw' | 'win2' | 'btts' | 'over25' | 'under25' | 'over35' | 'under35';

export interface OddsOption {
  type:  KnownPredictionType;
  label: string;
  odd:   number;
}

export interface OddsMarketValue {
  value: string;                  // valeur brute 1xBet, ex. "Home +0"
  odd:   number;
  type?: KnownPredictionType;      // renseigné si cette valeur correspond à un des 8 types connus
}

export interface OddsMarket {
  name:   string;                 // marché brut 1xBet, ex. "Asian Handicap"
  values: OddsMarketValue[];
}

export interface MatchOddsResult {
  source:  string;         // '1xBet'
  options: OddsOption[];   // raccourci vers les 8 types connus — alimente les pills rapides
  markets: OddsMarket[];   // les ~31 marchés bruts (tous, y compris les 8 ci-dessus)
}

// (marché, valeur) 1xBet → type de pronostic interne connu, pour les marchés
// que l'app sait exploiter nativement (auto-calcul WIN/LOSS inclus).
const KNOWN_TYPE_MAP: Record<string, Record<string, KnownPredictionType>> = {
  'Match Winner':       { Home: 'win1', Draw: 'draw', Away: 'win2' },
  'Both Teams Score':   { Yes: 'btts' },
  'Goals Over/Under':   { 'Over 2.5': 'over25', 'Under 2.5': 'under25', 'Over 3.5': 'over35', 'Under 3.5': 'under35' },
};

// Les cotes évoluent en continu jusqu'au coup d'envoi — cache court.
const oddsCache = new Map<string, { data: MatchOddsResult; ts: number }>();
const ODDS_CACHE_TTL = 5 * 60 * 1000; // 5 minutes

// ─── Classement ──────────────────────────────────────────────────────────────

export interface StandingRow {
  rank:        number;
  teamName:    string;
  teamLogo:    string | null;
  played:      number;
  win:         number;
  draw:        number;
  lose:        number;
  goalsDiff:   number;
  points:      number;
  form:        string | null; // ex. "WWDLW"
  /// Zone de qualification ou de relegation, traduite. `null` si aucune.
  zone:        string | null;
  /// Nature de la zone, pour la couleur : c1, c3, c4, barrage, promotion,
  /// relegation. Separee du libelle : une couleur ne doit pas dependre d une
  /// chaine de caracteres.
  zoneNature:  string | null;
}

const standingsCache = new Map<string, { data: StandingRow[]; ts: number }>();
const STANDINGS_CACHE_TTL = 2 * 60 * 60 * 1000; // 2h — un classement ne bouge pas vite, mais autant refléter les matchs de la journée assez tôt

export class ApiFootballService {
  private client: AxiosInstance;

  /** Exposé pour `ApiFootballInsights`, qui partage la même clé et le même quota. */
  get httpClient(): AxiosInstance { return this.client; }
  get hasApiKey(): boolean { return this._hasKey(); }

  constructor() {
    this.client = axios.create({
      baseURL: 'https://v3.football.api-sports.io',
      headers: {
        'x-apisports-key': process.env.API_FOOTBALL_KEY ?? '',
      },
      timeout: 10000,
    });
  }

  private static _normalizeTeamName(s: string): string {
    return s.toLowerCase()
      .replace(/[.\-_]/g, ' ')           // Bosnia-H. → bosnia h
      .replace(/\s+/g, ' ').trim();
  }

  /** Recherche souple d'une fixture par équipes + date (fonctionne sur toutes les ligues, plan gratuit inclus). */
  private async _findFixtureByTeams(homeTeam: string, awayTeam: string, matchDate: string): Promise<any | null> {
    const fixtureRes = await this.client.get('/fixtures', { params: { date: matchDate } });
    const fixtures: any[] = fixtureRes.data?.response ?? [];

    const h = ApiFootballService._normalizeTeamName(homeTeam);
    const a = ApiFootballService._normalizeTeamName(awayTeam);
    const matchTeam = (api: string, db: string) =>
      api.includes(db) || db.includes(api) ||
      api.startsWith(db.split(' ')[0]) || db.startsWith(api.split(' ')[0]);

    return fixtures.find(f => {
      const home = ApiFootballService._normalizeTeamName(f.teams?.home?.name ?? '');
      const away = ApiFootballService._normalizeTeamName(f.teams?.away?.name ?? '');
      return matchTeam(home, h) && matchTeam(away, a);
    }) ?? null;
  }

  async getMatchStats(
    leagueCode: string,
    homeTeam: string,
    awayTeam: string,
    matchDate: string, // YYYY-MM-DD
  ): Promise<MatchStatsResult | null> {
    const cacheKey = `${leagueCode}_${homeTeam}_${awayTeam}_${matchDate}`;
    const cached = statsCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < CACHE_TTL) return cached.data;

    if (!this._hasKey()) {
      console.warn('[ApiFootball] Clé API_FOOTBALL_KEY manquante dans .env');
      return null;
    }

    try {
      // On cherche par date uniquement (league+season filtre trop sur le plan gratuit) —
      // fonctionne pour n'importe quelle ligue, pas besoin de la connaître à l'avance.
      const fixture = await this._findFixtureByTeams(homeTeam, awayTeam, matchDate);
      if (!fixture) return null;

      const fixtureId = fixture.fixture?.id;

      // 2 — Récupérer events + stats en parallèle
      const [eventsRes, statsRes] = await Promise.all([
        this.client.get('/fixtures/events',     { params: { fixture: fixtureId } }),
        this.client.get('/fixtures/statistics', { params: { fixture: fixtureId } }),
      ]);

      // Parser les événements
      const rawEvents: any[] = eventsRes.data?.response ?? [];
      const events: MatchEvent[] = rawEvents.map(e => ({
        minute: e.time?.elapsed ?? 0,
        extra:  e.time?.extra   ?? null,
        team:   e.team?.name    ?? '',
        player: e.player?.name  ?? '',
        assist: e.assist?.name  ?? null,
        type:   e.type   ?? '',
        detail: e.detail ?? '',
      }));

      // Parser les statistiques
      const rawStats: any[] = statsRes.data?.response ?? [];
      const homeStats = rawStats[0]?.statistics ?? [];
      const awayStats = rawStats[1]?.statistics ?? [];
      const stats: MatchStat[] = homeStats.map((s: any, i: number) => ({
        label: s.type,
        home:  s.value,
        away:  awayStats[i]?.value ?? null,
      }));

      const result: MatchStatsResult = {
        fixture_id: fixtureId,
        events,
        stats,
        home_team: fixture.teams?.home?.name ?? homeTeam,
        away_team: fixture.teams?.away?.name ?? awayTeam,
      };

      statsCache.set(cacheKey, { data: result, ts: Date.now() });
      return result;

    } catch (err: any) {
      console.error('[ApiFootball] Erreur:', err.response?.data ?? err.message);
      return null;
    }
  }

  // ── Amicaux ("World - Friendlies", league id 10) ───────────────────────────

  private _hasKey(): boolean {
    return !!process.env.API_FOOTBALL_KEY && process.env.API_FOOTBALL_KEY !== 'VOTRE_CLE_ICI';
  }

  /**
   * Récupère TOUTES les fixtures d'un jour donné, toutes ligues confondues
   * (le filtrage — amicaux seuls, toutes ligues, etc. — se fait à l'appelant).
   *
   * ⚠️ Ne JAMAIS combiner `league` + `season` dans les params de `/fixtures` :
   * le plan gratuit API-Football renvoie une erreur ("Free plans do not have
   * access to this season") dès qu'on filtre par saison courante — seule la
   * recherche par `date` seule fonctionne sur le plan gratuit (même
   * contournement déjà utilisé dans getMatchStats()).
   */
  private async _fetchFixturesByDate(date: string): Promise<AFFixture[]> {
    const cacheKey = `date_${date}`;
    const cached = friendliesCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < FRIENDLIES_CACHE_TTL) return cached.data;

    const r = await this.client.get('/fixtures', { params: { date } });
    const all: AFFixture[] = r.data?.response ?? [];

    friendliesCache.set(cacheKey, { data: all, ts: Date.now() });
    return all;
  }

  /** Boucle sur une plage de jours, fixture-par-fixture, en tolérant les erreurs/rate-limit. */
  private async _fetchFixturesOverDays(days: string[]): Promise<AFFixture[]> {
    const all: AFFixture[] = [];
    for (const day of days) {
      try {
        all.push(...await this._fetchFixturesByDate(day));
      } catch (err) {
        const e = err as AxiosError;
        if (e.response?.status === 429) {
          console.warn('[ApiFootball] Rate limit atteint');
          break;
        }
        console.error(`[ApiFootball] Erreur fixtures ${day}:`, (e.response?.data as any) ?? e.message);
      }
    }
    return all;
  }

  private static _upcomingDays(): string[] {
    const fmt = (d: Date) => d.toISOString().split('T')[0];
    return Array.from({ length: 7 }, (_, i) => fmt(new Date(Date.now() + i * 86400000)));
  }

  private static _recentDays(): string[] {
    const fmt = (d: Date) => d.toISOString().split('T')[0];
    return [fmt(new Date(Date.now() - 86400000)), fmt(new Date())];
  }

  /**
   * Tous les matchs à venir (7 prochains jours) + ceux déjà en direct,
   * absolument toutes compétitions confondues (grandes ligues, amicaux,
   * tout le reste) — source unique désormais qu'API-Football remplace
   * football-data.org. Le tri par ligue (majors / amicaux / tout) se fait
   * chez l'appelant.
   *
   * Inclure les matchs LIVE ici (pas seulement via le merge liveFromDb côté
   * admin) est nécessaire pour qu'un match déjà en direct au tout premier
   * scan (jamais vu en NS avant) entre quand même en base et devienne
   * sélectionnable pour créer un pronostic.
   */
  async getAllUpcomingFixtures(): Promise<AFFixture[]> {
    if (!this._hasKey()) return [];
    const fixtures = await this._fetchFixturesOverDays(ApiFootballService._upcomingDays());
    return fixtures.filter(f => {
      const s = f.fixture.status.short;
      return s === 'NS' || mapAFStatus(s) === 'LIVE';
    });
  }

  /**
   * Recherche ciblée d'une fixture précise par son id — utilisé en filet de
   * sécurité pour les matchs restés bloqués LIVE/SCHEDULED en base au-delà de
   * la fenêtre de scan habituelle (2 derniers jours), plutôt que de rescanner
   * toutes les fixtures par date.
   */
  async getFixtureById(fixtureId: number): Promise<AFFixture | null> {
    if (!this._hasKey()) return null;
    try {
      const r = await this.client.get('/fixtures', { params: { id: fixtureId } });
      return (r.data?.response ?? [])[0] ?? null;
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur getFixtureById:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }

  /** Équivalent live/récent de getAllUpcomingFixtures(), pour la sync des scores. */
  async getAllLiveAndRecentFixtures(): Promise<AFFixture[]> {
    if (!this._hasKey()) return [];
    const fixtures = await this._fetchFixturesOverDays(ApiFootballService._recentDays());
    return fixtures.filter(f => mapAFStatus(f.fixture.status.short) !== 'SCHEDULED');
  }

  /** Codes courts (WC, PL, ...) des grandes ligues suivies + amicaux — pour le filtre "vue par défaut". */
  static majorLeagueCodes(): string[] {
    return Object.keys(LEAGUE_MAP);
  }

  /** Liste { code, name } des compétitions suivies — pour le filtre mobile/admin. */
  async getCompetitions() {
    return Object.entries(LEAGUE_NAMES).map(([code, name]) => ({ code, name }));
  }

  /** Retrouve le code court (WC, PL, FRIENDLY...) correspondant à un id de ligue API-Football. */
  private static _leagueCodeFor(leagueId: number): string | null {
    const entry = Object.entries(LEAGUE_MAP).find(([, v]) => v.id === leagueId);
    return entry ? entry[0] : null;
  }

  /** Normalise une fixture API-Football au même format que FootballDataService.formatForPronostic(). */
  formatFixtureForPronostic(f: AFFixture) {
    return {
      external_id:    f.fixture.id,
      league:         f.league.name,
      // Code court réutilisé pour les ligues connues (WC, PL, SA...) — garde
      // le filtre admin/mobile fonctionnel quel que soit le fournisseur.
      // Sinon un code dérivé de l'id API-Football pour tout le reste.
      league_code:    ApiFootballService._leagueCodeFor(f.league.id) ?? `AF_${f.league.id}`,
      league_logo:    f.league.logo,
      league_country: f.league.country ?? null,
      home_team:      f.teams.home.name,
      home_team_full: f.teams.home.name,
      home_team_logo: f.teams.home.logo,
      away_team:      f.teams.away.name,
      away_team_full: f.teams.away.name,
      away_team_logo: f.teams.away.logo,
      match_date:     f.fixture.date,
      status:         f.fixture.status.short,
      home_score:     f.goals.home,
      away_score:     f.goals.away,
    };
  }

  // ── Head-to-head ─────────────────────────────────────────────────────────

  /**
   * Historique des confrontations directes entre les deux équipes d'un match.
   * API-Football identifie les équipes par ID (pas par nom) — on retrouve
   * d'abord la fixture du match courant (recherche par date + noms, comme
   * getMatchStats) pour en extraire les IDs d'équipe, puis on interroge
   * /fixtures/headtohead.
   */
  async getH2H(
    homeTeam: string,
    awayTeam: string,
    matchDate: string, // YYYY-MM-DD
    limit = 10,
  ): Promise<H2HResult | null> {
    if (!this._hasKey()) return null;

    try {
      const fixture = await this._findFixtureByTeams(homeTeam, awayTeam, matchDate);
      const homeTeamId = fixture?.teams?.home?.id;
      const awayTeamId = fixture?.teams?.away?.id;
      if (!homeTeamId || !awayTeamId) return null;

      const r = await this.client.get('/fixtures/headtohead', {
        params: { h2h: `${homeTeamId}-${awayTeamId}`, last: limit },
      });
      const fixtures: AFFixture[] = r.data?.response ?? [];

      let homeWins = 0, awayWins = 0, draws = 0;
      // Nombre de rencontres réellement comptabilisées, à ne pas confondre avec
      // `fixtures.length` : voir plus bas.
      let joues = 0;

      const matches: H2HMatch[] = fixtures.map(f => {
        const hGoals = f.goals.home;
        const aGoals = f.goals.away;
        const fixtureHomeIsHomeTeam = f.teams.home.id === homeTeamId;
        let winner: 'HOME_TEAM' | 'AWAY_TEAM' | 'DRAW' | null = null;

        // API-Football renvoie aussi la rencontre en cours ou à venir dans
        // l'historique. Un match en direct à 0-0 était donc compté comme un nul,
        // et l'écran affichait « 2 nuls » au-dessus d'une liste n'en contenant
        // qu'un — le contrôleur filtrant la liste sur FINISHED sans toucher aux
        // agrégats. Un match non terminé n'a pas de résultat : il ne compte pas.
        const termine = mapAFStatus(f.fixture.status.short) === 'FINISHED';

        if (termine && hGoals != null && aGoals != null) {
          joues++;
          if (hGoals === aGoals) {
            winner = 'DRAW'; draws++;
          } else {
            const fixtureHomeWon = hGoals > aGoals;
            const homeTeamWon = fixtureHomeIsHomeTeam ? fixtureHomeWon : !fixtureHomeWon;
            if (homeTeamWon) { winner = 'HOME_TEAM'; homeWins++; }
            else              { winner = 'AWAY_TEAM'; awayWins++; }
          }
        }

        return {
          id:          f.fixture.id,
          utcDate:     f.fixture.date,
          status:      mapAFStatus(f.fixture.status.short),
          competition: { name: f.league.name, code: ApiFootballService._leagueCodeFor(f.league.id) ?? `AF_${f.league.id}` },
          homeTeam:    { id: f.teams.home.id, name: f.teams.home.name, shortName: f.teams.home.name },
          awayTeam:    { id: f.teams.away.id, name: f.teams.away.name, shortName: f.teams.away.name },
          score:       { winner, fullTime: { home: hGoals, away: aGoals } },
        };
      });

      return {
        aggregates: {
          // `joues` et non `fixtures.length` : les deux divergeaient dès qu'une
          // rencontre non terminée figurait dans l'historique renvoyé.
          numberOfMatches: joues,
          homeTeam: { id: homeTeamId, name: fixture.teams.home.name, wins: homeWins, draws, losses: awayWins },
          awayTeam: { id: awayTeamId, name: fixture.teams.away.name, wins: awayWins, draws, losses: homeWins },
        },
        matches,
      };
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur H2H:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }

  // ── Compositions d'équipe ───────────────────────────────────────────────────

  /**
   * Compositions officielles (onze de départ, remplaçants, entraîneur,
   * formation). Publiées par les clubs ~30-60 min avant le coup d'envoi —
   * `available: false` tant qu'elles ne sont pas encore sorties.
   */
  async getLineups(homeTeam: string, awayTeam: string, matchDate: string): Promise<LineupsResult | null> {
    if (!this._hasKey()) return null;

    const cacheKey = `lineups_${homeTeam}_${awayTeam}_${matchDate}`;
    const cached = lineupsCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < LINEUPS_CACHE_TTL) return cached.data;

    try {
      const fixture = await this._findFixtureByTeams(homeTeam, awayTeam, matchDate);
      if (!fixture) return null;

      const r = await this.client.get('/fixtures/lineups', {
        params: { fixture: fixture.fixture.id },
      });
      const raw: any[] = r.data?.response ?? [];

      if (raw.length < 2) {
        const result: LineupsResult = { available: false, home: null, away: null };
        lineupsCache.set(cacheKey, { data: result, ts: Date.now() });
        return result;
      }

      const format = (side: any): TeamLineup => ({
        formation: side.formation ?? null,
        coach:      side.coach?.name  ?? null,
        // La photo accompagne le nom dans la même réponse ; seul le nom était
        // lu.
        coachPhoto: side.coach?.photo ?? null,
        startXI:   (side.startXI ?? []).map((p: any) => ({
          id:     p.player?.id ?? null,
          name:   p.player?.name ?? '',
          number: p.player?.number ?? null,
          pos:    p.player?.pos ?? null,
          grid:   p.player?.grid ?? null,
        })),
        substitutes: (side.substitutes ?? []).map((p: any) => ({
          id:     p.player?.id ?? null,
          name:   p.player?.name ?? '',
          number: p.player?.number ?? null,
          pos:    p.player?.pos ?? null,
          grid:   p.player?.grid ?? null,
        })),
      });

      // L'API ne garantit pas l'ordre home/away — on recale sur l'id d'équipe.
      const homeSide = raw.find(s => s.team?.id === fixture.teams?.home?.id) ?? raw[0];
      const awaySide = raw.find(s => s.team?.id === fixture.teams?.away?.id) ?? raw[1];

      const result: LineupsResult = {
        available: true,
        home: format(homeSide),
        away: format(awaySide),
      };
      lineupsCache.set(cacheKey, { data: result, ts: Date.now() });
      return result;
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur lineups:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }

  // ── Blessures / suspensions ─────────────────────────────────────────────────

  /** Joueurs indisponibles (blessure, suspension) pour les deux équipes d'un match. */
  async getInjuries(homeTeam: string, awayTeam: string, matchDate: string): Promise<InjuredPlayer[] | null> {
    if (!this._hasKey()) return null;

    const cacheKey = `injuries_${homeTeam}_${awayTeam}_${matchDate}`;
    const cached = injuriesCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < INJURIES_CACHE_TTL) return cached.data;

    try {
      const fixture = await this._findFixtureByTeams(homeTeam, awayTeam, matchDate);
      if (!fixture) return null;

      const r = await this.client.get('/injuries', {
        params: { fixture: fixture.fixture.id },
      });
      const raw: any[] = r.data?.response ?? [];

      const mapped: InjuredPlayer[] = raw.map(item => ({
        name:   item.player?.name ?? '',
        team:   item.team?.id === fixture.teams?.home?.id ? 'home' : 'away',
        type:   item.player?.type ?? 'Injured',
        // Traduit ici, à la frontière du fournisseur — comme les
        // recommandations et les marchés. La table vivait côté mobile et avait
        // des trous que rien ne signalait : « Hamstring Injury » et « Hip
        // Injury » s'affichaient en anglais sous « Blessure musculaire ».
        reason: traduireAbsence(item.player?.reason ?? item.player?.type),
        // Photo du joueur, fournie dans la même réponse et jamais lue.
        photo:  item.player?.photo ?? null,
        suspension: estSuspension(item.player?.reason ?? ''),
      }));

      // L'API renvoie parfois plusieurs fois la même absence pour un joueur
      // (une ligne par source/compétition couvrant la même rencontre), ce qui
      // affichait la liste en double côté mobile.
      const seen = new Set<string>();
      const result = mapped.filter(p => {
        const key = `${p.team}|${p.name}|${p.type}|${p.reason}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });

      injuriesCache.set(cacheKey, { data: result, ts: Date.now() });
      return result;
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur injuries:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }

  // ── Cotes 1xBet ────────────────────────────────────────────────────────────

  /**
   * Cotes complètes pour un match, en priorité chez 1xBet, avec repli
   * automatique sur un autre bookmaker si 1xBet n'a rien coté (marché
   * suspendu, match en direct, ligue peu couverte...) : les ~31 marchés
   * bruts proposés (handicaps, mi-temps, score exact...) plus un raccourci
   * `options` vers les 8 types que l'app sait exploiter nativement
   * (auto-calcul WIN/LOSS inclus). Les autres marchés servent au choix
   * manuel de l'admin — leur résultat doit être forcé à la main une fois
   * le match terminé. `result.source` indique le bookmaker réellement
   * utilisé (ex. "1xBet" ou "Bet365 (1xBet indisponible)").
   */
  async getOdds1xBet(homeTeam: string, awayTeam: string, matchDate: string, fixtureId?: number): Promise<MatchOddsResult | null> {
    if (!this._hasKey()) return null;

    const cacheKey = `odds_${homeTeam}_${awayTeam}_${matchDate}`;
    const cached = oddsCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < ODDS_CACHE_TTL) return cached.data;

    try {
      // Si on connaît déjà l'ID de la fixture (match suivi en base), on l'utilise
      // directement plutôt que la recherche souple équipes+date — celle-ci échoue
      // si le match a été replanifié par la source après notre dernier scan (la
      // date stockée en base ne correspond alors plus à la date réelle côté API).
      const fixture = fixtureId
        ? { fixture: { id: fixtureId } }
        : await this._findFixtureByTeams(homeTeam, awayTeam, matchDate);
      if (!fixture) return null;

      const hasBets = (bm: any) => Array.isArray(bm?.bets) && bm.bets.length > 0;

      // 1. Essayer 1xBet en priorité.
      const r1 = await this.client.get('/odds', {
        params: { fixture: fixture.fixture.id, bookmaker: XBET_BOOKMAKER_ID },
      });
      let bookmaker = (r1.data?.response ?? [])[0]?.bookmakers?.[0];
      let source = '1xBet';

      // 2. Repli : n'importe quel bookmaker ayant coté ce match, si 1xBet n'a rien.
      if (!hasBets(bookmaker)) {
        const r2 = await this.client.get('/odds', {
          params: { fixture: fixture.fixture.id },
        });
        const allBookmakers: any[] = (r2.data?.response ?? [])[0]?.bookmakers ?? [];
        const fallback = allBookmakers.find(hasBets);
        if (fallback) {
          bookmaker = fallback;
          source = `${fallback.name} (1xBet indisponible)`;
        }
      }

      const result: MatchOddsResult = { source, options: [], markets: [] };
      if (!hasBets(bookmaker)) {
        oddsCache.set(cacheKey, { data: result, ts: Date.now() });
        return result;
      }

      const bets: any[] = bookmaker.bets ?? [];

      // Tous les marchés bruts, avec tag du type interne connu si applicable.
      result.markets = bets
        .filter(b => Array.isArray(b.values) && b.values.length > 0)
        .map(b => ({
          name: b.name as string,
          values: (b.values as any[]).map(v => {
            const odd = parseFloat(v.odd);
            const type = KNOWN_TYPE_MAP[b.name]?.[v.value];
            return { value: v.value as string, odd, ...(type ? { type } : {}) };
          }).filter(v => !isNaN(v.odd)),
        }));

      // Raccourci vers les 8 types connus — alimente les pills rapides existantes.
      const findOdd = (betName: string, valueName: string): number | null => {
        const bet = bets.find(b => b.name === betName);
        const v   = bet?.values?.find((x: any) => x.value === valueName);
        return v ? parseFloat(v.odd) : null;
      };
      const push = (type: KnownPredictionType, label: string, odd: number | null) => {
        if (odd != null && !isNaN(odd)) result.options.push({ type, label, odd });
      };

      push('win1',    `${homeTeam} gagne`,        findOdd('Match Winner', 'Home'));
      push('draw',    'Match nul',                 findOdd('Match Winner', 'Draw'));
      push('win2',    `${awayTeam} gagne`,         findOdd('Match Winner', 'Away'));
      push('btts',    'Les deux équipes marquent', findOdd('Both Teams Score', 'Yes'));
      push('over25',  '+2.5 buts',                 findOdd('Goals Over/Under', 'Over 2.5'));
      push('under25', '-2.5 buts',                 findOdd('Goals Over/Under', 'Under 2.5'));
      push('over35',  '+3.5 buts',                 findOdd('Goals Over/Under', 'Over 3.5'));
      push('under35', '-3.5 buts',                 findOdd('Goals Over/Under', 'Under 3.5'));

      oddsCache.set(cacheKey, { data: result, ts: Date.now() });
      return result;
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur odds:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }

  // ── Classement ───────────────────────────────────────────────────────────────

  /**
   * Classement d'une ligue suivie (WC/PL/BL1/SA/PD/FL1/CL — pas les amicaux,
   * qui n'ont pas de tableau). ⚠️ Combine league+season, donc bloqué sur le
   * plan gratuit ("Free plans do not have access to this season") tant que
   * l'abonnement payant n'est pas actif — retourne null proprement dans ce cas.
   */
  async getStandings(leagueCode: string): Promise<StandingRow[] | null> {
    if (!this._hasKey()) return null;
    const league = LEAGUE_MAP[leagueCode];
    if (!league || leagueCode === 'FRIENDLY') return null;

    // La saison est demandée à l'API, pas lue dans une constante : c'est le
    // gel de cette constante qui faisait servir la table finale de la saison
    // précédente à chaque rentrée d'août.
    const saison = (await saisonCourante(leagueCode)) ?? league.season;

    // La clé de cache porte la saison. Sans elle, le jour du basculement, les
    // deux heures de cache continueraient de servir l'ancien tableau.
    const cacheKey = `standings_${leagueCode}_${saison}`;
    const cached = standingsCache.get(cacheKey);
    if (cached && Date.now() - cached.ts < STANDINGS_CACHE_TTL) return cached.data;

    try {
      const r = await this.client.get('/standings', {
        params: { league: league.id, season: saison },
      });
      if (r.data?.errors && Object.keys(r.data.errors).length > 0) {
        console.warn('[ApiFootball] Classement indisponible (plan) :', JSON.stringify(r.data.errors));
        return null;
      }

      const table: any[] = r.data?.response?.[0]?.league?.standings?.[0] ?? [];
      const result: StandingRow[] = table.map(row => ({
        rank:      row.rank,
        teamName:  row.team?.name ?? '',
        teamLogo:  row.team?.logo ?? null,
        played:    row.all?.played ?? 0,
        win:       row.all?.win ?? 0,
        draw:      row.all?.draw ?? 0,
        lose:      row.all?.lose ?? 0,
        goalsDiff: row.goalsDiff ?? 0,
        points:    row.points ?? 0,
        form:      row.form ?? null,
        // `description` porte la zone de qualification ou de relégation. Elle
        // arrive en anglais et sous forme libre — « Promotion - Champions
        // League (Group Stage) » — et n'était pas lue du tout.
        zone:       zoneDepuisDescription(row.description)?.libelle ?? null,
        zoneNature: zoneDepuisDescription(row.description)?.nature  ?? null,
      }));

      standingsCache.set(cacheKey, { data: result, ts: Date.now() });
      return result;
    } catch (err) {
      const e = err as AxiosError;
      console.error('[ApiFootball] Erreur standings:', (e.response?.data as any) ?? e.message);
      return null;
    }
  }
}

export const apiFootballService = new ApiFootballService();

/**
 * Volet « enrichissement » du même compte API-Football (plan Pro).
 *
 * Construit sur le client Axios de `apiFootballService` : une seule clé, un
 * seul point de configuration, et les quotas restent comptés au même endroit.
 */
export const apiFootballInsights = new ApiFootballInsights(
  apiFootballService.httpClient,
  () => apiFootballService.hasApiKey,
);
