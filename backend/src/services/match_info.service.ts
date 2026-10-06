import type { AxiosInstance } from 'axios';
import { CacheFootball, exigerQuotaEnrichissement, responseFootball } from './cache_football';

interface MatchInfoData {
  fixture_id: number;
  venue: { name: string | null; city: string | null };
  referee: string | null; round: string | null; season: number | null;
  phase: string | null; elapsed: number | null; extra: number | null;
  home_team: string | null; away_team: string | null;
  scores: { halftime: Score; fulltime: Score; extratime: Score; penalty: Score };
}
type Score = { home: number | null; away: number | null };
const entier = (v: unknown): number | null => typeof v === 'number' && Number.isInteger(v) && v >= 0 ? v : null;
const texte = (v: unknown): string | null => typeof v === 'string' && v.trim() ? v.trim() : null;
const score = (v: any): Score => ({ home: entier(v?.home), away: entier(v?.away) });

/** Public sporting data only. Never includes predictions, odds or editorial content.
 * Phase scores are passed through separately; penalties are never added to goals.
 */
export class MatchInfoService {
  private cache = new CacheFootball<MatchInfoData>(256, 5 * 60_000);
  constructor(private client: AxiosInstance, private hasKey: () => boolean,
    private recentFixture: (id: number) => any | null = () => null) {}

  async get(id: number, status: string, matchDate: Date) {
    if (!this.hasKey() || !Number.isSafeInteger(id) || id <= 0) return null;
    const before = matchDate.getTime() - Date.now();
    const ttl = status === 'FINISHED' ? 5 * 60_000
      : status === 'SCHEDULED' && before > 60 * 60_000 ? 15 * 60_000 : 30_000;
    // Status in the key forces a fresh response on kickoff and final whistle.
    const result = await this.cache.read(id + ':' + status, ttl, async () => {
      let fixture = this.recentFixture(id);
      if (!fixture) {
        exigerQuotaEnrichissement();
        const response = await this.client.get('/fixtures', { params: { id } });
        fixture = responseFootball(response.data).find(f => f.fixture?.id === id);
      }
      if (fixture?.fixture?.id !== id || !fixture?.teams?.home?.id || !fixture?.teams?.away?.id ||
          !texte(fixture?.fixture?.status?.short)) throw new Error('Invalid fixture information');
      const f = fixture.fixture;
      return {
        fixture_id: id,
        venue: { name: texte(f.venue?.name), city: texte(f.venue?.city) },
        referee: texte(f.referee), round: texte(fixture.league?.round), season: entier(fixture.league?.season),
        phase: texte(f.status.short), elapsed: entier(f.status.elapsed), extra: entier(f.status.extra),
        home_team: texte(fixture.teams.home.name), away_team: texte(fixture.teams.away.name),
        scores: { halftime: score(fixture.score?.halftime), fulltime: score(fixture.score?.fulltime),
          extratime: score(fixture.score?.extratime), penalty: score(fixture.score?.penalty) },
      };
    });
    return result.data ? { ...result.data, updated_at: result.updatedAt, stale: result.stale } : null;
  }
}
