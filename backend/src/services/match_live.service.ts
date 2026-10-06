import type { AxiosInstance } from 'axios';
import { enrichissementsFootball } from './enrichissements_football';
import { CacheFootball, responseFootball, exigerQuotaEnrichissement } from './cache_football';

export interface MatchEvent {
  minute: number; extra: number | null; team: string; player: string;
  assist: string | null; type: string; detail: string;
}
export interface MatchStat { label: string; home: string | number | null; away: string | number | null; }
export interface MatchStatsResult {
  fixture_id: number; events: MatchEvent[]; stats: MatchStat[];
  home_team: string; away_team: string;
  updated_at: string | null; stale: boolean;
  events_status?: string; stats_status?: string;
}

export class MatchLiveService {
  private metadata = new CacheFootball<any>(256, 24 * 60 * 60_000);
  private feeds = new CacheFootball<any[]>();
  constructor(private client: AxiosInstance, private hasKey: () => boolean) {}

  /** Identité officielle, partagée avec les compositions, absences et H2H. */
  async fixture(id: number): Promise<any | null> {
    if (!this.hasKey()) return null;
    const result = await this.metadata.read(String(id), 6 * 60 * 60_000, async () => {
      exigerQuotaEnrichissement();
      const r = await this.client.get('/fixtures', { params: { id } });
      const fixture = responseFootball(r.data).find(f => f.fixture?.id === id);
      if (!fixture?.teams?.home?.id || !fixture?.teams?.away?.id) throw new Error('Fixture unavailable');
      return fixture;
    });
    return result.data;
  }

  async stats(id: number, status: string): Promise<MatchStatsResult | null> {
    if (!['LIVE', 'FINISHED'].includes(status)) return null;
    const fixture = await this.fixture(id);
    if (!fixture) return null;
    // Le statut fait partie de la clé : un dernier relevé LIVE ne doit pas
    // masquer le bilan final. Après la fin, relecture toutes les 5 minutes
    // pour recevoir les corrections tardives du fournisseur.
    const ttl = status === 'LIVE' ? 60_000 : 5 * 60_000;
    const season = fixture.league?.id && fixture.league?.season
      ? await enrichissementsFootball(this.client).season(fixture.league.id, fixture.league.season).catch(() => null)
      : null;
    const coverage = season?.coverage?.fixtures;
    const unsupported = { data: [] as any[], updatedAt: null, stale: false };
    const get = (endpoint: string) => this.feeds.read(id + ':' + status + ':' + endpoint, ttl, async () => {
      exigerQuotaEnrichissement();
      const r = await this.client.get('/fixtures/' + endpoint, { params: { fixture: id } });
      return responseFootball(r.data);
    });
    const [events, stats] = await Promise.all([
      coverage?.events === false ? unsupported : get('events'),
      coverage?.statistics_fixtures === false ? unsupported : get('statistics'),
    ]);
    if (events.data === null && stats.data === null) return null;
    const home = fixture.teams.home;
    const away = fixture.teams.away;
    const rows = (teamId: number) => new Map<string, any>(
      (stats.data?.find(s => s.team?.id === teamId)?.statistics ?? [])
        .map((s: any) => [s.type, s.value ?? null]));
    const h = rows(home.id), a = rows(away.id);
    const labels = [...new Set([...h.keys(), ...a.keys()])];
    const dates = [events.updatedAt, stats.updatedAt].filter((d): d is string => d !== null).sort();
    return {
      fixture_id: id, home_team: home.name, away_team: away.name,
      updated_at: dates[0] ?? null, stale: events.stale || stats.stale,
      events_status: coverage?.events === false ? 'unsupported' : events.stale ? 'unavailable' : events.data?.length ? 'available' : 'pending',
      stats_status: coverage?.statistics_fixtures === false ? 'unsupported' : stats.stale ? 'unavailable' : stats.data?.length ? 'available' : 'pending',
      events: (events.data ?? []).map(e => ({
        minute: e.time?.elapsed ?? 0, extra: e.time?.extra ?? null,
        team: e.team?.name ?? '', player: e.player?.name ?? '',
        assist: e.assist?.name ?? null, type: e.type ?? '', detail: e.detail ?? '',
      })).sort((a, b) => a.minute - b.minute || (a.extra ?? 0) - (b.extra ?? 0)),
      // Ni l'ordre des équipes, ni celui des statistiques n'est garanti.
      stats: labels.map(label => ({ label, home: h.get(label) ?? null, away: a.get(label) ?? null })),
    };
  }
}
