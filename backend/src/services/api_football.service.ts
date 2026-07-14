import axios, { AxiosInstance } from 'axios';

// Mapping Football-Data.org codes → API-Football league IDs + saison
const LEAGUE_MAP: Record<string, { id: number; season: number }> = {
  WC:  { id: 1,   season: 2026 },
  PL:  { id: 39,  season: 2024 },
  BL1: { id: 78,  season: 2024 },
  SA:  { id: 135, season: 2024 },
  PD:  { id: 140, season: 2024 },
  FL1: { id: 61,  season: 2024 },
  CL:  { id: 2,   season: 2024 },
};

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

export class ApiFootballService {
  private client: AxiosInstance;

  constructor() {
    this.client = axios.create({
      baseURL: 'https://v3.football.api-sports.io',
      headers: {
        'x-apisports-key': process.env.API_FOOTBALL_KEY ?? '',
      },
      timeout: 10000,
    });
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

    if (!process.env.API_FOOTBALL_KEY || process.env.API_FOOTBALL_KEY === 'VOTRE_CLE_ICI') {
      console.warn('[ApiFootball] Clé API_FOOTBALL_KEY manquante dans .env');
      return null;
    }

    const league = LEAGUE_MAP[leagueCode];
    if (!league) {
      console.warn(`[ApiFootball] Ligue inconnue: ${leagueCode}`);
      return null;
    }

    try {
      // 1 — Trouver le fixture_id
      // On cherche par date uniquement (league+season filtre trop sur le plan gratuit)
      const fixtureRes = await this.client.get('/fixtures', {
        params: { date: matchDate },
      });

      const fixtures: any[] = fixtureRes.data?.response ?? [];

      // Trouver le bon match par nom d'équipe (matching souple)
      const normalize = (s: string) =>
        s.toLowerCase()
         .replace(/[.\-_]/g, ' ')           // Bosnia-H. → bosnia h
         .replace(/\s+/g, ' ').trim();

      const fixture = fixtures.find(f => {
        const home = normalize(f.teams?.home?.name ?? '');
        const away = normalize(f.teams?.away?.name ?? '');
        const h    = normalize(homeTeam);
        const a    = normalize(awayTeam);
        // Match si l'un contient l'autre, ou si le 1er mot correspond
        const matchTeam = (api: string, db: string) =>
          api.includes(db) || db.includes(api) ||
          api.startsWith(db.split(' ')[0]) || db.startsWith(api.split(' ')[0]);
        return matchTeam(home, h) && matchTeam(away, a);
      });

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
}

export const apiFootballService = new ApiFootballService();
