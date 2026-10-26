/**
 * Les alertes au choix pour chaque match suivi (27 octobre 2026) : 145
 * alertes de but pour 8 lues sur la semaine du 19 octobre. Chacun garde ce
 * qu'il veut — toutes par défaut.
 */
import { prisma } from '../lib/prisma';
import { CATEGORIES_ALERTE, choisirAlertes, lireAlertes, suiveursDuMatch } from '../services/suiveurs_match';
import { decrireSurBaseLocale } from './aides/base_locale';

describe('un pari en cours', () => {
  afterEach(() => jest.restoreAllMocks());

  it('sans suivi : toutes les alertes ; avec un suivi : son choix l\'emporte', async () => {
    // Base simulée : u1 suit avec « résultat » seulement, u2 a un pari sans suivre.
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockImplementation((async (args: any) =>
      args.where.alertes ? [] : [{ userId: 'u1' }]) as any);
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([
      { bankroll: { userId: 'u1' } }, { bankroll: { userId: 'u2' } }] as any);
    expect(await suiveursDuMatch('m', 'p', 'buts')).toEqual(['u2']);
  });
});

const marque = `banc-alertes-${Date.now()}`;
const comptes: Record<string, string> = {};
let match = '';

decrireSurBaseLocale('les alertes choisies', () => {
  beforeAll(async () => {
    for (const k of ['a', 'b', 'c', 'd']) {
      comptes[k] = (await prisma.user.create({
        data: { pseudo: `${marque}-${k}`, referralCode: `${marque.slice(-8)}${k}`.toUpperCase() } })).id;
    }
    match = (await prisma.match.create({ data: {
      externalId: Math.floor(Math.random() * 1e9) + 1e9, source: 'API_FOOTBALL', league: 'Premier League', leagueCode: 'PL',
      homeTeam: `Arsenal ${marque}`, awayTeam: 'Chelsea', matchDate: new Date(Date.now() + 3_600_000), status: 'SCHEDULED',
    } })).id;
    // a suit comme avant (toutes les alertes, par défaut) ; b, le résultat
    // seulement ; c, le match sans notification.
    await prisma.userFavoriteMatch.create({ data: { userId: comptes.a, matchId: match } });
    await prisma.userFavoriteMatch.create({ data: { userId: comptes.b, matchId: match, alertes: ['fin_de_match'] } });
    await prisma.userFavoriteMatch.create({ data: { userId: comptes.c, matchId: match, alertes: [] } });
  });
  afterAll(async () => {
    await prisma.match.deleteMany({ where: { id: match } });   // les suivis suivent (cascade)
    await prisma.user.deleteMany({ where: { id: { in: Object.values(comptes) } } });
  });

  const tri = (l: string[]) => [...l].sort();

  it('chaque alerte ne part qu\'à ceux qui l\'ont gardée', async () => {
    expect(await suiveursDuMatch(match, null, 'buts')).toEqual([comptes.a]);
    expect(tri(await suiveursDuMatch(match, null, 'fin_de_match'))).toEqual(tri([comptes.a, comptes.b]));
    // Sans catégorie : tous ceux qui suivent.
    expect(tri(await suiveursDuMatch(match, null))).toEqual(tri([comptes.a, comptes.b, comptes.c]));
  });

  it('lire : suivi et alertes ; un match pas encore suivi les a toutes', async () => {
    expect(await lireAlertes(comptes.a, match)).toEqual({ suivi: true, alertes: [...CATEGORIES_ALERTE] });
    expect(await lireAlertes(comptes.c, match)).toEqual({ suivi: true, alertes: [] });
    expect(await lireAlertes(comptes.d, match)).toEqual({ suivi: false, alertes: [...CATEGORIES_ALERTE] });
  });

  it('choisir : suit le match s\'il ne l\'était pas ; dans l\'ordre du catalogue, sans doublon', async () => {
    expect(await choisirAlertes(comptes.d, match, ['fin_de_match', 'buts', 'buts']))
      .toEqual({ suivi: true, alertes: ['buts', 'fin_de_match'] });
    expect(await suiveursDuMatch(match, null, 'buts')).toContain(comptes.d);
    expect(await suiveursDuMatch(match, null, 'mi_temps')).not.toContain(comptes.d);
  });

  it('une alerte inconnue ou un match inconnu est refusé', async () => {
    await expect(choisirAlertes(comptes.a, match, ['buts', 'pari'])).rejects.toMatchObject({ statut: 422 });
    await expect(choisirAlertes(comptes.a, match, 'buts')).rejects.toMatchObject({ statut: 422 });
    await expect(choisirAlertes(comptes.a, 'inconnu', ['buts'])).rejects.toMatchObject({ statut: 404 });
    await expect(lireAlertes(comptes.a, 'inconnu')).rejects.toMatchObject({ statut: 404 });
  });
});
