jest.mock('../lib/prisma', () => ({ prisma: {
  pronostic: { findUnique: jest.fn(), findFirst: jest.fn() },
  match: { findUnique: jest.fn(), findFirst: jest.fn() }, user: { findUnique: jest.fn() },
} }));
jest.mock('../services/pronostics.service');
jest.mock('../services/notification.service');
jest.mock('../services/football_data.service');
jest.mock('../services/api_football.service', () => ({
  apiFootballService: { getMatchInfo: jest.fn(), getMatchStats: jest.fn(), getLineups: jest.fn(), getStandings: jest.fn(),
    getFormeRecente: jest.fn(), getOdds1xBet: jest.fn(), getH2H: jest.fn(), getFixtureOfficielle: jest.fn() },
  apiFootballInsights: { getLiveOdds: jest.fn() },
  LEAGUE_INFO: (code: string) => (code === 'PL' ? { id: 39, season: 2026 } : null),
}));
import { prisma } from '../lib/prisma';
import { apiFootballService } from '../services/api_football.service';
import { getMatchInfo, getPronosticDetail, getPronosticScore, getMatchStats, getLineups, getStandings, getFormeRecente, getCotes, getClassementLigue, getConfrontation, getH2H } from '../controllers/pronostics.controller';
const match = { id: 'm', status: 'LIVE', externalId: 42, source: 'API_FOOTBALL', homeTeam: 'A', awayTeam: 'B',
  league: 'Premier League', leagueCode: 'PL', matchDate: new Date(), homeScore: 2, awayScore: 1, elapsedMinutes: 45 };
const response = () => { const r: any = { json: jest.fn() }; r.status = jest.fn(() => r); return r; };
beforeEach(() => {
  jest.clearAllMocks();
  (prisma.pronostic.findUnique as jest.Mock).mockResolvedValue(null);
  (prisma.pronostic.findFirst as jest.Mock).mockResolvedValue(null);
  (prisma.match.findUnique as jest.Mock).mockResolvedValue(match);
});
it('invité: détail et score sans pronostic', async () => {
  const r = response(); await getPronosticDetail({ params: { id: 'm' } } as any, r);
  expect(r.json).toHaveBeenCalledWith(expect.objectContaining({ id: 'm', has_pronostic: false, home_score: 2 }));
  const score = response(); await getPronosticScore({ params: { id: 'm' } } as any, score);
  expect(score.json).toHaveBeenCalledWith({ homeScore: 2, awayScore: 1, status: 'LIVE', elapsed: 45 });
});
it('stats live: utilise l’identifiant exact et accepte un match sans pronostic', async () => {
  (apiFootballService.getMatchStats as jest.Mock).mockResolvedValue({ stats: [], events: [] });
  const r=response(); await getMatchStats({ params: { id: 'm' } } as any, r);
  expect(apiFootballService.getMatchStats).toHaveBeenCalledWith(42, 'LIVE');
  expect(r.status).not.toHaveBeenCalled();
});
it('avant le coup d’envoi et autre fournisseur: aucun appel de statistiques', async () => {
  (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, status: 'SCHEDULED' });
  const r=response(); await getMatchStats({ params: { id: 'm' } } as any, r);
  expect(r.status).toHaveBeenCalledWith(400);
  (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, source: 'FOOTBALL_DATA' });
  const other=response(); await getMatchStats({ params: { id: 'm' } } as any, other);
  expect(other.status).toHaveBeenCalledWith(404);
  expect(apiFootballService.getMatchStats).not.toHaveBeenCalled();
});
it('les compositions fonctionnent avec les anciens liens par identifiant de pronostic', async () => {
  (prisma.pronostic.findUnique as jest.Mock).mockResolvedValue({ id: 'p', match });
  (apiFootballService.getLineups as jest.Mock).mockResolvedValue({ available: true });
  await getLineups({ params: { id: 'p' } } as any, response());
  expect(apiFootballService.getLineups).toHaveBeenCalledWith('A','B',match.matchDate.toISOString().split('T')[0],42);
});
it('un pronostic brouillon ne fuit pas dans le nouveau détail public', async () => {
  (prisma.pronostic.findFirst as jest.Mock).mockResolvedValue({ id: 'p', isPublished: false, analystNote: 'secret', match });
  const r=response(); await getPronosticDetail({ params: { id: 'm' } } as any, r);
  expect(r.json.mock.calls[0][0].analyst_note).toBeUndefined();
  expect(r.json.mock.calls[0][0].has_pronostic).toBe(false);
});

it('classements: saison du match et identifiant fournisseur transmis, tous groupes sur demande',async()=>{
 (apiFootballService.getStandings as jest.Mock).mockResolvedValue({status:'available',rows:[
  {groupId:'a',isMatchTeam:false},{groupId:'b',isMatchTeam:true},{groupId:'b',isMatchTeam:false}]});
 const full=response();await getStandings({params:{id:'m'},query:{groups:'all'}} as any,full);
 expect(full.json.mock.calls[0][0]).toHaveLength(3);
 expect(apiFootballService.getStandings).toHaveBeenCalledWith('PL',match.matchDate,42);
 const legacy=response();await getStandings({params:{id:'m'},query:{}} as any,legacy);
 expect(legacy.json.mock.calls[0][0]).toHaveLength(2);
 for(const [status,code] of [['unsupported',404],['unavailable',503]] as const){
  (apiFootballService.getStandings as jest.Mock).mockResolvedValue({status,rows:[]});
  const r=response();await getStandings({params:{id:'m'},query:{}} as any,r);expect(r.status).toHaveBeenCalledWith(code);
 }
});

it('informations du match: accès public, identifiant exact et indisponibilité explicite', async () => {
  (apiFootballService.getMatchInfo as jest.Mock).mockResolvedValue({ phase: 'PEN', referee: 'R' });
  const r=response(); await getMatchInfo({params:{id:'m'}} as any,r);
  expect(apiFootballService.getMatchInfo).toHaveBeenCalledWith(42,'LIVE',match.matchDate);
  expect(r.json).toHaveBeenCalledWith({phase:'PEN',referee:'R'});
  (apiFootballService.getMatchInfo as jest.Mock).mockResolvedValue(null);
  const down=response(); await getMatchInfo({params:{id:'m'}} as any,down); expect(down.status).toHaveBeenCalledWith(503);
  jest.clearAllMocks();
  (prisma.match.findUnique as jest.Mock).mockResolvedValue({...match,source:'OTHER'});
  const other=response(); await getMatchInfo({params:{id:'m'}} as any,other); expect(other.status).toHaveBeenCalledWith(404);
  expect(apiFootballService.getMatchInfo).not.toHaveBeenCalled();
});

it('forme récente: identifiant fournisseur, indisponibilité explicite, autre fournisseur sans appel', async () => {
  (apiFootballService.getFormeRecente as jest.Mock).mockResolvedValue({ home: [], away: [] });
  const r=response(); await getFormeRecente({params:{id:'m'}} as any,r);
  expect(apiFootballService.getFormeRecente).toHaveBeenCalledWith(42);
  expect(r.json).toHaveBeenCalledWith({ home: [], away: [] });
  (apiFootballService.getFormeRecente as jest.Mock).mockResolvedValue(null);
  const down=response(); await getFormeRecente({params:{id:'m'}} as any,down); expect(down.status).toHaveBeenCalledWith(503);
  jest.clearAllMocks();
  (prisma.match.findUnique as jest.Mock).mockResolvedValue({...match,source:'OTHER'});
  const other=response(); await getFormeRecente({params:{id:'m'}} as any,other); expect(other.status).toHaveBeenCalledWith(404);
  expect(apiFootballService.getFormeRecente).not.toHaveBeenCalled();
});

it('cotes: tous les marchés avant le coup d’envoi, sans nom de bookmaker ni type interne', async () => {
  (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, status: 'SCHEDULED' });
  (apiFootballService.getOdds1xBet as jest.Mock).mockResolvedValue({ source: '1xBet', options: [{ type: 'win1' }],
    markets: [{ name: 'Match Winner', values: [{ value: 'Home', odd: 1.8, type: 'win1' }, { value: 'Draw', odd: 3.4 }] }] });
  const r=response(); await getCotes({params:{id:'m'}} as any,r);
  expect(apiFootballService.getOdds1xBet).toHaveBeenCalledWith('A','B',match.matchDate.toISOString().slice(0,10),42);
  expect(r.json).toHaveBeenCalledWith({ markets: [{ name: 'Match Winner', values: [{ value: 'Home', odd: 1.8 }, { value: 'Draw', odd: 3.4 }] }] });
  expect(JSON.stringify(r.json.mock.calls[0][0])).not.toMatch(/1xBet/);
  (apiFootballService.getOdds1xBet as jest.Mock).mockResolvedValue(null);
  const down=response(); await getCotes({params:{id:'m'}} as any,down); expect(down.status).toHaveBeenCalledWith(503);
});

it('cotes: fermées une fois le match commencé, et pour un autre fournisseur', async () => {
  for (const m of [match, { ...match, status: 'FINISHED' }, { ...match, status: 'SCHEDULED', source: 'OTHER' }]) {
    (prisma.match.findUnique as jest.Mock).mockResolvedValue(m);
    const r=response(); await getCotes({params:{id:'m'}} as any,r); expect(r.status).toHaveBeenCalledWith(404);
  }
  expect(apiFootballService.getOdds1xBet).not.toHaveBeenCalled();
});

it("classement d'une compétition sans passer par un match (page de compétition, 10 novembre 2026)", async () => {
  (apiFootballService.getStandings as jest.Mock).mockResolvedValue({ status: 'available', rows: [{ groupId: '0', rank: 1 }] });
  const r = response(); await getClassementLigue({ query: { league: 'PL' } } as any, r);
  expect(apiFootballService.getStandings).toHaveBeenCalledWith('PL', expect.any(Date));
  expect(r.json).toHaveBeenCalledWith([{ groupId: '0', rank: 1 }]);
  for (const code of [undefined, '', 'pl; drop', 'X']) {
    const bad = response(); await getClassementLigue({ query: { league: code } } as any, bad);
    expect(bad.status).toHaveBeenCalledWith(400);
  }
  for (const [status, attendu] of [['unsupported', 404], ['unavailable', 503]] as const) {
    (apiFootballService.getStandings as jest.Mock).mockResolvedValue({ status, rows: [] });
    (prisma.match.findFirst as jest.Mock).mockResolvedValue({ id: 'x' });
    const e = response(); await getClassementLigue({ query: { league: 'AF_3' } } as any, e);
    expect(e.status).toHaveBeenCalledWith(attendu);
  }
  // Un code inventé, sans match en base : pas d'appel au fournisseur.
  jest.clearAllMocks();
  (prisma.match.findFirst as jest.Mock).mockResolvedValue(null);
  const invente = response(); await getClassementLigue({ query: { league: 'AF_99999' } } as any, invente);
  expect(invente.status).toHaveBeenCalledWith(404);
  expect(apiFootballService.getStandings).not.toHaveBeenCalled();
});

describe('le détail d\u2019une confrontation passée (15 novembre 2026)', () => {
  const h2h = {
    aggregates: { numberOfMatches: 1, homeTeam: { id: 1, name: 'A', wins: 1, draws: 0, losses: 0 },
      awayTeam: { id: 2, name: 'B', wins: 0, draws: 0, losses: 1 } },
    matches: [
      { id: 777, utcDate: '2025-03-01T20:00:00Z', status: 'FINISHED', competition: { name: 'Premier League', code: 'PL' },
        homeTeam: { id: 1, name: 'A', shortName: 'A' }, awayTeam: { id: 2, name: 'B', shortName: 'B' },
        score: { winner: 'HOME_TEAM', fullTime: { home: 2, away: 1 } } },
      { id: 888, utcDate: '2026-12-01T20:00:00Z', status: 'SCHEDULED', competition: { name: 'Premier League', code: 'PL' },
        homeTeam: { id: 2, name: 'B', shortName: 'B' }, awayTeam: { id: 1, name: 'A', shortName: 'A' },
        score: { winner: null, fullTime: { home: null, away: null } } },
    ],
  };
  const fixture = {
    fixture: { id: 777, date: '2025-03-01T20:00:00+00:00', venue: { name: 'Stade' }, referee: 'M. Arbitre' },
    league: { name: 'Premier League', logo: 'l.png', round: 'Regular Season - 27' },
    teams: { home: { name: 'A', logo: 'a.png' }, away: { name: 'B', logo: 'b.png' } },
    goals: { home: 2, away: 1 }, score: { halftime: { home: 1, away: 0 } },
  };
  beforeEach(() => {
    (apiFootballService.getH2H as jest.Mock).mockResolvedValue(h2h);
    (apiFootballService.getFixtureOfficielle as jest.Mock).mockResolvedValue(fixture);
    (apiFootballService.getMatchStats as jest.Mock).mockResolvedValue({ fixture_id: 777, events: [], stats: [], home_team: 'A', away_team: 'B' });
    (prisma.match.findFirst as jest.Mock).mockResolvedValue(null);
  });

  it('la liste des confrontations porte l\u2019identifiant de chaque rencontre', async () => {
    (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, source: 'API_FOOTBALL' });
    const r = response(); await getH2H({ params: { id: 'm' } } as any, r);
    expect(r.json.mock.calls[0][0].matches[0].fixture_id).toBe(777);
  });

  it('score, mi-temps, faits et statistiques d\u2019une rencontre du face-à-face', async () => {
    (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, source: 'API_FOOTBALL' });
    (prisma.match.findFirst as jest.Mock).mockResolvedValue({ id: 'locale' });
    const r = response(); await getConfrontation({ params: { id: 'm', fixtureId: '777' } } as any, r);
    expect(r.status).not.toHaveBeenCalled();
    expect(r.json).toHaveBeenCalledWith(expect.objectContaining({
      fixture_id: 777, match_id: 'locale', home_score: 2, away_score: 1, ht_home: 1, ht_away: 0,
      venue: 'Stade', round: 'Regular Season - 27', home_logo: 'a.png',
    }));
    expect(apiFootballService.getMatchStats).toHaveBeenCalledWith(777, 'FINISHED');
  });

  it('une rencontre hors du face-à-face, ou pas encore jouée, n\u2019est pas servie : pas d\u2019appel au fournisseur', async () => {
    (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, source: 'API_FOOTBALL' });
    for (const id of ['999', '888']) {
      const r = response(); await getConfrontation({ params: { id: 'm', fixtureId: id } } as any, r);
      expect(r.status).toHaveBeenCalledWith(404);
    }
    expect(apiFootballService.getFixtureOfficielle).not.toHaveBeenCalled();
    const invalide = response(); await getConfrontation({ params: { id: 'm', fixtureId: 'abc' } } as any, invalide);
    expect(invalide.status).toHaveBeenCalledWith(400);
  });

  it('un match d\u2019un autre fournisseur n\u2019a pas de détail de confrontation', async () => {
    (prisma.match.findUnique as jest.Mock).mockResolvedValue({ ...match, source: 'FOOTBALL_DATA' });
    const r = response(); await getConfrontation({ params: { id: 'm', fixtureId: '777' } } as any, r);
    expect(r.status).toHaveBeenCalledWith(404);
    expect(apiFootballService.getH2H).not.toHaveBeenCalled();
  });
});
