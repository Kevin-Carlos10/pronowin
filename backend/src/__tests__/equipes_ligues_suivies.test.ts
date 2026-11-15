/**
 * Les équipes et ligues suivies annoncent leurs matchs (15 novembre 2026) :
 * suivre une équipe ou une ligue ne faisait qu'afficher ses matchs dans
 * « Suivis », sans aucune alerte.
 */
import { prisma } from '../lib/prisma';
import {
  enregistrerSuivis, lireSuivis, suiveursDuMatch, suiveursEquipesLigues, MAX_SUIVIS,
} from '../services/suiveurs_match';

const contexte = {
  league: 'Premier League',
  homeTeamLogo: 'https://media.api-sports.io/football/teams/42.png',
  awayTeamLogo: 'https://media.api-sports.io/football/teams/49.png',
};

describe('qui reçoit les alertes d\'une équipe ou d\'une ligue suivie', () => {
  let equipes: jest.SpyInstance, ligues: jest.SpyInstance;
  beforeEach(() => {
    // u1 suit Arsenal (42) ; u2 suit la Premier League ; u3 suit Chelsea
    // (49) mais a coupé « Équipes suivies » ; u4 suit la ligue mais a coupé
    // « Ligues suivies ».
    equipes = jest.spyOn(prisma.userEquipeSuivie, 'findMany').mockResolvedValue([
      { userId: 'u1', user: { notificationPrefs: null } },
      { userId: 'u3', user: { notificationPrefs: { equipes_suivies: false } } },
    ] as any);
    ligues = jest.spyOn(prisma.userLigueSuivie, 'findMany').mockResolvedValue([
      { userId: 'u2', user: { notificationPrefs: { match: true } } },
      { userId: 'u4', user: { notificationPrefs: { ligues_suivies: false } } },
    ] as any);
  });
  afterEach(() => jest.restoreAllMocks());

  it('coup d\'envoi et résultat : équipes et ligue ; chacun peut couper les siennes', async () => {
    for (const c of ['coup_envoi', 'fin_de_match'] as const) {
      expect((await suiveursEquipesLigues(contexte, c)).sort()).toEqual(['u1', 'u2']);
    }
    // Les deux équipes du match, par l'identifiant de leur logo ; la ligue
    // par son nom ; jamais un compte supprimé.
    expect(equipes.mock.calls[0][0].where).toEqual({ equipeId: { in: [42, 49] }, user: { deletedAt: null } });
    expect(ligues.mock.calls[0][0].where).toEqual({ ligue: 'Premier League', user: { deletedAt: null } });
  });

  it('les buts : l\'équipe suivie seulement — ceux de toute une ligue feraient trop', async () => {
    expect(await suiveursEquipesLigues(contexte, 'buts')).toEqual(['u1']);
    expect(ligues).not.toHaveBeenCalled();
  });

  it('cartons, mi-temps, compositions, résumé : rien de plus que le suivi du match', async () => {
    for (const c of ['cartons', 'mi_temps', 'compositions', 'resume'] as const) {
      expect(await suiveursEquipesLigues(contexte, c)).toEqual([]);
    }
    expect(equipes).not.toHaveBeenCalled();
    expect(ligues).not.toHaveBeenCalled();
  });

  it('un match sans logo reconnaissable ni ligue ne coûte aucune requête', async () => {
    expect(await suiveursEquipesLigues({ homeTeamLogo: 'https://crests.football-data.org/57.png' }, 'buts')).toEqual([]);
    expect(equipes).not.toHaveBeenCalled();
  });

  it('qui suit aussi le match a fait son choix pour lui : c\'est lui qui compte', async () => {
    // u1 suit le match, sans l'alerte de but ; u2 n'a qu'un pari en cours.
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockImplementation((async (args: any) =>
      args.where.alertes ? [] : [{ userId: 'u1' }]) as any);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([]);
    expect(await suiveursDuMatch('m', 'p', 'buts', contexte)).toEqual([]);
    expect((await suiveursDuMatch('m', 'p', 'coup_envoi', contexte)).sort()).toEqual(['u2']);
    // Sans contexte (compositions, résumé), comme avant.
    expect(await suiveursDuMatch('m', 'p', 'buts')).toEqual([]);
  });
});

describe('les suivis sur le serveur', () => {
  let transaction: jest.SpyInstance;
  beforeEach(() => {
    transaction = jest.spyOn(prisma, '$transaction').mockResolvedValue([] as any);
    for (const m of [prisma.userLigueSuivie, prisma.userEquipeSuivie]) {
      jest.spyOn(m, 'deleteMany').mockReturnValue({} as any);
      jest.spyOn(m, 'createMany').mockReturnValue({} as any);
      jest.spyOn(m, 'findMany').mockResolvedValue([]);
    }
  });
  afterEach(() => jest.restoreAllMocks());

  it('lire : dans l\'ordre où ils ont été suivis, au format de l\'application', async () => {
    (prisma.userEquipeSuivie.findMany as jest.Mock).mockResolvedValue([
      { equipeId: 42, nom: 'Arsenal', logo: 'a.png', competition: 'Premier League' }]);
    (prisma.userLigueSuivie.findMany as jest.Mock).mockResolvedValue([{ ligue: 'La Liga' }]);
    expect(await lireSuivis('u')).toEqual({
      ligues: ['La Liga'], equipes: [{ id: 42, nom: 'Arsenal', logo: 'a.png', competition: 'Premier League' }],
    });
    expect((prisma.userLigueSuivie.findMany as jest.Mock).mock.calls[0][0])
      .toEqual({ where: { userId: 'u' }, orderBy: { createdAt: 'asc' } });
  });

  it('enregistrer : remplace la liste reçue, sans doublon, dans l\'ordre ; l\'autre reste', async () => {
    await enregistrerSuivis('u', { ligues: ['La Liga', 'Serie A', 'La Liga'] });
    const cree = (prisma.userLigueSuivie.createMany as jest.Mock).mock.calls[0][0].data;
    expect(cree.map((l: any) => l.ligue)).toEqual(['La Liga', 'Serie A']);
    expect(cree[0].createdAt.getTime()).toBeLessThan(cree[1].createdAt.getTime());
    expect(prisma.userLigueSuivie.deleteMany).toHaveBeenCalledWith({ where: { userId: 'u' } });
    expect(prisma.userEquipeSuivie.deleteMany).not.toHaveBeenCalled();
    expect(transaction.mock.calls[0][0]).toHaveLength(2);

    await enregistrerSuivis('u', { equipes: [
      { id: 42, nom: 'Arsenal', logo: 'a.png' }, { id: 42, nom: 'Arsenal' }, { id: 49, nom: 'Chelsea', competition: null }] });
    expect((prisma.userEquipeSuivie.createMany as jest.Mock).mock.calls[0][0].data
      .map(({ createdAt, ...e }: any) => e)).toEqual([
      { userId: 'u', equipeId: 42, nom: 'Arsenal', logo: 'a.png', competition: null },
      { userId: 'u', equipeId: 49, nom: 'Chelsea', logo: null, competition: null },
    ]);
    // Une liste vide se suit aussi : on ne suit plus rien.
    await enregistrerSuivis('u', { ligues: [] });
    expect(transaction).toHaveBeenCalledTimes(3);
  });

  it('une liste invalide est refusée, sans rien écrire', async () => {
    const invalides: unknown[] = [
      {}, null, 'La Liga',
      { ligues: 'La Liga' }, { ligues: [''] }, { ligues: [42] }, { ligues: ['x'.repeat(121)] },
      { ligues: Array.from({ length: MAX_SUIVIS + 1 }, (_, i) => `L${i}`) },
      { equipes: [{ id: '42', nom: 'Arsenal' }] }, { equipes: [{ id: 4.2, nom: 'Arsenal' }] },
      { equipes: [{ id: 42 }] }, { equipes: [{ id: 42, nom: 'Arsenal', logo: 7 }] }, { equipes: [null] },
    ];
    for (const corps of invalides) {
      await expect(enregistrerSuivis('u', corps)).rejects.toMatchObject({ statut: 422 });
    }
    expect(transaction).not.toHaveBeenCalled();
  });
});
