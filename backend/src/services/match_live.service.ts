import type { AxiosInstance } from 'axios';
import { enrichissementsFootball } from './enrichissements_football';
import { CacheFootball, responseFootball, exigerQuotaEnrichissement } from './cache_football';
import { observerRencontres } from './estimation_chrono';

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
  /** Chaque mi-temps, si elles retombent sur le total (`statsParMiTemps`). */
  stats_mi_temps?: { first: MatchStat[]; second: MatchStat[] } | null;
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
      observerRencontres(fixture ? [fixture] : []);
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
    const get = (endpoint: string, extra: Record<string, string> = {}) =>
      this.feeds.read(id + ':' + status + ':' + endpoint, ttl, async () => {
        exigerQuotaEnrichissement();
        const r = await this.client.get('/fixtures/' + endpoint, { params: { fixture: id, ...extra } });
        return responseFootball(r.data);
      });
    const [events, stats] = await Promise.all([
      coverage?.events === false ? unsupported : get('events'),
      // `half` : le même appel rend aussi chaque mi-temps (statistics_1h/2h).
      coverage?.statistics_fixtures === false ? unsupported : get('statistics', { half: 'true' }),
    ]);
    if (events.data === null && stats.data === null) return null;
    const home = fixture.teams.home;
    const away = fixture.teams.away;
    const rows = (teamId: number, cle = 'statistics') => new Map<string, any>(
      (stats.data?.find(s => s.team?.id === teamId)?.[cle] ?? [])
        .map((s: any) => [s.type, s.value ?? null]));
    const h = rows(home.id), a = rows(away.id);
    const labels = [...new Set([...h.keys(), ...a.keys()])];
    const lignes = (dom: Map<string, any>, ext: Map<string, any>) =>
      [...new Set([...dom.keys(), ...ext.keys()])].map(label => ({ label, home: dom.get(label) ?? null, away: ext.get(label) ?? null }));
    const miTemps = statsParMiTemps(h, a,
      [rows(home.id, 'statistics_1h'), rows(away.id, 'statistics_1h')],
      [rows(home.id, 'statistics_2h'), rows(away.id, 'statistics_2h')]);
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
        // Identifiants : relient un événement au joueur des compositions sans
        // dépendre de la graphie du nom.
        player_id: Number.isSafeInteger(e.player?.id) ? e.player.id : null,
        assist_id: Number.isSafeInteger(e.assist?.id) ? e.assist.id : null,
        // Motif d'un carton (« Argument », « Foul »…) ou « Penalty Shootout »
        // pour une séance de tirs au but : affiché dans le fil des événements.
        comments: typeof e.comments === 'string' && e.comments.trim() ? e.comments.trim() : null,
      })).sort((a, b) => a.minute - b.minute || (a.extra ?? 0) - (b.extra ?? 0)),
      // Ni l'ordre des équipes, ni celui des statistiques n'est garanti.
      stats: labels.map(label => ({ label, home: h.get(label) ?? null, away: a.get(label) ?? null })),
      // Chaque mi-temps, seulement si elles retombent sur le total.
      stats_mi_temps: miTemps
        ? { first: lignes(miTemps[0][0], miTemps[0][1]), second: lignes(miTemps[1][0], miTemps[1][1]) }
        : null,
    };
  }
}

type Lignes = Map<string, any>;

/** Compteurs dont la somme des deux mi-temps doit redonner le total. */
const COMPTEURS_VERIFIES = ['Total Shots', 'Corner Kicks', 'Fouls'];

/**
 * Statistiques de chaque mi-temps, ou null si on ne peut pas s'y fier.
 *
 * API-Football les rend avec le total (`half=true`), mais pas partout
 * correctement : le 17 octobre 2026, un match d'Eredivisie avait une
 * première mi-temps identique au total et une seconde vide, quand Betis–
 * Barcelona ou Bayern–Leipzig tombaient juste (6 tirs = 2 + 4). On ne les
 * sert que si la seconde mi-temps existe et que, pour chaque équipe, les
 * compteurs vérifiables retombent sur le total.
 */
export function statsParMiTemps(
  totalDom: Lignes, totalExt: Lignes,
  premiere: [Lignes, Lignes], seconde: [Lignes, Lignes],
): [[Lignes, Lignes], [Lignes, Lignes]] | null {
  if ([...premiere, ...seconde].some(m => m.size === 0)) return null;
  const nombre = (v: any) => typeof v === 'number' ? v : v === null || v === undefined ? 0 : NaN;
  let verifies = 0;
  for (const [total, m1, m2] of [[totalDom, premiere[0], seconde[0]], [totalExt, premiere[1], seconde[1]]] as const) {
    for (const cle of COMPTEURS_VERIFIES) {
      if (!total.has(cle)) continue;
      const t = nombre(total.get(cle)), a = nombre(m1.get(cle)), b = nombre(m2.get(cle));
      if (![t, a, b].every(Number.isFinite)) return null;
      // Un relevé en direct peut avoir une action d'avance sur l'autre.
      if (Math.abs(a + b - t) > 1) return null;
      verifies++;
    }
  }
  return verifies > 0 ? [premiere, seconde] : null;
}
