/**
 * Paiements Mobile Money (GeniusPay) dans le panneau (18 octobre 2026) : deux
 * paiements restaient « en cours » depuis le 13 octobre sans qu'aucun écran
 * le montre, et le rapprochement automatique ne les relisait plus (26 h).
 */
import { etatPaiementMM, estBloque } from '../services/paiements_mobile_money_admin.service';

const MAINTENANT = new Date(Date.UTC(2026, 9, 18, 18, 0, 0));
const ilYa = (heures: number) => new Date(MAINTENANT.getTime() - heures * 3_600_000);

describe('l\'état d\'un paiement', () => {
  const etat = (statut: string, heures: number, accorde = false) =>
    etatPaiementMM({ statut, creeLe: ilYa(heures), premiumAccordeLe: accorde ? ilYa(heures - 0.1) : null }, MAINTENANT);

  it('payé et Premium accordé', () => expect(etat('completed', 5, true)).toBe('accorde'));
  it('payé sans Premium, ou non conforme : anomalie', () => {
    expect(etat('completed', 5)).toBe('anomalie');
    expect(etat('anomalie', 5)).toBe('anomalie');
  });
  it('validé chez l\'opérateur, pas conclu : en cours', () => expect(etat('processing', 120)).toBe('en_cours'));
  it('page ouverte, rien de validé : en attente, puis abandonné après 26 h', () => {
    expect(etat('pending', 2)).toBe('en_attente');
    expect(etat('pending', 27)).toBe('abandonne');
  });
  it('refusé, annulé, expiré, remboursé : échoué', () => {
    for (const s of ['failed', 'cancelled', 'expired', 'refunded']) expect(etat(s, 3)).toBe('echoue');
  });
});

it('bloqué : en cours depuis plus d\'une heure, ou en anomalie', () => {
  expect(estBloque('en_cours', ilYa(0.5), MAINTENANT)).toBe(false);
  expect(estBloque('en_cours', ilYa(2), MAINTENANT)).toBe(true);
  expect(estBloque('anomalie', ilYa(0.1), MAINTENANT)).toBe(true);
  expect(estBloque('en_attente', ilYa(20), MAINTENANT)).toBe(false);
});

describe('le résumé', () => {
  // Base simulée : les méthodes Prisma ne se typent pas comme de simples promesses.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { resumePaiementsMobileMoney } = require('../services/paiements_mobile_money_admin.service');

  const compte = (pseudo: string) => ({
    id: 'u-' + pseudo, pseudo, email: pseudo + '@example.com',
    subscriptionPlan: 'free', subscriptionExpiresAt: null, deletedAt: null,
  });
  const ligne = (id: string, o: any) => ({
    id, plan: 'monthly', montant: 6000, frais: null, montantNet: null, moyen: null,
    reference: 'REF-' + id, environnement: 'live', premiumAccordeLe: null, majLe: ilYa(1),
    user: compte('awa'), ...o,
  });

  beforeEach(() => {
    jest.useFakeTimers(); jest.setSystemTime(MAINTENANT);
    jest.spyOn(prisma.paiementGeniusPay, 'findMany').mockResolvedValue([
      ligne('a', { statut: 'completed', creeLe: ilYa(3), premiumAccordeLe: ilYa(2.9), frais: 160, montantNet: 5840, moyen: 'orange_money' }),
      ligne('b', { statut: 'processing', creeLe: ilYa(125), frais: 760, user: compte('issa') }),
      ligne('c', { statut: 'processing', creeLe: ilYa(124), frais: 370 }),
      ligne('d', { statut: 'pending', creeLe: ilYa(2) }),
      ligne('e', { statut: 'pending', creeLe: ilYa(40) }),
      ligne('f', { statut: 'failed', creeLe: ilYa(10) }),
      ligne('g', { statut: 'completed', creeLe: ilYa(30), premiumAccordeLe: ilYa(29), environnement: 'sandbox' }),
    ]);
  });
  afterEach(() => { jest.restoreAllMocks(); jest.useRealTimers(); });

  it('chiffres sur les paiements réels ; le bac à sable compté à part', async () => {
    const r = await resumePaiementsMobileMoney();
    expect(r.stats).toEqual({
      jours: 30, encaisses: 1, brut: 6000, frais: 160, net: 5840,
      bloques: 2, montantBloque: 12000, enAttente: 1, abandonnes: 1, echoues: 1,
      tauxReussite: 33, sandbox: 1,
    });
  });

  it('les bloqués en tête, puis du plus récent au plus ancien ; bac à sable masqué', async () => {
    const r = await resumePaiementsMobileMoney();
    expect(r.paiements.map((p: any) => p.id)).toEqual(['c', 'b', 'd', 'a', 'f', 'e']);
    expect(r.paiements[0]).toMatchObject({ etat: 'en_cours', bloque: true, ageHeures: 124, formule: expect.any(String) });
  });

  it('filtres : bloqués, état, recherche, bac à sable', async () => {
    expect((await resumePaiementsMobileMoney({ etat: 'bloque' })).paiements.map((p: any) => p.id)).toEqual(['c', 'b']);
    expect((await resumePaiementsMobileMoney({ etat: 'abandonne' })).paiements.map((p: any) => p.id)).toEqual(['e']);
    expect((await resumePaiementsMobileMoney({ recherche: 'issa' })).paiements.map((p: any) => p.id)).toEqual(['b']);
    expect((await resumePaiementsMobileMoney({ recherche: 'ref-f' })).paiements.map((p: any) => p.id)).toEqual(['f']);
    expect((await resumePaiementsMobileMoney({ sandbox: true })).total).toBe(7);
  });
});

describe('la revérification', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const geniuspay = require('../services/geniuspay.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { reverifierPaiementMobileMoney } = require('../services/paiements_mobile_money_admin.service');
  afterEach(() => jest.restoreAllMocks());

  it('un paiement « en cours » de 5 jours est relu, et le Premium accordé s\'il est payé', async () => {
    const avant = { id: 'b', statut: 'processing', premiumAccordeLe: null, creeLe: ilYa(125) };
    jest.spyOn(prisma.paiementGeniusPay, 'findUnique').mockResolvedValue(avant);
    const relu = jest.spyOn(geniuspay, 'rapprocherPaiement').mockResolvedValue({ ...avant, statut: 'completed', premiumAccordeLe: new Date() });
    expect(await reverifierPaiementMobileMoney('b')).toEqual({
      etat: 'accorde', statut: 'completed', change: true, premiumAccorde: true, relu: true,
    });
    expect(relu).toHaveBeenCalledWith('b');
  });

  it('inconnu : null', async () => {
    jest.spyOn(prisma.paiementGeniusPay, 'findUnique').mockResolvedValue(null);
    expect(await reverifierPaiementMobileMoney('x')).toBeNull();
  });
});
