/**
 * Le parcours « code promo » n'est plus un tarif, c'est une offre.
 *
 * Avant : −30 % sur l'abonnement. L'utilisateur ouvrait un compte chez un
 * partenaire **et** payait quand même.
 *
 * Maintenant : le **premier mois** de Premium offert, contre l'ouverture d'un
 * compte partenaire avec notre code et la preuve du dépôt initial. Une seule
 * fois dans la vie du compte — au renouvellement, le tarif normal s'applique.
 *
 * Deux propriétés se perdent facilement et coûtent cher :
 *
 *  1. la durée accordée doit être celle de l'offre, jamais celle qui traîne
 *     dans le formulaire d'administration ;
 *  2. l'offre ne doit pas se reconduire — sinon le même justificatif rend le
 *     Premium gratuit à vie.
 *
 * Ces contrôles s'exécutent : c'est un enchaînement d'appels qui est en cause,
 * pas une forme de code.
 */
const proofs: any[] = [];
const subscriptions: any[] = [];

jest.mock('../lib/prisma', () => ({
  prisma: {
    subscriptionProof: {
      findFirst: jest.fn(async ({ where }: any) =>
        proofs.find(p =>
          p.userId === where.userId &&
          p.status === where.status &&
          (where.type === undefined || p.type === where.type)) ?? null),
      create: jest.fn(async ({ data }: any) => {
        const p = { id: `proof-${proofs.length + 1}`, ...data };
        proofs.push(p);
        return p;
      }),
      findUnique: jest.fn(async ({ where }: any) =>
        proofs.find(p => p.id === where.id) ?? null),
      update: jest.fn(async ({ where, data }: any) => {
        const p = proofs.find(x => x.id === where.id);
        Object.assign(p, data);
        return p;
      }),
    },
    subscription: {
      create: jest.fn(async ({ data }: any) => { subscriptions.push(data); return data; }),
    },
    user: {
      findUnique: jest.fn(async () => ({ subscriptionExpiresAt: null })),
      update:     jest.fn(async () => ({})),
    },
  },
}));

jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { return {}; } },
}));
jest.mock('../services/referral.service', () => ({
  ReferralService: class { async triggerCommissions() { return {}; } },
}));
jest.mock('../services/payment_method.service', () => ({ listerPubliques: async () => [] }));
jest.mock('../middleware/profile.middleware', () => ({ estProfilComplet: async () => true }));

import { SubscriptionService, OFFRE_CODE_JOURS } from '../services/subscription.service';

const svc = new SubscriptionService();

/** Ce que l'écran envoie sur le parcours « code promo », et rien de plus. */
const SOUMISSION = {
  userId:      'u1',
  type:        'xbet_account_screenshot' as const,
  imageBase64: 'AAAA',
  xbetId:      '123456',
  platform:    '1xbet',
};

beforeEach(() => {
  proofs.length = 0;
  subscriptions.length = 0;
});

describe('offre « premier mois offert »', () => {
  it('la soumission ne réclame ni montant ni numéro Mobile Money', async () => {
    // C'est tout le changement : le parcours ne comporte plus de versement.
    // La version précédente exigeait un montant d'au moins 4 200 FCFA, un
    // numéro d'expéditeur et une seconde capture prouvant le paiement.
    const r = await svc.submitProof(SOUMISSION);

    expect(r.status).toBe('pending');
    expect(proofs).toHaveLength(1);
    expect(proofs[0].amount).toBeNull();
    expect(proofs[0].senderPhone).toBeNull();
  });

  it('l\'identifiant de compte et la plateforme restent exigés', async () => {
    await expect(svc.submitProof({ ...SOUMISSION, xbetId: '  ' }))
      .rejects.toThrow(/ID de compte/);

    await expect(svc.submitProof({ ...SOUMISSION, platform: 'inconnu' }))
      .rejects.toThrow(/[Pp]lateforme/);
  });

  it('l\'approbation accorde exactement la durée de l\'offre', async () => {
    const r = await svc.submitProof(SOUMISSION);

    const avant = Date.now();
    await svc.reviewProof({ proofId: r.proof_id, adminId: 'a1', approved: true });

    expect(subscriptions).toHaveLength(1);
    const jours = Math.round(
      (subscriptions[0].endDate.getTime() - avant) / 86400000);
    expect(jours).toBe(OFFRE_CODE_JOURS);
    expect(subscriptions[0].amountPaid).toBe(0);
  });

  it('une durée saisie côté administration ne peut pas gonfler l\'offre', async () => {
    // Le cas qui resterait invisible : une liste déroulante restée sur
    // « annuel » accorderait douze mois là où l'écran en promettait un.
    const r = await svc.submitProof(SOUMISSION);

    const avant = Date.now();
    await svc.reviewProof({
      proofId: r.proof_id, adminId: 'a1', approved: true, durationDays: 365,
    });

    const jours = Math.round(
      (subscriptions[0].endDate.getTime() - avant) / 86400000);
    expect(jours).toBe(OFFRE_CODE_JOURS);
  });

  it('le paiement direct garde la durée décidée par l\'administration', async () => {
    // Le pendant : la borne ne doit s'appliquer qu'au parcours offert. Sans ce
    // contrôle, forcer 30 jours partout passerait les quatre tests précédents
    // en cassant l'abonnement annuel payé.
    proofs.push({
      id: 'direct-1', userId: 'u2', type: 'payment_screenshot',
      status: 'pending', amount: 54000,
    });

    const avant = Date.now();
    await svc.reviewProof({
      proofId: 'direct-1', adminId: 'a1', approved: true, durationDays: 365,
    });

    const jours = Math.round(
      (subscriptions[0].endDate.getTime() - avant) / 86400000);
    expect(jours).toBe(365);
  });

  it('l\'offre ne se reconduit pas : une seule fois par compte', async () => {
    const r = await svc.submitProof(SOUMISSION);
    await svc.reviewProof({ proofId: r.proof_id, adminId: 'a1', approved: true });

    await expect(svc.submitProof(SOUMISSION))
      .rejects.toThrow(/déjà été accordé/);
  });

  it('une preuve refusée ne consomme pas l\'offre', async () => {
    // Refuser puis interdire de recommencer punirait une capture illisible
    // comme une fraude.
    const r = await svc.submitProof(SOUMISSION);
    await svc.reviewProof({
      proofId: r.proof_id, adminId: 'a1', approved: false, adminNote: 'illisible',
    });

    await expect(svc.submitProof(SOUMISSION)).resolves.toMatchObject({
      status: 'pending',
    });
  });

  it('l\'offre est annoncée en jours, pas en remise', async () => {
    const r = await svc.submitProof(SOUMISSION);

    expect(r.message).toContain(`${OFFRE_CODE_JOURS} jours`);
    expect(r.message).not.toMatch(/%/);
  });
});

describe('les tarifs réduits ont disparu', () => {
  it('aucune constante de prix « code » ne subsiste', async () => {
    const mod: Record<string, unknown> = await import('../services/subscription.service');

    for (const nom of [
      'PREMIUM_PRICE_USD_CODE_MONTHLY', 'PREMIUM_PRICE_USD_CODE_ANNUAL',
      'PREMIUM_PRICE_FCFA_CODE_MONTHLY', 'PREMIUM_PRICE_FCFA_CODE_ANNUAL',
    ]) {
      expect(mod[nom]).toBeUndefined();
    }
    expect(typeof mod.OFFRE_CODE_JOURS).toBe('number');
  });

  it('le serveur publie une durée offerte, plus des prix « code »', async () => {
    const etat: any = await svc.getCurrentSubscription('u1');

    expect(etat.code_offer_days).toBe(OFFRE_CODE_JOURS);
    expect(etat.premium_price_monthly_code_fcfa).toBeUndefined();
    expect(etat.premium_price_annual_code_fcfa).toBeUndefined();
  });
});
