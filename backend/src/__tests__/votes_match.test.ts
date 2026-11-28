/**
 * « Qui va gagner ? » — le vote des fans avant le match (26 octobre 2026).
 * Un vote par compte et par match, modifiable jusqu'au coup d'envoi.
 */
import { prisma } from '../lib/prisma';
import { pourcentages, resumeVotes, voter } from '../services/votes_match.service';
import { decrireSurBaseLocale } from './aides/base_locale';

describe('des pourcentages qui font 100', () => {
  it.each([
    [[1, 1, 1], [34, 33, 33]],
    [[2, 1, 0], [67, 33, 0]],
    [[0, 0, 0], [0, 0, 0]],
    [[7, 2, 1], [70, 20, 10]],
    [[1, 0, 2], [33, 0, 67]],
  ])('%j → %j', (compte, attendu) => {
    const p = pourcentages(compte as [number, number, number]);
    expect(p).toEqual(attendu);
    if (attendu.some(Boolean)) expect(p[0] + p[1] + p[2]).toBe(100);
  });
});

const marque = `banc-votes-${Date.now()}`;
const HEURE = 3_600_000;
const comptes: string[] = [];
const matchs: string[] = [];

async function compte(n: string) {
  const u = await prisma.user.create({ data: { pseudo: `${marque}-${n}`, referralCode: `${marque.slice(-8)}${n}`.toUpperCase() } });
  comptes.push(u.id);
  return u.id;
}
async function match(heuresAvantCoupEnvoi: number, status: 'SCHEDULED' | 'LIVE' | 'FINISHED' = 'SCHEDULED') {
  const m = await prisma.match.create({ data: {
    externalId: Math.floor(Math.random() * 1e9) + 1e9, source: 'API_FOOTBALL', league: 'Premier League', leagueCode: 'PL',
    homeTeam: `Arsenal ${marque}`, awayTeam: 'Chelsea', matchDate: new Date(Date.now() + heuresAvantCoupEnvoi * HEURE), status,
  } });
  matchs.push(m.id);
  return m.id;
}

decrireSurBaseLocale('le vote des fans', () => {
  afterAll(async () => {
    await prisma.match.deleteMany({ where: { id: { in: matchs } } });   // les votes suivent (cascade)
    await prisma.user.deleteMany({ where: { id: { in: comptes } } });
  });

  it('chacun vote une fois, peut changer d\'avis ; la répartition et son propre vote', async () => {
    const m = await match(20);
    const [a, b, c] = [await compte('a'), await compte('b'), await compte('c')];
    expect(await resumeVotes(m, a)).toEqual({ ouvert: true, total: 0, dom: 0, nul: 0, ext: 0,
      pourcentages: { dom: 0, nul: 0, ext: 0 }, mon_vote: null });

    await voter(m, a, '1');
    await voter(m, b, '1');
    const r = await voter(m, c, 'N');
    expect(r).toMatchObject({ total: 3, dom: 2, nul: 1, ext: 0, pourcentages: { dom: 67, nul: 33, ext: 0 }, mon_vote: 'N' });

    // c change d'avis : toujours trois votes.
    const r2 = await voter(m, c, '2');
    expect(r2).toMatchObject({ total: 3, dom: 2, nul: 0, ext: 1, mon_vote: '2' });
    expect(await prisma.voteMatch.count({ where: { matchId: m } })).toBe(3);

    // Un invité voit la répartition, sans vote à lui.
    expect(await resumeVotes(m, null)).toMatchObject({ total: 3, mon_vote: null });
  });

  it('le match a commencé : votes clos, la répartition reste visible', async () => {
    const enCours = await match(-0.5, 'LIVE');
    const a = await compte('d');
    await expect(voter(enCours, a, '1')).rejects.toMatchObject({ statut: 409 });
    expect(await resumeVotes(enCours, a)).toMatchObject({ ouvert: false, total: 0 });
    // Coup d'envoi passé, statut pas encore relevé : clos aussi.
    const enRetard = await match(-0.1, 'SCHEDULED');
    await expect(voter(enRetard, a, '2')).rejects.toMatchObject({ statut: 409 });
  });

  it('un choix inconnu est refusé ; un match inconnu aussi', async () => {
    const m = await match(5);
    const a = await compte('e');
    await expect(voter(m, a, 'X')).rejects.toMatchObject({ statut: 422 });
    await expect(voter(m, a, 1)).rejects.toMatchObject({ statut: 422 });
    await expect(voter('inconnu', a, '1')).rejects.toMatchObject({ statut: 404 });
    expect(await resumeVotes('inconnu', a)).toBeNull();
  });

  it('un compte supprimé emporte ses votes', async () => {
    const m = await match(8);
    const f = await compte('f');
    await voter(m, f, '1');
    await prisma.user.delete({ where: { id: f } });
    comptes.splice(comptes.indexOf(f), 1);
    expect((await resumeVotes(m, null))!.total).toBe(0);
  });
});
