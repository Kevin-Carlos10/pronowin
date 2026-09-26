/**
 * L'argent des parrains : ce qui est retiré doit revenir, ce qui est versé
 * ne doit l'être qu'une fois.
 *
 * Deux défauts distincts, tous deux sur de l'argent réel.
 *
 * ── Le retrait refusé ──────────────────────────────────────────────────────
 *
 * `requestWithdrawal` déduit les gains **au moment de la demande** — c'est
 * volontaire, ça empêche de demander deux fois la même somme pendant que
 * l'administrateur regarde. La contrepartie obligatoire est qu'un refus rende
 * l'argent. `processRequest` ne le faisait pas : il passait la transaction à
 * `rejected`, envoyait une notification « Versement refusé », et les gains
 * restaient déduits. Le parrain perdait la somme sans jamais la recevoir, et
 * rien dans l'application ne le lui signalait — son solde avait simplement
 * baissé.
 *
 * ── La commission versée deux fois ─────────────────────────────────────────
 *
 * `triggerCommissions` lisait les parrainages non payés, puis les marquait
 * payés. Entre la lecture et l'écriture, un second appel lisait les mêmes
 * lignes, encore non payées. Les deux créditaient.
 *
 * Ce n'est pas théorique : `grantPremium` est appelé par la validation d'achat
 * intégré, que le client peut relancer, et par la revue de preuve côté
 * administrateur. Deux validations du même reçu qui se croisent versaient deux
 * fois la commission.
 *
 * ── Ce que ce banc mesure, et ce qu'il ne mesure pas ───────────────────────
 *
 * La base est simulée en mémoire. Ce banc n'établit donc **pas** l'isolation
 * transactionnelle de Postgres — aucun test unitaire ne le peut. Ce qu'il
 * établit est ce dont dépend cette isolation : que le code crédite seulement
 * si une écriture **conditionnelle** a effectivement changé une ligne. Un
 * `update` inconditionnel précédé d'une lecture, lui, échoue ici comme il
 * échouerait en production.
 */

// ── Une base en mémoire, avant tout import de service ──────────────────────
//
// Le `require` est à l'intérieur de la fabrique : jest.mock est hissé au-dessus
// des imports, et ne peut donc pas fermer sur une variable du module.
jest.mock('../lib/prisma', () => require('./aides/base_memoire').creerBase());

jest.mock('../services/notification.service', () => ({
  NotificationService: class {
    async sendToUser() { /* rien : les notifications ne sont pas le sujet */ }
  },
}));

import { PaymentService } from '../services/payment.service';
import { ReferralService, COMMISSION_L1 } from '../services/referral.service';

const { _base } = require('../lib/prisma');

const referral = new ReferralService();
const paiement = new PaymentService();

/** Remet la base à un état connu. */
function poser(gains: number) {
  _base.users.clear();
  _base.referrals.clear();
  _base.transactions.clear();
  _base.users.set('parrain', {
    id: 'parrain', pseudo: 'Parrain', referralEarnings: gains,
    referredBy: null, referralCode: 'CODE1', xbetId: null,
    subscriptionPlan: 'free', subscriptionExpiresAt: null, fcmToken: 'jeton-push',
  });
  _base.users.set('filleul', {
    id: 'filleul', pseudo: 'Filleul', referralEarnings: 0,
    referredBy: 'parrain', referralCode: 'CODE2', xbetId: null,
    subscriptionPlan: 'free', subscriptionExpiresAt: null, fcmToken: null,
  });
}

const gainsDuParrain = () => _base.users.get('parrain').referralEarnings;

describe('un retrait refusé rend l\'argent', () => {
  beforeEach(() => poser(3000));

  /** Demande un virement de [montant], et rend l'identifiant de transaction. */
  async function demander(montant: number) {
    const r: any = await referral.requestWithdrawal({
      userId: 'parrain', amount: montant, method: 'orange_money',
      phone: '+22670000000', useAsCredit: false,
    });
    return r.transaction_id;
  }

  it('la demande déduit les gains tout de suite', async () => {
    await demander(2000);
    expect(gainsDuParrain()).toBe(1000);
  });

  it('le refus recrédite la somme', async () => {
    const id = await demander(2000);
    await paiement.processRequest({
      transactionId: id, adminId: 'admin-1', status: 'rejected',
      adminNote: 'Numéro incorrect.',
    });

    expect(gainsDuParrain()).toBe(3000);
  });

  it('l\'approbation ne recrédite rien', async () => {
    // Contrepartie : un correctif qui recréditerait dans les deux cas rendrait
    // l'argent **et** l'enverrait. Le parrain serait payé deux fois.
    const id = await demander(2000);
    await paiement.processRequest({
      transactionId: id, adminId: 'admin-1', status: 'completed',
    });

    expect(gainsDuParrain()).toBe(1000);
  });

  it('deux refus du même versement ne recréditent qu\'une fois', async () => {
    const id = await demander(2000);
    await paiement.processRequest({
      transactionId: id, adminId: 'admin-1', status: 'rejected',
    });
    await paiement.processRequest({
      transactionId: id, adminId: 'admin-1', status: 'rejected',
    }).catch(() => { /* déjà traité : le refus est attendu */ });

    expect(gainsDuParrain()).toBe(3000);
  });

  it('un versement d\'une autre provenance n\'est pas recrédité', async () => {
    // Contrepartie : ne recréditer que ce qui a été débité. Une somme qui n'est
    // pas venue des gains de parrainage n'a jamais fait baisser
    // `referralEarnings` ; la rembourser là créerait de l'argent.
    _base.transactions.set('tx-ailleurs', {
      id: 'tx-ailleurs', userId: 'parrain', type: 'withdrawal',
      amount: 5000, currency: 'XOF', status: 'pending',
      paymentMethod: 'orange_money', metadata: { source: 'autre_chose' },
    });

    await paiement.processRequest({
      transactionId: 'tx-ailleurs', adminId: 'admin-1', status: 'rejected',
    });

    expect(gainsDuParrain()).toBe(3000);
  });

  it('deux refus simultanés ne recréditent qu\'une fois', async () => {
    // Le contrôle « déjà traité » lisait puis écrivait. Deux administrateurs
    // qui cliquent en même temps passaient tous les deux la lecture.
    const id = await demander(2000);
    await Promise.all([
      paiement.processRequest({ transactionId: id, adminId: 'a', status: 'rejected' })
        .catch(() => {}),
      paiement.processRequest({ transactionId: id, adminId: 'b', status: 'rejected' })
        .catch(() => {}),
    ]);

    expect(gainsDuParrain()).toBe(3000);
  });
});

describe('une commission ne se verse qu\'une fois', () => {
  beforeEach(() => {
    poser(0);
    _base.referrals.set('r1', {
      id: 'r1', referrerId: 'parrain', referredId: 'filleul',
      level: 1, commissionAmount: 0, isPaid: false,
    });
  });

  it('un passage Premium crédite la commission', async () => {
    await referral.triggerCommissions('filleul');
    expect(gainsDuParrain()).toBe(COMMISSION_L1);
    expect(_base.referrals.get('r1').isPaid).toBe(true);
  });

  it('un second appel ne crédite pas une seconde fois', async () => {
    await referral.triggerCommissions('filleul');
    await referral.triggerCommissions('filleul');
    expect(gainsDuParrain()).toBe(COMMISSION_L1);
  });

  it('deux appels simultanés ne créditent qu\'une fois', async () => {
    // Deux validations du même reçu d'achat intégré qui se croisent : les deux
    // lisent `isPaid: false` avant que l'une ait écrit.
    await Promise.all([
      referral.triggerCommissions('filleul'),
      referral.triggerCommissions('filleul'),
    ]);

    expect(gainsDuParrain()).toBe(COMMISSION_L1);
    expect(_base.referrals.get('r1').isPaid).toBe(true);
  });

  it('le montant versé est inscrit sur la ligne de parrainage', async () => {
    // Contrepartie : un correctif qui n'écrirait plus que `isPaid` laisserait
    // `commissionAmount` à zéro, et l'historique des gains afficherait des
    // lignes à 0 FCFA pour de l'argent réellement versé.
    await referral.triggerCommissions('filleul');
    expect(_base.referrals.get('r1').commissionAmount).toBe(COMMISSION_L1);
  });
});
