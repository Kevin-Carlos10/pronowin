/**
 * Bilan de la semaine aux comptes gratuits (18 octobre 2026) : chaque lundi,
 * bonne ou mauvaise semaine, une seule fois, sans prix ni moyen de paiement.
 * Personnel depuis le 27 octobre : votes et matchs suivis d'abord.
 */
import {
  bilansPersonnels, debutSemaine, envoyerBilanHebdo, texteBilan, textePerso, TITRE_BILAN,
} from '../services/bilan_hebdo.service';

// Lundi 19 octobre 2026.
const LUNDI = Date.UTC(2026, 9, 19);
const heure = 3600_000;

describe('le texte', () => {
  it('gratuits et VIP', () => {
    const b = { gratuits: { gagnes: 7, decisifs: 10 }, vip: { gagnes: 4, decisifs: 5 } };
    expect(texteBilan(b, 'fr')).toBe('Pronostics gratuits : 7 gagnés sur 10 · VIP : 4 gagnés sur 5');
    expect(texteBilan(b, 'en')).toBe('Free predictions: 7 of 10 won · VIP: 4 of 5 won');
  });

  it('une mauvaise semaine se dit aussi, au singulier si besoin', () => {
    const b = { gratuits: { gagnes: 1, decisifs: 6 }, vip: { gagnes: 0, decisifs: 3 } };
    expect(texteBilan(b, 'fr')).toBe('Pronostics gratuits : 1 gagné sur 6 · VIP : 0 gagné sur 3');
  });

  it('aucun VIP réglé : seulement les gratuits ; rien du tout : pas de bilan', () => {
    expect(texteBilan({ gratuits: { gagnes: 3, decisifs: 4 }, vip: { gagnes: 0, decisifs: 0 } }, 'fr'))
      .toBe('Pronostics gratuits : 3 gagnés sur 4');
    expect(texteBilan({ gratuits: { gagnes: 0, decisifs: 0 }, vip: { gagnes: 0, decisifs: 0 } }, 'fr')).toBeNull();
  });

  it('ni prix, ni moyen de paiement, ni lien vers le site', () => {
    const t = texteBilan({ gratuits: { gagnes: 7, decisifs: 10 }, vip: { gagnes: 4, decisifs: 5 } }, 'fr')!;
    expect(t).not.toMatch(/FCFA|€|\$|Mobile Money|site|pronowin\.space/i);
  });
});

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
  let lectures: any[];
  let lecturesVotes: any[];
  const notifSvc = () => ({
    destinatairesJoignables: async () => [{ id: 'u1' }, { id: 'u2' }, { id: 'u3' }],
    sendToUser: envoi,
  }) as any;

  beforeEach(() => {
    envoi = jest.fn(async (userId: string) => ({ success: userId !== 'u3' }));
    lectures = [];
    lecturesVotes = [];
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue(null);
    jest.spyOn(prisma.pronostic, 'findMany').mockImplementation(async (args: any) => {
      lectures.push(args);
      return [
        { isPremium: false, result: 'WIN' }, { isPremium: false, result: 'LOSS' }, { isPremium: false, result: 'WIN' },
        { isPremium: true, result: 'LOSS' },
      ] as any;
    });
    // u1 a voté deux fois (une juste) et suivi un match au pronostic gagné.
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

  it('lundi 10 h UTC : la semaine écoulée, à chaque compte gratuit, vers l\'historique', async () => {
    const r = await envoyerBilanHebdo(new Date(LUNDI + 10 * heure + 5 * 60_000), notifSvc());
    expect(r).toEqual({ envoye: true, destinataires: 2, personnels: 1 });
    expect(envoi).toHaveBeenCalledTimes(3);
    // Le bilan général seul pour qui n'a rien fait.
    expect(envoi).toHaveBeenCalledWith('u2', {
      title: TITRE_BILAN, titleEn: 'Weekly recap',
      body: 'Pronostics gratuits : 2 gagnés sur 3 · VIP : 0 gagné sur 1',
      bodyEn: 'Free predictions: 2 of 3 won · VIP: 0 of 1 won',
      data: { type: 'promo', deep_link: '/historique' },
    }, 'promo');
    // Sa propre semaine d'abord.
    expect(envoi).toHaveBeenCalledWith('u1', expect.objectContaining({
      body: 'Vos votes : 1 bien vu sur 2 · Votre match suivi : 1 pronostic gagné sur 1\n'
        + 'Pronostics gratuits : 2 gagnés sur 3 · VIP : 0 gagné sur 1',
    }), 'promo');
    // Du lundi 12 (inclus) au lundi 19 (exclu), publiés, remboursés exclus.
    const semaine = { status: 'FINISHED', matchDate: { gte: new Date(LUNDI - 7 * 24 * heure), lt: new Date(LUNDI) } };
    expect(lectures[0].where).toEqual({
      publicationRecordedAt: { not: null },
      result: { in: ['WIN', 'LOSS'] },
      match: semaine,
    });
    expect(lecturesVotes[0].where).toEqual({ userId: { in: ['u1', 'u2', 'u3'] }, match: semaine });
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

  it('semaine sans pronostic réglé : rien', async () => {
    jest.spyOn(prisma.pronostic, 'findMany').mockResolvedValue([]);
    expect(await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc()))
      .toEqual({ envoye: false, raison: 'aucun pronostic réglé' });
    expect(envoi).not.toHaveBeenCalled();
  });

  it('un envoi qui échoue n\'arrête pas les autres', async () => {
    envoi.mockImplementation(async (userId: string) => {
      if (userId === 'u1') throw new Error('réseau');
      return { success: true };
    });
    expect(await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc()))
      .toEqual({ envoye: true, destinataires: 2, personnels: 1 });
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
