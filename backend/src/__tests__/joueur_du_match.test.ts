/**
 * « Joueur du match » — le vote des fans (8 novembre 2026).
 */
jest.mock('../lib/prisma', () => {
  const votes: any[] = [];
  const matchs: Record<string, any> = {};
  return {
    prisma: {
      match: { findUnique: jest.fn(async ({ where }: any) => matchs[where.id] ?? null) },
      pronostic: { findUnique: jest.fn(async () => null) },
      voteJoueurDuMatch: {
        groupBy: jest.fn(async ({ where }: any) => {
          const g = new Map<string, any>();
          for (const v of votes.filter(v => v.matchId === where.matchId)) {
            const cle = `${v.joueurId}|${v.joueurNom}|${v.equipe}`;
            const e = g.get(cle) ?? { joueurId: v.joueurId, joueurNom: v.joueurNom, equipe: v.equipe, _count: { _all: 0 } };
            e._count._all++;
            g.set(cle, e);
          }
          return [...g.values()];
        }),
        findUnique: jest.fn(async ({ where }: any) =>
          votes.find(v => v.matchId === where.matchId_userId.matchId && v.userId === where.matchId_userId.userId) ?? null),
        upsert: jest.fn(async ({ where, create, update }: any) => {
          const v = votes.find(x => x.matchId === where.matchId_userId.matchId && x.userId === where.matchId_userId.userId);
          if (v) Object.assign(v, update); else votes.push({ ...create });
        }),
      },
    },
    _votes: votes, _matchs: matchs,
  };
});

import {
  etatVote, resumeJoueurDuMatch, voterJoueur, remplacerLecteurJoueurs, MINUTE_OUVERTURE,
} from '../services/joueur_du_match.service';

const { _votes, _matchs } = require('../lib/prisma');

const COUP_ENVOI = new Date('2026-11-08T16:30:00Z');
const match = (status: string, minute: number | null) => ({
  id: 'm1', status, matchDate: COUP_ENVOI, elapsedMinutes: minute, source: 'API_FOOTBALL', externalId: 1208021,
});
const apres = (h: number) => new Date(COUP_ENVOI.getTime() + h * 3600_000);

beforeEach(() => {
  _votes.length = 0;
  remplacerLecteurJoueurs(async () => [
    { id: 10, name: 'Nicolas Jackson', team: 'away' },
    { id: 11, name: 'Morgan Rogers', team: 'away' },
    { id: 20, name: 'Bruno Fernandes', team: 'home' },
  ]);
});

describe('ouverture', () => {
  it(`à la ${MINUTE_OUVERTURE}e minute, puis trente heures après le coup d'envoi`, () => {
    expect(etatVote(match('SCHEDULED', null))).toBe('indisponible');
    expect(etatVote(match('LIVE', 79))).toBe('bientot');
    expect(etatVote(match('LIVE', 80))).toBe('ouvert');
    expect(etatVote(match('FINISHED', 90), apres(29))).toBe('ouvert');
    expect(etatVote(match('FINISHED', 90), apres(31))).toBe('clos');
  });
});

describe('voter', () => {
  it('avant la 80e : refusé', async () => {
    _matchs.m1 = match('LIVE', 60);
    await expect(voterJoueur('m1', 'u1', 10, apres(1))).rejects.toMatchObject({ statut: 409 });
  });

  it('le nom vient du fournisseur ; un vote par compte, modifiable ; pourcentages sur 100', async () => {
    _matchs.m1 = match('LIVE', 85);
    await voterJoueur('m1', 'u1', 10, apres(2));
    await voterJoueur('m1', 'u2', 10, apres(2));
    await voterJoueur('m1', 'u3', 20, apres(2));
    let r = await voterJoueur('m1', 'u3', '11', apres(2)); // change d'avis
    expect(_votes).toHaveLength(3);
    expect(r.total).toBe(3);
    expect(r.classement[0]).toMatchObject({ joueur_id: 10, nom: 'Nicolas Jackson', equipe: 'away', votes: 2, pourcentage: 67 });
    expect(r.classement[1]).toMatchObject({ joueur_id: 11, pourcentage: 33 });
    expect(r.mon_vote).toBe(11);
    r = (await resumeJoueurDuMatch('m1', null, apres(2)))!;
    expect(r.mon_vote).toBeNull();
  });

  it('un joueur qui n’a pas joué ce match : refusé', async () => {
    _matchs.m1 = match('FINISHED', 90);
    await expect(voterJoueur('m1', 'u1', 999, apres(3))).rejects.toMatchObject({ statut: 422 });
    await expect(voterJoueur('m1', 'u1', 'x', apres(3))).rejects.toMatchObject({ statut: 422 });
  });

  it('notes indisponibles : 503, rien d’enregistré', async () => {
    _matchs.m1 = match('FINISHED', 90);
    remplacerLecteurJoueurs(async () => null);
    await expect(voterJoueur('m1', 'u1', 10, apres(3))).rejects.toMatchObject({ statut: 503 });
    expect(_votes).toHaveLength(0);
  });

  it('clos le lendemain soir', async () => {
    _matchs.m1 = match('FINISHED', 90);
    await expect(voterJoueur('m1', 'u1', 10, apres(40))).rejects.toThrow(/clos/);
  });
});
