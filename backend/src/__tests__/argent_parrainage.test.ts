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

// ── Une base en mémoire, avant tout import de service ────────────────────────
jest.mock('../lib/prisma', () => {
  const base = {
    users:        new Map<string, any>(),
    referrals:    new Map<string, any>(),
    transactions: new Map<string, any>(),
  };

  /** Une ligne satisfait-elle une clause `where` plate ? */
  const correspond = (ligne: any, where: any): boolean =>
    Object.entries(where ?? {}).every(([cle, cond]: [string, any]) => {
      if (cond !== null && typeof cond === 'object') {
        if ('gte' in cond) return ligne[cle] >= cond.gte;
        if ('equals' in cond) return ligne[cle] === cond.equals;
        return false;
      }
      return ligne[cle] === cond;
    });

  /** Applique un `data` Prisma (valeurs directes ou `increment`/`decrement`). */
  const appliquer = (ligne: any, data: any) => {
    for (const [cle, val] of Object.entries(data ?? {})) {
      if (val !== null && typeof val === 'object' && !(val instanceof Date)) {
        const v: any = val;
        if ('increment' in v) { ligne[cle] = (ligne[cle] ?? 0) + v.increment; continue; }
        if ('decrement' in v) { ligne[cle] = (ligne[cle] ?? 0) - v.decrement; continue; }
      }
      ligne[cle] = val;
    }
  };

  /**
   * Résout les relations demandées par `include`.
   *
   * [liens] associe un nom de relation à la clé étrangère qui la porte ; la
   * cible est toujours `users` ici, seules tables reliées dans ce banc.
   */
  const joindre = (ligne: any, include: any, liens: Record<string, string>) => {
    if (!include) return ligne;
    const enrichie = { ...ligne };
    for (const nom of Object.keys(include)) {
      if (!include[nom] || !liens[nom]) continue;
      const cible = base.users.get(ligne[liens[nom]]);
      enrichie[nom] = cible ? { ...cible } : null;
    }
    return enrichie;
  };

  /** Les opérations d'une table. Toutes asynchrones : elles cèdent la main. */
  const table = (magasin: Map<string, any>, liens: Record<string, string> = {}) => ({
    findUnique: async ({ where, include }: any) => {
      const l = [...magasin.values()].find((x) => correspond(x, where));
      return l ? joindre({ ...l }, include, liens) : null;
    },
    findMany: async ({ where, include }: any = {}) =>
      [...magasin.values()]
        .filter((x) => correspond(x, where))
        .map((x) => joindre({ ...x }, include, liens)),
    update: async ({ where, data }: any) => {
      const l = [...magasin.values()].find((x) => correspond(x, where));
      if (!l) throw new Error('ligne introuvable');
      appliquer(l, data);
      return { ...l };
    },
    updateMany: async ({ where, data }: any) => {
      const lignes = [...magasin.values()].filter((x) => correspond(x, where));
      lignes.forEach((l) => appliquer(l, data));
      return { count: lignes.length };
    },
    create: async ({ data }: any) => {
      const id = data.id ?? `id-${magasin.size + 1}`;
      const l = { id, ...data };
      magasin.set(id, l);
      return { ...l };
    },
  });

  const prisma: any = {
    user:        table(base.users),
    referral:    table(base.referrals, { referrer: 'referrerId', referred: 'referredId' }),
    transaction: table(base.transactions, { user: 'userId' }),
    // Une transaction simulée : elle exécute la suite, sans isolation. Voir la
    // note en tête de fichier sur ce que cela permet d'établir ou non.
    $transaction: async (fn: any) => fn(prisma),
  };

  return { prisma, _base: base };
});

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
