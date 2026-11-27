/**
 * Les cotes du formulaire du panneau pour un match en cours (27 novembre
 * 2026) : le flux en direct, pas l'avant-match figé au coup d'envoi.
 */
import { prisma } from '../lib/prisma';
import { apiFootballInsights, apiFootballService } from '../services/api_football.service';
import { cotesDuDirectPourPanneau, enCoursPourPanneau } from '../services/cotes_direct_panneau';
import { getMatchOdds } from '../controllers/pronostics.controller';

const direct = (extra: Record<string, unknown> = {}) => ({
  fixtureId: 4242, elapsed: 63, stale: false,
  markets: [
    { key: 'fulltime result', name: 'Résultat du match', values: [
      { value: 'Home', odd: 1.45 }, { value: 'Draw', odd: 4.1 }, { value: 'Away', odd: 7.5 },
    ] },
    { key: 'double chance', name: 'Double chance', values: [{ value: 'X2', odd: 2.9 }, { value: '1X', odd: 1.08 }] },
    { key: 'over/under line', name: 'Plus/Moins', values: [
      { value: 'Over', odd: 1.62, ligne: '2.5' }, { value: 'Under', odd: 2.2, ligne: '2.5' },
      { value: 'Over', odd: 3.4, ligne: '3.5' },
    ] },
    { key: 'both teams to score', name: 'Les deux équipes marquent', values: [{ value: 'Yes', odd: 2.05 }, { value: 'No', odd: 1.7 }] },
    // Règles propres au direct : pas proposé.
    { key: 'asian handicap', name: 'Handicap asiatique', values: [{ value: 'Home', odd: 1.9, ligne: '-0.5' }] },
    { key: 'next goal', name: 'Prochain but', values: [{ value: '1', odd: 1.8 }] },
  ],
  ...extra,
});

describe('les cotes en direct au format du formulaire', () => {
  it('les noms et valeurs d\'avant-match, que le règlement automatique reconnaît', () => {
    const r = cotesDuDirectPourPanneau(direct() as any, 'Arsenal', 'Chelsea');
    expect(r.source).toBe('Cotes en direct · 63e minute');
    expect(r.markets).toEqual([
      { name: 'Match Winner', values: [
        { value: 'Home', odd: 1.45, type: 'win1' }, { value: 'Draw', odd: 4.1, type: 'draw' }, { value: 'Away', odd: 7.5, type: 'win2' },
      ] },
      { name: 'Double Chance', values: [{ value: 'Draw/Away', odd: 2.9 }, { value: 'Home/Draw', odd: 1.08 }] },
      { name: 'Goals Over/Under', values: [
        { value: 'Over 2.5', odd: 1.62, type: 'over25' }, { value: 'Under 2.5', odd: 2.2, type: 'under25' },
        { value: 'Over 3.5', odd: 3.4, type: 'over35' },
      ] },
      { name: 'Both Teams Score', values: [{ value: 'Yes', odd: 2.05, type: 'btts' }, { value: 'No', odd: 1.7 }] },
    ]);
  });

  it('les raccourcis des pastilles, comme avant le match', () => {
    const r = cotesDuDirectPourPanneau(direct() as any, 'Arsenal', 'Chelsea');
    expect(r.options).toEqual([
      { type: 'win1', label: 'Arsenal gagne', odd: 1.45 },
      { type: 'draw', label: 'Match nul', odd: 4.1 },
      { type: 'win2', label: 'Chelsea gagne', odd: 7.5 },
      { type: 'btts', label: 'Les deux équipes marquent', odd: 2.05 },
      { type: 'over25', label: '+2.5 buts', odd: 1.62 },
      { type: 'under25', label: '-2.5 buts', odd: 2.2 },
      { type: 'over35', label: '+3.5 buts', odd: 3.4 },
    ]);
  });

  it('sans seuil, une valeur de buts ne se lit pas ; flux figé : on le dit', () => {
    const r = cotesDuDirectPourPanneau(direct({
      stale: true, elapsed: null,
      markets: [{ key: 'match goals', name: 'Total de buts', values: [{ value: 'Over', odd: 1.5 }] }],
    }) as any, 'A', 'B');
    expect(r.markets).toEqual([]);
    expect(r.source).toBe('Cotes en direct · flux momentanément figé');
  });
});

describe('le match est-il en cours ?', () => {
  const coupEnvoi = new Date(Date.UTC(2026, 10, 27, 15, 0));
  it('LIVE, ou coup d\'envoi passé depuis moins de 2 h (statut en retard)', () => {
    expect(enCoursPourPanneau('LIVE', coupEnvoi, new Date(Date.UTC(2026, 10, 27, 14, 0)))).toBe(true);
    expect(enCoursPourPanneau('SCHEDULED', coupEnvoi, new Date(Date.UTC(2026, 10, 27, 15, 1)))).toBe(true);
    expect(enCoursPourPanneau('SCHEDULED', coupEnvoi, new Date(Date.UTC(2026, 10, 27, 14, 59)))).toBe(false);
    expect(enCoursPourPanneau('SCHEDULED', coupEnvoi, new Date(Date.UTC(2026, 10, 27, 17, 1)))).toBe(false);
    expect(enCoursPourPanneau('FINISHED', coupEnvoi, new Date(Date.UTC(2026, 10, 27, 15, 30)))).toBe(false);
  });
});

describe('GET /admin/match/:id/odds', () => {
  const response = () => { const r: any = { json: jest.fn() }; r.status = jest.fn(() => r); return r; };
  const match = (status: string, minutes: number) => ({
    id: 'm1', homeTeam: 'Arsenal', awayTeam: 'Chelsea', status, source: 'API_FOOTBALL', externalId: 4242,
    matchDate: new Date(Date.now() - minutes * 60_000),
  });
  const avantMatch = { source: '1xBet', options: [], markets: [{ name: 'Match Winner', values: [{ value: 'Home', odd: 2.1 }] }] };
  let lectureAvantMatch: jest.SpyInstance;

  beforeEach(() => {
    lectureAvantMatch = jest.spyOn(apiFootballService, 'getOdds1xBet').mockResolvedValue(avantMatch as any);
  });
  afterEach(() => jest.restoreAllMocks());

  it('en direct : les cotes du direct, pas celles d\'avant le coup d\'envoi', async () => {
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue(match('LIVE', 63) as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(direct() as any);
    const res = response();
    await getMatchOdds({ params: { matchId: 'm1' } } as any, res);
    expect(res.json.mock.calls[0][0].source).toBe('Cotes en direct · 63e minute');
    expect(res.json.mock.calls[0][0].options[0]).toEqual({ type: 'win1', label: 'Arsenal gagne', odd: 1.45 });
    expect(lectureAvantMatch).not.toHaveBeenCalled();
  });

  it('en direct sans cote (marchés suspendus) : le dire, jamais les cotes figées', async () => {
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue(match('LIVE', 63) as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(null);
    const res = response();
    await getMatchOdds({ params: { matchId: 'm1' } } as any, res);
    expect(res.status).toHaveBeenCalledWith(422);
    expect(res.json.mock.calls[0][0].message).toContain('Cotes en direct indisponibles');
    expect(lectureAvantMatch).not.toHaveBeenCalled();
  });

  it('avant le match : l\'avant-match, comme toujours', async () => {
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue(match('SCHEDULED', -90) as any);
    const live = jest.spyOn(apiFootballInsights, 'getLiveOdds');
    const res = response();
    await getMatchOdds({ params: { matchId: 'm1' } } as any, res);
    expect(res.json).toHaveBeenCalledWith(avantMatch);
    expect(live).not.toHaveBeenCalled();
  });

  it('coup d\'envoi passé, statut pas encore à jour, rien en direct : l\'avant-match', async () => {
    jest.spyOn(prisma.match, 'findUnique').mockResolvedValue(match('SCHEDULED', 1) as any);
    jest.spyOn(apiFootballInsights, 'getLiveOdds').mockResolvedValue(null);
    const res = response();
    await getMatchOdds({ params: { matchId: 'm1' } } as any, res);
    expect(res.json).toHaveBeenCalledWith(avantMatch);
  });
});
