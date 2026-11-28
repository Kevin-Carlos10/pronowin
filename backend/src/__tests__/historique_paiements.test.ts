/**
 * L'historique des paiements d'un compte (23 novembre 2026) : ce qui a été
 * payé, ce qui est en cours, ce qui a été refusé — sans doublon.
 */
import { prisma } from '../lib/prisma';
import { historiquePaiements } from '../services/historique_paiements.service';

const maintenant = new Date('2026-11-23T12:00:00Z');
const ilYa = (jours: number, minutes = 0) => new Date(maintenant.getTime() - jours * 86_400_000 - minutes * 60_000);

afterEach(() => jest.restoreAllMocks());

function base({ abonnements = [] as any[], paiements = [] as any[], preuves = [] as any[] }) {
  jest.spyOn(prisma.subscription, 'findMany').mockResolvedValue(abonnements);
  jest.spyOn(prisma.paiementGeniusPay, 'findMany').mockResolvedValue(paiements);
  jest.spyOn(prisma.subscriptionProof, 'findMany').mockResolvedValue(preuves);
}

describe('l\'historique des paiements', () => {
  it('un paiement GeniusPay réussi est son abonnement : une ligne, avec référence et opérateur', async () => {
    base({
      abonnements: [{ id: 's1', createdAt: ilYa(10), startDate: ilYa(10), endDate: ilYa(-355),
        amountPaid: 54000, paymentMethod: 'geniuspay' }],
      paiements: [{ id: 'g1', plan: 'premium_annual', montant: 54000, reference: 'GP-123', statut: 'completed',
        moyen: 'orange_money', creeLe: ilYa(10, 3), premiumAccordeLe: ilYa(10, 1), environnement: 'live' }],
    });
    const h = await historiquePaiements('u', maintenant);
    expect(h).toEqual([expect.objectContaining({
      id: 's1', statut: 'paye', formule: 'premium_annual', montant: 54000,
      moyen: 'geniuspay', operateur: 'orange_money', reference: 'GP-123',
    })]);
  });

  it('en cours, échoué (un mois au plus), en vérification, refusé avec son motif ; le test ne compte pas', async () => {
    base({
      paiements: [
        { id: 'g2', plan: 'premium_monthly', montant: 6000, reference: 'GP-2', statut: 'processing',
          moyen: null, creeLe: ilYa(0, 5), premiumAccordeLe: null, environnement: 'live' },
        { id: 'g3', plan: 'premium_monthly', montant: 6000, reference: 'GP-3', statut: 'failed',
          moyen: 'moov_money', creeLe: ilYa(2), premiumAccordeLe: null, environnement: 'live' },
        { id: 'g4', plan: 'premium_monthly', montant: 6000, reference: 'GP-4', statut: 'expired',
          moyen: null, creeLe: ilYa(40), premiumAccordeLe: null, environnement: 'live' },
        { id: 'g5', plan: 'premium_monthly', montant: 6000, reference: 'GP-5', statut: 'completed',
          moyen: null, creeLe: ilYa(1), premiumAccordeLe: null, environnement: 'sandbox' },
      ],
      preuves: [
        { id: 'p1', createdAt: ilYa(1), planId: 'premium_monthly', amount: 6000, status: 'pending', adminNote: null },
        { id: 'p2', createdAt: ilYa(3), planId: 'premium_monthly', amount: 5000, status: 'rejected',
          adminNote: 'Montant incomplet' },
      ],
    });
    const h = await historiquePaiements('u', maintenant);
    expect(h.map(l => [l.id, l.statut])).toEqual([
      ['g2', 'en_cours'], ['p1', 'en_verification'], ['g3', 'echoue'], ['p2', 'refuse']]);
    expect(h.find(l => l.id === 'p2')!.motif).toBe('Montant incomplet');
  });

  it('offert par l\'équipe ou par code partenaire ; un achat de boutique sans montant connu', async () => {
    base({ abonnements: [
      { id: 's2', createdAt: ilYa(5), startDate: ilYa(5), endDate: ilYa(-25), amountPaid: 0, paymentMethod: 'manual_admin' },
      { id: 's3', createdAt: ilYa(50), startDate: ilYa(50), endDate: ilYa(20), amountPaid: 0, paymentMethod: 'promo_1xbet' },
      { id: 's4', createdAt: ilYa(90), startDate: ilYa(90), endDate: ilYa(60), amountPaid: null, paymentMethod: 'iap_apple' },
      { id: 's5', createdAt: ilYa(120), startDate: ilYa(120), endDate: ilYa(90), amountPaid: 6000, paymentMethod: 'manual_mobcash' },
    ] });
    const h = await historiquePaiements('u', maintenant);
    expect(h.map(l => [l.id, l.statut, l.moyen, l.montant])).toEqual([
      ['s2', 'offert', 'manual_admin', 0], ['s3', 'offert', 'promo', 0],
      ['s4', 'paye', 'iap_apple', null], ['s5', 'paye', 'manual_mobcash', 6000]]);
    // Ce compte seulement.
    expect((prisma.subscription.findMany as jest.Mock).mock.calls[0][0].where).toEqual({ userId: 'u', plan: 'premium' });
    expect((prisma.paiementGeniusPay.findMany as jest.Mock).mock.calls[0][0].where).toEqual({ userId: 'u' });
  });
});
