jest.mock('../lib/prisma', () => ({ prisma: {
  pronostic: { findUnique: jest.fn(), findFirst: jest.fn() },
  match: { findUnique: jest.fn() }, user: { findUnique: jest.fn() },
} }));
jest.mock('../services/pronostics.service');
jest.mock('../services/notification.service');
jest.mock('../services/football_data.service');
jest.mock('../services/api_football.service', () => ({
  apiFootballService: { getMatchInfo: jest.fn(), getMatchStats: jest.fn(), getLineups: jest.fn(), getStandings: jest.fn(),
    getFormeRecente: jest.fn(), getOdds1xBet: jest.fn() },
  apiFootballInsights: { getLiveOdds: jest.fn() },
}));
import { prisma } from '../lib/prisma';
import { apiFootballService } from '../services/api_football.service';
import { getMatchInfo, getPronosticDetail, getPronosticScore, getMatchStats, getLineups, getStandings, getFormeRecente, getCotes } from '../controllers/pronostics.controller';
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
