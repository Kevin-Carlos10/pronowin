/**
 * Bilan de la semaine aux comptes gratuits (18 octobre 2026) : chaque lundi,
 * bonne ou mauvaise semaine, une seule fois, sans prix ni moyen de paiement.
 * Personnel depuis le 27 octobre : votes et matchs suivis d'abord.
 * Depuis le 23 novembre, plus de bilan général : le taux de réussite est
 * réservé aux abonnés Premium.
 */
import {
  bilansPersonnels, debutSemaine, envoyerBilanHebdo, textePerso, TITRE_BILAN,
} from '../services/bilan_hebdo.service';

// Lundi 19 octobre 2026.
const LUNDI = Date.UTC(2026, 9, 19);
const heure = 3600_000;

describe('la partie personnelle', () => {
  const vide = { votes: 0, votesJustes: 0, suivis: 0, suivisGagnes: 0, suivisDecisifs: 0 };

  it('votes et matchs suivis', () => {
    const b = { votes: 5, votesJustes: 3, suivis: 4, suivisGagnes: 2, suivisDecisifs: 3 };
    expect(textePerso(b, 'fr')).toBe('Vos votes : 3 bien vus sur 5 · Vos 4 matchs suivis : 2 pronostics gagnés sur 3');
    expect(textePerso(b, 'en')).toBe('Your votes: 3 of 5 spot on · Your 4 followed matches: 2 of 3 predictions won');
  });

  it('au singulier ; un match suivi sans pronostic réglé se nomme seul', () => {
    expect(textePerso({ ...vide, votes: 1, votesJustes: 1 }, 'fr')).toBe('Vos votes : 1 bien vu sur 1');
    expect(textePerso({ ...vide, suivis: 1 }, 'fr')).toBe('Votre match suivi');
    expect(textePerso({ ...vide, suivis: 1, suivisGagnes: 0, suivisDecisifs: 1 }, 'fr'))
      .toBe('Votre match suivi : 0 pronostic gagné sur 1');
  });

  it('sans activité : rien', () => {
    expect(textePerso(undefined, 'fr')).toBeNull();
    expect(textePerso(vide, 'fr')).toBeNull();
  });

  it('ni prix, ni moyen de paiement, ni lien vers le site', () => {
    const t = textePerso({ votes: 5, votesJustes: 3, suivis: 4, suivisGagnes: 2, suivisDecisifs: 3 }, 'fr')!;
    expect(t).not.toMatch(/FCFA|€|\$|Mobile Money|site|pronowin\.space/i);
  });
});

it('début de semaine : le lundi 00:00 UTC', () => {
  expect(debutSemaine(new Date(LUNDI + 15 * heure)).getTime()).toBe(LUNDI);
  expect(debutSemaine(new Date(LUNDI - heure)).getTime()).toBe(LUNDI - 7 * 24 * heure);   // dimanche soir
  expect(debutSemaine(new Date(LUNDI + 3 * 24 * heure)).getTime()).toBe(LUNDI);           // jeudi
});

describe('l\'envoi', () => {
  // Base simulée : les méthodes Prisma ne se typent pas comme de simples promesses.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  let envoi: jest.Mock;
  let lecturesVotes: any[];
  const notifSvc = () => ({
    destinatairesJoignables: async () => [{ id: 'u1' }, { id: 'u2' }, { id: 'u3' }],
    sendToUser: envoi,
  }) as any;

  beforeEach(() => {
    envoi = jest.fn(async (userId: string) => ({ success: userId !== 'u3' }));
    lecturesVotes = [];
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue(null);
    // u1 a voté deux fois (une juste) et suivi un match au pronostic gagné.
    // u2 et u3 n'ont rien fait.
    jest.spyOn(prisma.voteMatch, 'findMany').mockImplementation(async (args: any) => {
      lecturesVotes.push(args);
      return [
        { userId: 'u1', choix: '1', match: { homeScore: 2, awayScore: 0 } },
        { userId: 'u1', choix: 'N', match: { homeScore: 1, awayScore: 3 } },
      ] as any;
    });
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([
      { userId: 'u1', match: { pronostic: { result: 'WIN', publicationRecordedAt: new Date() } } },
    ] as any);
  });
  afterEach(() => jest.restoreAllMocks());

  it('lundi 10 h UTC : sa propre semaine, à chaque compte gratuit qui en a une, vers l\'historique', async () => {
    const r = await envoyerBilanHebdo(new Date(LUNDI + 10 * heure + 5 * 60_000), notifSvc());
    expect(r).toEqual({ envoye: true, destinataires: 1, personnels: 1 });
    // Sa semaine seule : plus de bilan général (taux réservé aux abonnés
    // Premium, 23 novembre 2026).
    expect(envoi).toHaveBeenCalledTimes(1);
    expect(envoi).toHaveBeenCalledWith('u1', {
      title: TITRE_BILAN, titleEn: 'Weekly recap',
      body: 'Vos votes : 1 bien vu sur 2 · Votre match suivi : 1 pronostic gagné sur 1',
      bodyEn: 'Your votes: 1 of 2 spot on · Your followed match: 1 of 1 predictions won',
      data: { type: 'promo', deep_link: '/historique' },
    }, 'promo');
    // Du lundi 12 (inclus) au lundi 19 (exclu).
    const semaine = { status: 'FINISHED', matchDate: { gte: new Date(LUNDI - 7 * 24 * heure), lt: new Date(LUNDI) } };
    expect(lecturesVotes[0].where).toEqual({ userId: { in: ['u1', 'u2', 'u3'] }, match: semaine });
  });

  it('aucun message ne porte le bilan général des pronostics', async () => {
    await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc());
    for (const [, m] of envoi.mock.calls) {
      expect(`${m.body} ${m.bodyEn}`).not.toMatch(/Pronostics gratuits|VIP|Free predictions|%/);
    }
  });

  it('hors créneau : ni avant 10 h, ni après 22 h, ni un autre jour', async () => {
    for (const t of [LUNDI + 9 * heure, LUNDI + 22 * heure, LUNDI + 24 * heure + 11 * heure, LUNDI - 13 * heure]) {
      expect((await envoyerBilanHebdo(new Date(t), notifSvc())).envoye).toBe(false);
    }
    expect(envoi).not.toHaveBeenCalled();
  });

  it('déjà parti cette semaine (redémarrage du serveur) : pas une seconde fois', async () => {
    const temoin = jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue({ id: 'n1' } as any);
    expect(await envoyerBilanHebdo(new Date(LUNDI + 14 * heure), notifSvc())).toEqual({ envoye: false, raison: 'déjà envoyé' });
    expect(temoin.mock.calls[0][0]).toMatchObject({ where: { type: 'promo', title: TITRE_BILAN, createdAt: { gte: new Date(LUNDI) } } });
    expect(envoi).not.toHaveBeenCalled();
  });

  it('personne n\'a rien fait de la semaine : rien', async () => {
    jest.spyOn(prisma.voteMatch, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([]);
    expect(await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc()))
      .toEqual({ envoye: false, raison: 'aucune activité personnelle' });
    expect(envoi).not.toHaveBeenCalled();
  });

  it('un envoi qui échoue n\'arrête pas les autres', async () => {
    // u2 a suivi un match, lui aussi.
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([
      { userId: 'u1', match: { pronostic: { result: 'WIN', publicationRecordedAt: new Date() } } },
      { userId: 'u2', match: { pronostic: null } },
    ] as any);
    envoi.mockImplementation(async (userId: string) => {
      if (userId === 'u1') throw new Error('réseau');
      return { success: true };
    });
    expect(await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc()))
      .toEqual({ envoye: true, destinataires: 1, personnels: 2 });
  });
});

describe('les bilans personnels', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  afterEach(() => jest.restoreAllMocks());

  it('un vote sans score final ne compte pas juste ; un remboursé ou non publié ne compte pas réglé', async () => {
    jest.spyOn(prisma.voteMatch, 'findMany').mockResolvedValue([
      { userId: 'u1', choix: '2', match: { homeScore: 0, awayScore: 1 } },
      { userId: 'u1', choix: 'N', match: { homeScore: null, awayScore: null } },
    ] as any);
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([
      { userId: 'u1', match: { pronostic: { result: 'VOID', publicationRecordedAt: new Date() } } },
      { userId: 'u1', match: { pronostic: { result: 'WIN', publicationRecordedAt: null } } },
      { userId: 'u1', match: { pronostic: null } },
      { userId: 'u2', match: { pronostic: { result: 'LOSS', publicationRecordedAt: new Date() } } },
    ] as any);
    const b = await bilansPersonnels(['u1', 'u2'], new Date(LUNDI - 7 * 24 * heure), new Date(LUNDI));
    expect(b.get('u1')).toEqual({ votes: 2, votesJustes: 1, suivis: 3, suivisGagnes: 0, suivisDecisifs: 0 });
    expect(b.get('u2')).toEqual({ votes: 0, votesJustes: 0, suivis: 1, suivisGagnes: 0, suivisDecisifs: 1 });
  });
});
