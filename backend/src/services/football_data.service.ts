import axios, { AxiosError } from 'axios';

const BASE = 'https://api.football-data.org/v4';

export const SUPPORTED_COMPETITIONS: Record<string, string> = {
  WC:  'FIFA World Cup',
  PL:  'Premier League',
  BL1: 'Bundesliga',
  SA:  'Serie A',
  PD:  'La Liga',
  FL1: 'Ligue 1',
  CL:  'Champions League',
};

export interface FDMatch {
  id:          number;
  utcDate:     string;
  status:      string;
  matchday:    number | null;
  competition: { id: number; name: string; code: string; emblem: string };
  homeTeam:    { id: number; name: string; shortName: string; crest: string };
  awayTeam:    { id: number; name: string; shortName: string; crest: string };
  score: {
    fullTime: { home: number | null; away: number | null };
    halfTime: { home: number | null; away: number | null };
  };
}

export interface H2HMatch {
  id:          number;
  utcDate:     string;
  status:      string;
  competition: { name: string; code: string };
  homeTeam:    { id: number; name: string; shortName: string };
  awayTeam:    { id: number; name: string; shortName: string };
  score: {
    winner:   'HOME_TEAM' | 'AWAY_TEAM' | 'DRAW' | null;
    fullTime: { home: number | null; away: number | null };
  };
}

export interface H2HResult {
  aggregates: {
    numberOfMatches: number;
    homeTeam: { id: number; name: string; wins: number; draws: number; losses: number };
    awayTeam: { id: number; name: string; wins: number; draws: number; losses: number };
  };
  matches: H2HMatch[];
}

// ─── Cache en mémoire (évite de dépasser le rate limit du plan gratuit) ────────
interface CacheEntry { data: FDMatch[]; timestamp: number; }
const cache = new Map<string, CacheEntry>();
const CACHE_TTL = 15 * 60 * 1000; // 15 minutes

export class FootballDataService {
  private client = axios.create({
    baseURL: BASE,
    headers: { 'X-Auth-Token': process.env.FOOTBALL_DATA_API_KEY ?? '' },
    timeout: 15000,
  });

  async getUpcomingMatches(competitionCode?: string): Promise<FDMatch[]> {
    const dateFrom = new Date();
    const dateTo   = new Date(Date.now() + 7 * 86400000);
    const fmt      = (d: Date) => d.toISOString().split('T')[0];

    if (competitionCode && SUPPORTED_COMPETITIONS[competitionCode]) {
      return this._fetchWithCache(competitionCode, fmt(dateFrom), fmt(dateTo));
    }

    // Toutes les ligues — avec délai entre chaque pour respecter le rate limit
    const codes  = Object.keys(SUPPORTED_COMPETITIONS);
    const all: FDMatch[] = [];

    for (const code of codes) {
      const matches = await this._fetchWithCache(code, fmt(dateFrom), fmt(dateTo));
      all.push(...matches);
      // Pause seulement si pas en cache (= appel réseau effectué)
      const cacheKey = `${code}_${fmt(dateFrom)}_${fmt(dateTo)}`;
      if (!this._isCacheValid(cacheKey)) {
        await new Promise(res => setTimeout(res, 700));
      }
    }

    return all.sort((a, b) =>
      new Date(a.utcDate).getTime() - new Date(b.utcDate).getTime()
    );
  }

  private async _fetchWithCache(code: string, dateFrom: string, dateTo: string): Promise<FDMatch[]> {
    const cacheKey = `${code}_${dateFrom}_${dateTo}`;

    // Retourner le cache si valide
    if (this._isCacheValid(cacheKey)) {
      console.log(`[FootballData] Cache HIT pour ${code}`);
      return cache.get(cacheKey)!.data;
    }

    const matches = await this._fetchCompetition(code, dateFrom, dateTo);

    // Mettre en cache même si tableau vide (évite les appels répétés)
    cache.set(cacheKey, { data: matches, timestamp: Date.now() });
    return matches;
  }

  private _isCacheValid(key: string): boolean {
    const entry = cache.get(key);
    return !!entry && (Date.now() - entry.timestamp) < CACHE_TTL;
  }

  private async _fetchCompetition(code: string, dateFrom: string, dateTo: string): Promise<FDMatch[]> {
    try {
      console.log(`[FootballData] Fetch ${code} (${dateFrom} → ${dateTo})`);
      const r = await this.client.get(`/competitions/${code}/matches`, {
        params: { status: 'SCHEDULED', dateFrom, dateTo },
      });
      const matches = r.data.matches ?? [];
      console.log(`[FootballData] ${code}: ${matches.length} matchs`);
      return matches;
    } catch (err) {
      const e      = err as AxiosError;
      const status = e.response?.status;
      const data   = e.response?.data as any;

      if (status === 403) {
        throw new Error(
          'Clé API Football-Data invalide ou email non vérifié. ' +
          'Confirmez votre email sur football-data.org puis réessayez.'
        );
      }
      if (status === 429) {
        console.warn(`[FootballData] Rate limit pour ${code} — données mises en cache à vide`);
        return [];
      }
      console.error(`[FootballData] Erreur ${status} pour ${code}:`, data?.message ?? e.message);
      return [];
    }
  }

  async getMatch(matchId: number): Promise<FDMatch | null> {
    try {
      const r = await this.client.get(`/matches/${matchId}`);
      return r.data;
    } catch { return null; }
  }

  async getH2H(matchId: number, limit = 10): Promise<H2HResult | null> {
    try {
      const r = await this.client.get(`/matches/${matchId}/head2head`, {
        params: { limit },
      });
      return r.data;
    } catch (err) {
      const e = err as AxiosError;
      console.error(`[FootballData] H2H error for match ${matchId}:`, e.response?.data ?? e.message);
      return null;
    }
  }

  /**
   * Récupère tous les matchs EN COURS ou TERMINÉS aujourd'hui et hier
   * (statuts : IN_PLAY, PAUSED, FINISHED) pour toutes les compétitions.
   * Utilisé par la sync automatique des scores.
   */
  async getLiveAndRecentMatches(): Promise<FDMatch[]> {
    const now      = new Date();
    const yesterday = new Date(now.getTime() - 86400000);
    const fmt = (d: Date) => d.toISOString().split('T')[0];
    const dateFrom = fmt(yesterday);
    const dateTo   = fmt(now);

    const codes  = Object.keys(SUPPORTED_COMPETITIONS);
    const all: FDMatch[] = [];

    for (const code of codes) {
      try {
        const r = await this.client.get(`/competitions/${code}/matches`, {
          params: { status: 'IN_PLAY,PAUSED,FINISHED', dateFrom, dateTo },
        });
        const matches: FDMatch[] = r.data.matches ?? [];
        all.push(...matches);
        console.log(`[ScoreSync] ${code}: ${matches.length} matchs live/terminés`);
      } catch (err) {
        const e = err as any;
        if (e.response?.status === 429) {
          console.warn(`[ScoreSync] Rate limit pour ${code}, passage au suivant`);
          await new Promise(res => setTimeout(res, 2000));
        } else if (e.response?.status !== 404) {
          console.error(`[ScoreSync] Erreur ${code}:`, e.response?.data?.message ?? e.message);
        }
      }
      // Pause 700ms entre chaque ligue pour respecter la limite 10 req/min
      await new Promise(res => setTimeout(res, 700));
    }

    return all;
  }

  async getCompetitions() {
    return Object.entries(SUPPORTED_COMPETITIONS).map(([code, name]) => ({ code, name }));
  }

  formatForPronostic(m: FDMatch) {
    return {
      external_id:    m.id,
      league:         m.competition.name,
      league_code:    m.competition.code,
      league_logo:    m.competition.emblem ?? null,
      home_team:      m.homeTeam.shortName || m.homeTeam.name,
      home_team_full: m.homeTeam.name,
      home_team_logo: m.homeTeam.crest ?? null,
      away_team:      m.awayTeam.shortName || m.awayTeam.name,
      away_team_full: m.awayTeam.name,
      away_team_logo: m.awayTeam.crest ?? null,
      match_date:     m.utcDate,
      status:         m.status,
      home_score:     m.score.fullTime.home,
      away_score:     m.score.fullTime.away,
    };
  }
}
