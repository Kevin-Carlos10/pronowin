import { noterQuota, _reinitialiser } from '../services/etat_taches';
import { MatchLiveService } from '../services/match_live.service';
import { CacheFootball, exigerQuotaEnrichissement } from '../services/cache_football';
import { ApiFootballInsights } from '../services/api_football_insights.service';

const fixture = { fixture: { id: 42 }, teams: { home: { id: 1, name: 'Home' }, away: { id: 2, name: 'Away' } } };
const reply = (response: any[]) => ({ data: { response, errors: [] } });
const event = { time: { elapsed: 21 }, team: { name: 'Home' }, player: { name: 'A' }, type: 'Goal', detail: 'Normal Goal' };
beforeEach(() => { jest.useFakeTimers(); jest.setSystemTime(new Date('2026-10-05T12:00:00Z')); });
afterEach(() => { _reinitialiser(); jest.useRealTimers(); });

it('live: identités et libellés alignés même si le fournisseur inverse les rangées', async () => {
  const client = { get: jest.fn(async (url: string) => reply(url === '/fixtures' ? [fixture] : url.endsWith('/events') ? [event] : [
    { team: { id: 2 }, statistics: [{ type: 'Shots on Goal', value: 3 }, { type: 'Ball Possession', value: '40%' }] },
    { team: { id: 1 }, statistics: [{ type: 'Ball Possession', value: '60%' }, { type: 'Shots on Goal', value: 5 }, { type: 'Fouls', value: null }] },
  ])) };
  const svc = new MatchLiveService(client as any, () => true);
  const results = await Promise.all(Array.from({ length: 15 }, () => svc.stats(42, 'LIVE')));
  expect(client.get).toHaveBeenCalledTimes(3);
  expect(client.get).toHaveBeenCalledWith('/fixtures', { params: { id: 42 } });
  expect(results[0]).toMatchObject({ fixture_id: 42, stale: false, home_team: 'Home', events: [{ minute: 21 }] });
  expect(results[0]!.stats).toEqual([
    { label: 'Ball Possession', home: '60%', away: '40%' }, { label: 'Shots on Goal', home: 5, away: 3 },
    { label: 'Fouls', home: null, away: null },
  ]);
  await svc.stats(42, 'LIVE');
  expect(client.get).toHaveBeenCalledTimes(3);
  jest.advanceTimersByTime(60_001);
  await svc.stats(42, 'LIVE');
  expect(client.get).toHaveBeenCalledTimes(5);
  await svc.stats(42, 'FINISHED');
  expect(client.get).toHaveBeenCalledTimes(7); // jamais le dernier cache LIVE comme bilan final
});

it('les erreurs HTTP 200 de quota gardent la vraie date et temporisent la reprise', async () => {
  let down = false;
  const client = { get: jest.fn(async (url: string) => {
    if (down) return { data: { response: [], errors: { requests: 'quota' } } };
    return reply(url === '/fixtures' ? [fixture] : url.endsWith('/events') ? [event] : []);
  }) };
  const svc = new MatchLiveService(client as any, () => true);
  const first = await svc.stats(42, 'LIVE');
  down = true; jest.advanceTimersByTime(60_001);
  const stale = await svc.stats(42, 'LIVE');
  expect(stale).toMatchObject({ stale: true, updated_at: first!.updated_at, events: [{ minute: 21 }] });
  const calls = client.get.mock.calls.length;
  await svc.stats(42, 'LIVE');
  expect(client.get).toHaveBeenCalledTimes(calls);
  jest.advanceTimersByTime(5 * 60_000);
  expect(await svc.stats(42, 'LIVE')).toBeNull();
});

it('une absence de couverture valide reste une liste vide, pas des zéros inventés', async () => {
  const client = { get: jest.fn(async (url: string) => reply(url === '/fixtures' ? [fixture] : [])) };
  const svc = new MatchLiveService(client as any, () => true);
  expect(await svc.stats(42, 'LIVE')).toMatchObject({ stats: [], events: [], stale: false });
  expect(await svc.stats(42, 'SCHEDULED')).toBeNull();
  expect(client.get).toHaveBeenCalledTimes(3);
});

it('une panne de statistiques laisse les événements disponibles et signale le relevé incomplet', async () => {
  const client = { get: jest.fn(async (url: string) => {
    if (url.endsWith('/statistics')) throw new Error('offline');
    return reply(url === '/fixtures' ? [fixture] : [event]);
  }) };
  const r = await new MatchLiveService(client as any, () => true).stats(42, 'LIVE');
  expect(r).toMatchObject({ stale: true, stats: [], events: [{ minute: 21 }] });
});

it('cache borné et erreur sans boucle de reprise', async () => {
  const cache = new CacheFootball<number>(2);
  const get = jest.fn(async () => 1);
  await cache.read('a', 60_000, get); await cache.read('b', 60_000, get); await cache.read('c', 60_000, get);
  await cache.read('a', 60_000, get); expect(get).toHaveBeenCalledTimes(4);
  const down = jest.fn(async () => { throw new Error('429'); });
  expect((await cache.read('d', 60_000, down)).data).toBeNull();
  await cache.read('d', 60_000, down); expect(down).toHaveBeenCalledTimes(1);
});

it('cotes live: clé stable, marchés suspendus exclus, un seul appel partagé', async () => {
  const client = { get: jest.fn(async () => reply([
    { fixture: { id: 42, status: { elapsed: 25 } }, odds: [
      { name: 'Match Winner', values: [{ value: 'Home', odd: '1.80' }, { value: 'Draw', odd: '2.50', suspended: true }] },
      { name: 'Double Chance', suspended: true, values: [{ value: 'Home/Draw', odd: '1.20' }] },
      { name: 'Match Goals', values: [{ value: 'Over', odd: '1.90', handicap: '2.5' }] },
    ] },
    { fixture: { id: 43 }, status: { stopped: true }, odds: [{ name: 'Match Winner', values: [{ value: 'Home', odd: '2.0' }] }] },
  ])) };
  const svc = new ApiFootballInsights(client as any, () => true);
  const [a, b] = await Promise.all([svc.getLiveOdds(42), svc.getLiveOdds(43)]);
  expect(client.get).toHaveBeenCalledTimes(1); expect(b).toBeNull();
  expect(a!.markets).toEqual([
    // Chaque sélection porte ses deux libellés, pour l'app en français et en anglais.
    { key: 'match winner', name: 'Vainqueur du match',
      values: [{ value: 'Home', odd: 1.8, labels: { fr: 'Domicile', en: 'Home' } }] },
    { key: 'match goals', name: 'Total de buts',
      values: [{ value: 'Over', odd: 1.9, ligne: '2.5', labels: { fr: 'Plus de', en: 'Over' } }] },
  ]);
  jest.advanceTimersByTime(120_001);
  client.get.mockRejectedValueOnce(new Error('offline'));
  expect(await svc.getLiveOdds(42)).toMatchObject({ stale: true, updated_at: a!.updated_at });
});

it('les enrichissements préservent la réserve du quota et reprennent le lendemain', async () => {
  noterQuota({ 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '750' });
  const client = { get: jest.fn() };
  const svc = new MatchLiveService(client as any, () => true);
  expect(await svc.stats(42, 'LIVE')).toBeNull();
  expect(client.get).not.toHaveBeenCalled();
  expect(exigerQuotaEnrichissement).toThrow();
  jest.advanceTimersByTime(24 * 60 * 60_000);
  expect(exigerQuotaEnrichissement).not.toThrow();
});
