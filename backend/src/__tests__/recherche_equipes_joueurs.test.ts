jest.mock('../lib/prisma', () => ({ prisma: { match: { findMany: jest.fn() } } }));
import { prisma } from '../lib/prisma';
import { idEquipeDepuisLogo, rechercherEquipes, rechercherJoueurs, rechercherCompetitions } from '../services/recherche_equipes_joueurs.service';
import { _reinitialiser } from '../services/etat_taches';

const logo = (id: number) => `https://media.api-sports.io/football/teams/${id}.png`;
const ligne = (dom: string, idDom: number, ext: string, idExt: number, code = 'BL1') => ({
  homeTeam: dom, awayTeam: ext, homeTeamFull: null, awayTeamFull: null,
  homeTeamLogo: logo(idDom), awayTeamLogo: logo(idExt), leagueCountry: code,
});

beforeEach(() => { jest.clearAllMocks(); _reinitialiser(); });

describe('recherche d’équipes et de joueurs (7 novembre 2026)', () => {
  it('l’identifiant API-Football se lit dans l’adresse du logo', () => {
    expect(idEquipeDepuisLogo(logo(157))).toBe(157);
    expect(idEquipeDepuisLogo('https://crests.football-data.org/5.svg')).toBeNull();
    expect(idEquipeDepuisLogo(null)).toBeNull();
  });

  it('équipes : sans doublon, sans l’adversaire, celles qui commencent par le terme d’abord', async () => {
    (prisma.match.findMany as jest.Mock).mockResolvedValue([
      ligne('FC Bayern München', 157, 'Mainz 05', 164),
      ligne('Bayer Leverkusen', 168, 'FC Bayern München', 157),
      ligne('Bayern II', 999, 'Unterhaching', 1000, 'BL3'),
    ]);
    const r = await rechercherEquipes('bayer');
    expect(r.map(e => e.nom)).toEqual(['Bayer Leverkusen', 'Bayern II', 'FC Bayern München']);
    expect(r[2]).toEqual({ id: 157, nom: 'FC Bayern München', logo: logo(157), competition: 'BL1' });
  });

  it('équipes : les accents ne gênent pas la comparaison finale ; une lettre ne cherche rien', async () => {
    (prisma.match.findMany as jest.Mock).mockResolvedValue([ligne('Atlético Madrid', 530, 'Getafe', 546, 'PD')]);
    expect((await rechercherEquipes('atletico')).map(e => e.id)).toEqual([530]);
    expect(await rechercherEquipes('a')).toEqual([]);
  });

  it('joueurs : dès trois lettres, au format de l’application ; fournisseur en panne : rien', async () => {
    const c = { get: jest.fn(async () => ({ data: { errors: [], response: [
      { player: { id: 184, name: 'H. Kane', photo: 'p184', position: 'Attacker', nationality: 'England', age: 33 } },
      { player: { id: null, name: 'sans id' } },
    ] } })) };
    expect(await rechercherJoueurs(c as any, 'ka')).toEqual([]);
    expect(c.get).not.toHaveBeenCalled();
    expect(await rechercherJoueurs(c as any, 'kane')).toEqual([
      { id: 184, nom: 'H. Kane', photo: 'p184', poste: 'Attacker', nationalite: 'England', age: 33 },
    ]);
    expect(c.get).toHaveBeenCalledWith('/players/profiles', { params: { search: 'kane' } });

    const enPanne = { get: jest.fn(async () => { throw Error('offline'); }) };
    expect(await rechercherJoueurs(enPanne as any, 'mbappe')).toEqual([]);
  });
});

describe('recherche de compétitions (15 novembre 2026)', () => {
  it('par le nom, au format de l\u2019application ; celles qui commencent par le terme d\u2019abord', async () => {
    (prisma.match.findMany as jest.Mock).mockResolvedValue([
      { league: 'Liga Portugal', leagueCode: 'AF_94', leagueLogo: 'pt.png', leagueCountry: 'Portugal' },
      { league: 'La Liga', leagueCode: 'PD', leagueLogo: 'es.png', leagueCountry: 'Spain' },
    ]);
    const r = await rechercherCompetitions('liga');
    expect(r.map(c => c.code)).toEqual(['AF_94', 'PD']);
    expect(r[1]).toEqual({ code: 'PD', nom: 'La Liga', logo: 'es.png', pays: 'Spain' });
    const requete = (prisma.match.findMany as jest.Mock).mock.calls[0][0];
    expect(requete.distinct).toEqual(['leagueCode']);
  });

  it('les noms français mènent au code : « ligue des champions » trouve la CL', async () => {
    (prisma.match.findMany as jest.Mock).mockResolvedValue([]);
    await rechercherCompetitions('Ligue des champ');
    const ou = (prisma.match.findMany as jest.Mock).mock.calls[0][0].where.OR;
    expect(ou).toContainEqual({ leagueCode: { in: ['CL'] } });
  });

  it('une lettre ne cherche rien', async () => {
    expect(await rechercherCompetitions('l')).toEqual([]);
    expect(prisma.match.findMany).not.toHaveBeenCalled();
  });
});
