import { MatchInfoService } from '../services/match_info.service';
import { noterQuota, _reinitialiser } from '../services/etat_taches';
const date = new Date('2026-10-06T12:00:00Z');
const fixture = (phase = 'PEN') => ({
  fixture: { id: 42, status: { short: phase, elapsed: 120 }, referee: 'Referee', venue: { name: 'Stadium', city: 'City' } },
  teams: { home: { id: 1, name: 'Home' }, away: { id: 2, name: 'Away' } },
  league: { round: 'Final', season: 2026 },
  score: { halftime: { home: 0, away: 0 }, fulltime: { home: 1, away: 1 },
    extratime: { home: 2, away: 2 }, penalty: { home: 5, away: 4 } },
  predictions: { secret: true },
});
const reply = (f: any) => ({ data: { errors: [], response: [f] } });
beforeEach(() => { jest.useFakeTimers(); jest.setSystemTime(date); });
afterEach(() => { _reinitialiser(); jest.useRealTimers(); });

it('expose uniquement les données sportives et sépare les scores sans additionner les tirs au but', async () => {
  const get = jest.fn(async () => reply(fixture()));
  const service = new MatchInfoService({ get } as any, () => true);
  const results = await Promise.all(Array.from({ length: 20 }, () => service.get(42, 'FINISHED', date)));
  expect(get).toHaveBeenCalledTimes(1);
  expect(get).toHaveBeenCalledWith('/fixtures', { params: { id: 42 } });
  expect(results[0]).toMatchObject({ venue: { name: 'Stadium', city: 'City' }, referee: 'Referee', round: 'Final', season: 2026,
    phase: 'PEN', scores: { fulltime: { home: 1, away: 1 }, extratime: { home: 2, away: 2 }, penalty: { home: 5, away: 4 } }, stale: false });
  expect(results[0]).not.toHaveProperty('predictions');
});
it.each(['NS','HT','ET','P','AET','PEN','SUSP','ABD'])('préserve la phase %s et ne fabrique pas de zéros', async phase => {
  const f = fixture(phase); f.score = {} as any; f.fixture.referee = null as any; f.fixture.venue = {} as any;
  const info = await new MatchInfoService({ get: async () => reply(f) } as any, () => true).get(42, 'LIVE', date);
  expect(info).toMatchObject({ phase, referee: null, venue: { name: null, city: null }, scores: { penalty: { home: null, away: null } } });
});
it('le cache live expire après 30 secondes et la fin invalide immédiatement le relevé live', async () => {
  const get = jest.fn(async () => reply(fixture('ET')));
  const svc = new MatchInfoService({ get } as any, () => true);
  await svc.get(42, 'LIVE', date); await svc.get(42, 'LIVE', date);
  expect(get).toHaveBeenCalledTimes(1);
  jest.advanceTimersByTime(30_001); get.mockResolvedValue(reply(fixture('P')));
  expect(await svc.get(42, 'LIVE', date)).toMatchObject({ phase: 'P' });
  get.mockResolvedValue(reply(fixture('PEN')));
  expect(await svc.get(42, 'FINISHED', date)).toMatchObject({ phase: 'PEN' });
  expect(get).toHaveBeenCalledTimes(3);
});
it('partage le relevé récent du synchroniseur même lorsque le quota est réservé', async () => {
  noterQuota({ 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '700' });
  const get = jest.fn();
  const info = await new MatchInfoService({ get } as any, () => true, () => fixture()).get(42, 'FINISHED', date);
  expect(info).toMatchObject({ phase: 'PEN' }); expect(get).not.toHaveBeenCalled();
  expect(await new MatchInfoService({ get } as any, () => true).get(42, 'LIVE', date)).toBeNull();
  expect(get).not.toHaveBeenCalled();
});
it('panne: conserve la date, signale le dernier relevé et cesse de le servir après cinq minutes', async () => {
  const get = jest.fn(async () => reply(fixture('ET')));
  const svc = new MatchInfoService({ get } as any, () => true);
  const first = await svc.get(42, 'LIVE', date);
  jest.advanceTimersByTime(30_001); get.mockRejectedValue(new Error('offline'));
  expect(await svc.get(42, 'LIVE', date)).toMatchObject({ stale: true, updated_at: first!.updated_at });
  await svc.get(42, 'LIVE', date); expect(get).toHaveBeenCalledTimes(2);
  jest.advanceTimersByTime(5 * 60_000);
  expect(await svc.get(42, 'LIVE', date)).toBeNull();
});
it('rejette une réponse d’un autre match et les erreurs fournisseur HTTP 200', async () => {
  const f = fixture(); f.fixture.id = 43;
  const get = jest.fn(async () => reply(f));
  expect(await new MatchInfoService({ get } as any, () => true).get(42, 'LIVE', date)).toBeNull();
  get.mockResolvedValue({ data: { errors: { quota: 'exceeded' }, response: [fixture()] } } as any);
  expect(await new MatchInfoService({ get } as any, () => true).get(42, 'LIVE', date)).toBeNull();
});
it('aucun appel sans clé ou pour un identifiant invalide', async () => {
  const get = jest.fn();
  expect(await new MatchInfoService({ get } as any, () => false).get(42, 'LIVE', date)).toBeNull();
  expect(await new MatchInfoService({ get } as any, () => true).get(-1, 'LIVE', date)).toBeNull();
  expect(get).not.toHaveBeenCalled();
});
