import { ClassementsFootball } from '../services/classements_football.service';
import { MatchLiveService } from '../services/match_live.service';
import { FichesEquipes } from '../services/fiche_equipe.service';
import { FichesJoueurs } from '../services/fiche_joueur.service';
import { enrichissementsFootball } from '../services/enrichissements_football';
import { noterQuota, _reinitialiser } from '../services/etat_taches';

const ok = (response: any) => ({ data: { errors: [], response } });
const fixture = { fixture: { id: 42 }, league: { id: 999, season: 2024 },
  teams: { home: { id: 3, name: 'Home' }, away: { id: 4, name: 'Away' } } };
const seasons = [{ year: 2024, start: '2024-08-01', end: '2025-05-31', coverage: { standings: true } },
 { year: 2026, current: true, start: '2026-08-01', end: '2027-05-31' }];
const row = (id: number, group: string) => ({ rank: 1, team: { id, name: 'Team '+id }, group,
  points: 12, all: { played: 5, win: 4, draw: 0, lose: 1 }, goalsDiff: 6 });
const payload = [{ league: { id: 999, season: 2024, standings: [[row(1,'Group A')],[row(3,'Group B'),row(4,'Group B')]] } }];
beforeEach(() => { jest.useFakeTimers(); jest.setSystemTime(new Date('2026-10-05T12:00:00Z')); _reinitialiser(); });
afterEach(() => { jest.useRealTimers(); _reinitialiser(); });

it('toutes compétitions et tous groupes, saison historique et équipes identifiées par id', async () => {
 const c={get:jest.fn(async (path:string)=>ok(path==='/leagues' ? [{league:{id:999},seasons}] : payload))};
 const svc=new ClassementsFootball(c as any,async()=>fixture);
 const results=await Promise.all(Array.from({length:20},()=>svc.get({fixtureId:42,leagueId:39,matchDate:new Date()})));
 expect(c.get).toHaveBeenCalledTimes(2);
 expect(c.get).toHaveBeenCalledWith('/standings',{params:{league:999,season:2024}});
 expect(results[0].status).toBe('available');
 expect(results[0].rows.map(r=>[r.groupName,r.isMatchTeam])).toEqual([['Group A',false],['Group B',true],['Group B',true]]);
 expect(results[0].rows.every(r=>r.season===2024)).toBe(true);
});
it('ancien fournisseur: saison couvrant la date, jamais la saison courante', async () => {
 const c={get:jest.fn(async(path:string)=>ok(path==='/leagues'?[{league:{id:999},seasons}]:payload))};
 const svc=new ClassementsFootball(c as any,async()=>null);
 expect((await svc.get({leagueId:999,matchDate:new Date('2025-02-01')})).season).toBe(2024);
 expect((await svc.get({leagueId:999,matchDate:new Date('2023-02-01')})).status).toBe('unavailable');
 expect(c.get).toHaveBeenCalledTimes(2);
});
it('couverture absente: pas de requête inutile de classement', async () => {
 const c={get:jest.fn(async()=>ok([{league:{id:999},seasons:[{year:2024,coverage:{standings:false}}]}]))};
 expect((await new ClassementsFootball(c as any,async()=>fixture).get({fixtureId:42})).status).toBe('unsupported');
 expect(c.get).toHaveBeenCalledTimes(1);
});
it('liste vide valide, quota dépassé et mauvais championnat restent distincts', async () => {
 for(const [body,expected] of [[ok([]),'pending'],[{data:{errors:{requests:'quota'},response:[]}},'unavailable'],[ok([{league:{id:100,season:2024,standings:[]}}]),'unavailable']] as const){
  const c={get:jest.fn(async(path:string)=>path==='/leagues'?ok([{league:{id:999},seasons}]):body)};
  const svc=new ClassementsFootball(c as any,async()=>fixture);
  expect((await svc.get({fixtureId:42})).status).toBe(expected);
  await svc.get({fixtureId:42}); expect(c.get).toHaveBeenCalledTimes(2);
 }
});
it('un classement ancien reste marqué périmé pendant une brève panne',async()=>{
 let down=false;
 const c={get:jest.fn(async(path:string)=>{
   if(path==='/leagues')return ok([{league:{id:999},seasons}]);
   if(down)throw Error('offline'); return ok(payload);
 })};
 const svc=new ClassementsFootball(c as any,async()=>fixture);
 const first=await svc.get({fixtureId:42}); down=true; jest.advanceTimersByTime(15*60_000+1);
 const next=await svc.get({fixtureId:42});
 expect(next.rows[0]).toMatchObject({stale:true,updatedAt:first.rows[0].updatedAt});
});
it('la couverture des événements et des statistiques est propre à la saison',async()=>{
 const c={get:jest.fn(async(path:string)=>ok(path==='/fixtures'?[fixture]:[{league:{id:999},
  seasons:[{year:2024,coverage:{fixtures:{events:false,statistics_fixtures:false}}}]}]))};
 const svc=new MatchLiveService(c as any,()=>true);
 expect(await svc.stats(42,'LIVE')).toMatchObject({events_status:'unsupported',stats_status:'unsupported',events:[],stats:[]});
 expect(c.get).toHaveBeenCalledTimes(2);
});
it('HTTP 200 en erreur ne devient pas une équipe introuvable',async()=>{
 let down=true;
 const c={get:jest.fn(async(path:string)=>down?{data:{errors:{requests:'quota'},response:[]}}:ok(path==='/teams'?[{team:{id:1,name:'A'}}]:[]))};
 const svc=new FichesEquipes(c as any,()=>true);
 expect(await svc.fiche(1)).toBeNull(); expect(await svc.fiche(1)).toBeNull(); expect(c.get).toHaveBeenCalledTimes(1);
 down=false; jest.advanceTimersByTime(30_001);
 expect(await svc.fiche(1)).toMatchObject({name:'A',partial:false});
});
it('la fiche équipe partielle se répare sans recharger les sections valides',async()=>{
 let down=true;
 const c={get:jest.fn(async(path:string)=>{
  if(path==='/teams')return ok([{team:{id:1,name:'A'}}]);
  if(path==='/coachs' && down)throw Error('offline');
  return ok(path==='/coachs'?[{name:'Coach'}]:[]);
 })};
 const svc=new FichesEquipes(c as any,()=>true);
 const first=await Promise.all(Array.from({length:10},()=>svc.fiche(1)));
 expect(first[0]).toMatchObject({partial:true}); expect(c.get).toHaveBeenCalledTimes(3);
 down=false; jest.advanceTimersByTime(30_001);
 expect(await svc.fiche(1)).toMatchObject({partial:false,coach:{name:'Coach'}});
 expect(c.get).toHaveBeenCalledTimes(4);
});
it('joueurs: erreur de profil distincte et reprise des seules absences en échec',async()=>{
 let mode='profile';
 const c={get:jest.fn(async(path:string)=>{
  if(path==='/players')return mode==='profile'?{data:{errors:['quota'],response:[]}}:ok([{player:{id:7,name:'X'},statistics:[]}]);
  if(path==='/sidelined'&&mode==='sidelined')throw Error('offline');
  return ok([]);
 })};
 const svc=new FichesJoueurs(c as any,()=>true);
 expect(await svc.fiche(7,2024)).toBeNull();
 mode='sidelined';jest.advanceTimersByTime(30_001);
 expect(await svc.fiche(7,2024)).toMatchObject({partial:true});
 const calls=c.get.mock.calls.length;mode='ok';jest.advanceTimersByTime(30_001);
 expect(await svc.fiche(7,2024)).toMatchObject({partial:false});expect(c.get).toHaveBeenCalledTimes(calls+1);
});
it('réserve du quota: aucun nouvel enrichissement, reprise le lendemain',async()=>{
 const c={get:jest.fn(async()=>ok([]))};const api=enrichissementsFootball(c as any);
 noterQuota({'x-ratelimit-requests-limit':100,'x-ratelimit-requests-remaining':10});
 await expect(api.get('/teams',{id:1},60_000)).rejects.toThrow();expect(c.get).not.toHaveBeenCalled();
 jest.advanceTimersByTime(24*60*60_000);await expect(api.get('/teams',{id:1},60_000)).resolves.toEqual([]);
 expect(c.get).toHaveBeenCalledTimes(1);
});
it('réponses malformées et statistiques objet en erreur ne sont pas des données vides valides',async()=>{
 const c={get:jest.fn(async()=>({data:{errors:{message:'failed'},response:{}}}))};
 const api=enrichissementsFootball(c as any);
 await expect(api.object('/teams/statistics',{team:1},60_000)).rejects.toThrow();
 await expect(api.get('/teams',{id:1},60_000)).rejects.toThrow();
});

it('les identifiants de groupe restent stables quand le fournisseur change leur ordre',async()=>{
 let reverse=false;
 const c={get:jest.fn(async(path:string)=>{
  if(path==='/leagues')return ok([{league:{id:999},seasons}]);
  const groups=payload[0].league.standings;
  return ok([{league:{id:999,season:2024,standings:reverse?[...groups].reverse():groups}}]);
 })};
 const svc=new ClassementsFootball(c as any,async()=>fixture);
 const first=await svc.get({fixtureId:42});reverse=true;jest.advanceTimersByTime(15*60_000+1);
 const next=await svc.get({fixtureId:42});
 expect(next.rows.find(r=>r.teamId===3)?.groupId).toBe(first.rows.find(r=>r.teamId===3)?.groupId);
});
