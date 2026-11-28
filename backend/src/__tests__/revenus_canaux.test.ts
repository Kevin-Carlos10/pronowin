/**
 * Ventes par canal, fidélité des abonnés, export comptable.
 *
 * Les écrans de revenus ne lisaient que la somme des abonnements : rien ne
 * disait ce que rapporte chaque canal, qui renouvelle, qui part.
 */
import {
  canalDe, estRenouvele, analyserFidelite, agregerVentes, rapprocheur, prixStore,
  DELAI_RENOUVELLEMENT_JOURS, type LigneAbonnement, type AchatStore,
} from '../services/revenus_canaux.service';

const JOUR = 86_400_000;
const MAINTENANT = new Date('2026-10-05T12:00:00Z');
const j = (n: number) => new Date(MAINTENANT.getTime() + n * JOUR);

let n = 0;
const abo = (userId: string, moyen: string, debut: number, fin: number, p: Partial<LigneAbonnement> = {}): LigneAbonnement => ({
  id: `s${++n}`, userId, paymentMethod: moyen, amountPaid: moyen === 'manual_mobcash' ? 2000 : null,
  startDate: j(debut), endDate: j(fin), createdAt: j(debut), ...p,
});

describe('canal d\'un moyen de paiement', () => {
  it('chaque valeur écrite par le serveur, ancienne comprise', () => {
    expect(canalDe('manual_mobcash')).toBe('mobile_money');
    expect(canalDe('iap_apple')).toBe('apple');
    expect(canalDe('iap_google')).toBe('google');
    expect(canalDe('promo_1xbet')).toBe('partenaire');
    expect(canalDe('xbet_promo')).toBe('partenaire');   // nom d'avant la généralisation
    expect(canalDe('manual_admin')).toBe('offert');
    expect(canalDe('orange_money')).toBe('mobile_money');
    expect(canalDe('bitcoin')).toBe('autre');
  });
});

describe('renouvellement', () => {
  it('réabonnement anticipé, en retard de quelques jours, ou couverture plus longue', () => {
    const fin = abo('a', 'manual_mobcash', -40, -10);
    expect(estRenouvele(fin, [fin, abo('a', 'manual_mobcash', -12, 20)])).toBe(true);   // avant la fin
    expect(estRenouvele(fin, [fin, abo('a', 'manual_mobcash', -5, 25)])).toBe(true);    // 5 jours après
    expect(estRenouvele(fin, [fin, abo('a', 'manual_mobcash', -100, 300)])).toBe(true); // annuel en cours
  });

  it('un retour au-delà du délai n\'est pas un renouvellement', () => {
    const fin = abo('a', 'manual_mobcash', -60, -40);
    const retour = abo('a', 'manual_mobcash', -40 + DELAI_RENOUVELLEMENT_JOURS + 1, 10);
    expect(estRenouvele(fin, [fin, retour])).toBe(false);
    expect(estRenouvele(fin, [fin])).toBe(false);
  });
});

describe('fidélité', () => {
  const abonnements = [
    // Mobile Money : un renouvelle, un part.
    abo('fidele', 'manual_mobcash', -70, -40), abo('fidele', 'manual_mobcash', -41, -10), abo('fidele', 'manual_mobcash', -11, 3),
    abo('parti', 'manual_mobcash', -50, -20),
    // Apple : renouvelle tout seul.
    abo('pomme', 'iap_apple', -45, -15), abo('pomme', 'iap_apple', -15, 15),
    // Mois offert par un partenaire, sans suite : pas un abonné payant.
    abo('essai', 'promo_1xbet', -40, -12),
    // Fin trop récente : l'issue n'est pas encore connue.
    abo('recent', 'manual_mobcash', -32, -2),
  ];
  const r = analyserFidelite(abonnements, MAINTENANT, 90);

  it('taux par canal, et global sur les seuls canaux payants', () => {
    const mm = r.parCanal.find((c) => c.canal === 'mobile_money')!;
    // fidèle −40 (renouvelé), fidèle −10 (renouvelé), parti −20 (non) ; récent : en attente.
    expect(mm).toMatchObject({ fins: 3, renouvelees: 2, taux: 67 });
    expect(r.parCanal.find((c) => c.canal === 'apple')).toMatchObject({ fins: 1, renouvelees: 1 });
    expect(r.parCanal.find((c) => c.canal === 'partenaire')).toMatchObject({ fins: 1, renouvelees: 0, taux: 0 });
    expect(r.global).toMatchObject({ fins: 4, renouvelees: 3, taux: 75 });
  });

  it('les comptes à relancer : bientôt expirés, récemment partis', () => {
    expect(r.bientot.map((c) => c.userId)).toEqual(['fidele']);
    expect(r.partis.map((c) => [c.userId, c.canal])).toEqual([
      ['recent', 'mobile_money'], ['essai', 'partenaire'], ['parti', 'mobile_money'],
    ]);
    const fidele = r.bientot[0];
    expect(fidele).toMatchObject({ paiements: 3, totalFcfa: 6000 });
  });

  it('six mois, le dernier signalé comme provisoire', () => {
    expect(r.mensuel).toHaveLength(6);
    expect(r.mensuel[5]).toMatchObject({ mois: '2026-10', enCours: true });
    expect(r.mensuel[0]).toMatchObject({ mois: '2026-05', enCours: false });
  });
});

describe('ventes par canal', () => {
  const achats: AchatStore[] = [
    { userId: 'pomme', store: 'apple', expiresAt: j(15), environment: 'Production',
      payload: { transaction: { price: 4990, currency: 'USD' } } },
    { userId: 'testeur', store: 'apple', expiresAt: j(20), environment: 'Sandbox', payload: {} },
  ];
  const ventes = [
    abo('nouveau', 'manual_mobcash', -3, 27),
    abo('ancien', 'manual_mobcash', -2, 28),
    abo('pomme', 'iap_apple', -1, 15),
    abo('testeur', 'iap_apple', -1, 20),
    abo('mystere', 'iap_google', -1, 29),
  ];
  const premier = new Map<string, Date>([
    ['nouveau', j(-3)], ['ancien', j(-200)], ['pomme', j(-1)], ['testeur', j(-1)], ['mystere', j(-90)],
  ]);
  const r = agregerVentes(ventes, premier, rapprocheur(achats));

  it('un achat de test n\'est pas une vente', () => {
    expect(r.tests).toBe(1);
    expect(r.total.ventes).toBe(4);
  });

  it('montant FCFA, prix store par devise, montant inconnu', () => {
    const mm = r.canaux.find((c) => c.canal === 'mobile_money')!;
    expect(mm).toMatchObject({ ventes: 2, nouveaux: 1, reabonnements: 1, fcfa: 4000 });
    expect(r.canaux.find((c) => c.canal === 'apple')).toMatchObject({
      ventes: 1, nouveaux: 1, store: [{ devise: 'USD', montant: 4.99 }], montantsInconnus: 0 });
    expect(r.canaux.find((c) => c.canal === 'google')).toMatchObject({ ventes: 1, reabonnements: 1, montantsInconnus: 1 });
    expect(r.total.fcfa).toBe(4000);
  });

  it('le rapprochement retrouve un abonnement passé à un autre compte', () => {
    const achatDe = rapprocheur([{ userId: 'nouveau-proprio', store: 'apple', expiresAt: j(15),
      environment: 'Production', payload: { transaction: { price: 14990, currency: 'EUR' } } }]);
    expect(prixStore(achatDe(abo('ancien-proprio', 'iap_apple', -1, 15)))).toEqual({ montant: 14.99, devise: 'EUR' });
    expect(achatDe(abo('x', 'manual_mobcash', -1, 15))).toBeUndefined();
  });
});
