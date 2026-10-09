import type { AxiosInstance } from 'axios';
import { enrichissementsFootball } from './enrichissements_football';
import { zoneDepuisDescription } from './zones_classement';

/** Le bilan d'une équipe sur un terrain : à domicile, à l'extérieur. */
export interface Bilan {
  played: number; win: number; draw: number; lose: number; goalsFor: number; goalsAgainst: number; points: number;
}
export interface StandingRow {
  rank: number; teamName: string; teamLogo: string | null; teamId: number | null;
  played: number; win: number; draw: number; lose: number; goalsDiff: number; points: number;
  goalsFor: number; goalsAgainst: number;
  /** Comme Sofascore : le classement domicile ou extérieur se recompose de ces bilans. */
  home: Bilan; away: Bilan;
  form: string | null; zone: string | null; zoneNature: string | null;
  groupId: string; groupName: string | null; season: number;
  isMatchTeam: boolean | null; updatedAt: string | null; stale: boolean;
}
export interface ClassementMatch {
  status: 'available' | 'pending' | 'unsupported' | 'unavailable';
  rows: StandingRow[]; season: number | null;
}

function bilan(b: any): Bilan {
  const win = b?.win ?? 0, draw = b?.draw ?? 0;
  return {
    played: b?.played ?? 0, win, draw, lose: b?.lose ?? 0,
    goalsFor: b?.goals?.for ?? 0, goalsAgainst: b?.goals?.against ?? 0,
    // Le fournisseur ne donne pas les points par terrain : 3 par victoire, 1 par nul.
    points: win * 3 + draw,
  };
}

export class ClassementsFootball {
  constructor(private client: AxiosInstance, private fixture: (id: number) => Promise<any | null>) {}

  async get(options: { fixtureId?: number; leagueId?: number; matchDate?: Date }): Promise<ClassementMatch> {
    const api = enrichissementsFootball(this.client);
    let league = options.leagueId, season: number | undefined;
    let home: number | undefined, away: number | undefined;
    const result = (status: ClassementMatch['status'], rows: StandingRow[] = []): ClassementMatch =>
      ({ status, rows, season: season ?? null });
    try {
      if (options.fixtureId) {
        const f = await this.fixture(options.fixtureId);
        if (!f) return result('unavailable');
        league = f.league?.id; season = f.league?.season;
        home = f.teams?.home?.id; away = f.teams?.away?.id;
      }
      if (!league) return result('unsupported');
      const leagues = await api.get('/leagues', { id: league }, 24 * 60 * 60_000);
      const seasons: any[] = leagues.find(l => l.league?.id === league)?.seasons ?? [];
      // For legacy matches without an API-Football id, use date boundaries,
      // never today's season. Overlapping/unknown seasons stay unavailable.
      if (!season && options.matchDate) {
        const day = options.matchDate.toISOString().slice(0, 10);
        const candidates = seasons.filter(s => s.start && s.end && s.start <= day && s.end >= day);
        if (candidates.length === 1) season = candidates[0].year;
      }
      if (!Number.isInteger(season)) return result('unavailable');
      const coverage = seasons.find(s => s.year === season)?.coverage?.standings;
      if (coverage === false) return result('unsupported');
      const snapshot = await api.read('/standings', { league, season: season! }, 15 * 60_000);
      if (snapshot.data === null) return result('unavailable');
      const data = snapshot.data.find(d => d.league?.id === league && d.league?.season === season);
      if (!data && snapshot.data.length > 0) return result('unavailable');
      const groups = data?.league?.standings ?? [];
      if (!Array.isArray(groups) || groups.some((g: any) => !Array.isArray(g))) return result('unavailable');
      const rows: StandingRow[] = groups.flatMap((group: any[], index: number) => group.map(row => {
        if (!Number.isFinite(row.rank) || !row.team?.id) throw new Error('Invalid standing row');
        const zone = zoneDepuisDescription(row.description);
        return {
          rank: row.rank, teamId: row.team.id, teamName: row.team.name ?? '', teamLogo: row.team.logo ?? null,
          played: row.all?.played ?? 0, win: row.all?.win ?? 0, draw: row.all?.draw ?? 0, lose: row.all?.lose ?? 0,
          goalsDiff: row.goalsDiff ?? 0, points: row.points ?? 0, form: row.form ?? null,
          goalsFor: row.all?.goals?.for ?? 0, goalsAgainst: row.all?.goals?.against ?? 0,
          home: bilan(row.home), away: bilan(row.away),
          zone: zone?.libelle ?? null, zoneNature: zone?.nature ?? null,
          groupId: group[0]?.group || String(index), groupName: row.group ?? null, season: season!,
          isMatchTeam: home && away ? row.team.id === home || row.team.id === away : null,
          updatedAt: data.league?.update ?? snapshot.updatedAt, stale: snapshot.stale,
        };
      }));
      // An old empty response followed by a failure isn't "not published yet".
      return result(rows.length ? 'available' : snapshot.stale ? 'unavailable' : 'pending', rows);
    } catch (_) { return result('unavailable'); }
  }
}
