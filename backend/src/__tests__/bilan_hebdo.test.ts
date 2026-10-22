/**
 * Bilan de la semaine aux comptes gratuits (18 octobre 2026) : chaque lundi,
 * bonne ou mauvaise semaine, une seule fois, sans prix ni moyen de paiement.
 */
import { debutSemaine, envoyerBilanHebdo, texteBilan, TITRE_BILAN } from '../services/bilan_hebdo.service';

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

it('début de semaine : le lundi 00:00 UTC', () => {
  expect(debutSemaine(new Date(LUNDI + 15 * heure)).getTime()).toBe(LUNDI);
  expect(debutSemaine(new Date(LUNDI - heure)).getTime()).toBe(LUNDI - 7 * 24 * heure);   // dimanche soir
  expect(debutSemaine(new Date(LUNDI + 3 * 24 * heure)).getTime()).toBe(LUNDI);           // jeudi
});

describe('l\'envoi', () => {
  // Base simulée : les méthodes Prisma ne se typent pas comme de simples promesses.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  let segment: jest.Mock;
  let lectures: any[];
  const notifSvc = () => ({ sendToSegment: segment }) as any;

  beforeEach(() => {
    segment = jest.fn(async () => ({ sent: 42 }));
    lectures = [];
    jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue(null);
    jest.spyOn(prisma.pronostic, 'findMany').mockImplementation(async (args: any) => {
      lectures.push(args);
      return [
        { isPremium: false, result: 'WIN' }, { isPremium: false, result: 'LOSS' }, { isPremium: false, result: 'WIN' },
        { isPremium: true, result: 'LOSS' },
      ] as any;
    });
  });
  afterEach(() => jest.restoreAllMocks());

  it('lundi 10 h UTC : la semaine écoulée, aux comptes gratuits, vers l\'historique', async () => {
    const r = await envoyerBilanHebdo(new Date(LUNDI + 10 * heure + 5 * 60_000), notifSvc());
    expect(r).toEqual({ envoye: true, destinataires: 42 });
    expect(segment).toHaveBeenCalledWith('free', {
      title: TITRE_BILAN, titleEn: 'Weekly recap',
      body: 'Pronostics gratuits : 2 gagnés sur 3 · VIP : 0 gagné sur 1',
      bodyEn: 'Free predictions: 2 of 3 won · VIP: 0 of 1 won',
      deepLink: '/historique',
    });
    // Du lundi 12 (inclus) au lundi 19 (exclu), publiés, remboursés exclus.
    expect(lectures[0].where).toEqual({
      publicationRecordedAt: { not: null },
      result: { in: ['WIN', 'LOSS'] },
      match: { status: 'FINISHED', matchDate: { gte: new Date(LUNDI - 7 * 24 * heure), lt: new Date(LUNDI) } },
    });
  });

  it('hors créneau : ni avant 10 h, ni après 22 h, ni un autre jour', async () => {
    for (const t of [LUNDI + 9 * heure, LUNDI + 22 * heure, LUNDI + 24 * heure + 11 * heure, LUNDI - 13 * heure]) {
      expect((await envoyerBilanHebdo(new Date(t), notifSvc())).envoye).toBe(false);
    }
    expect(segment).not.toHaveBeenCalled();
  });

  it('déjà parti cette semaine (redémarrage du serveur) : pas une seconde fois', async () => {
    const temoin = jest.spyOn(prisma.notification, 'findFirst').mockResolvedValue({ id: 'n1' } as any);
    expect(await envoyerBilanHebdo(new Date(LUNDI + 14 * heure), notifSvc())).toEqual({ envoye: false, raison: 'déjà envoyé' });
    expect(temoin.mock.calls[0][0]).toMatchObject({ where: { type: 'promo', title: TITRE_BILAN, createdAt: { gte: new Date(LUNDI) } } });
    expect(segment).not.toHaveBeenCalled();
  });

  it('semaine sans pronostic réglé : rien', async () => {
    jest.spyOn(prisma.pronostic, 'findMany').mockResolvedValue([]);
    expect(await envoyerBilanHebdo(new Date(LUNDI + 11 * heure), notifSvc()))
      .toEqual({ envoye: false, raison: 'aucun pronostic réglé' });
    expect(segment).not.toHaveBeenCalled();
  });
});
