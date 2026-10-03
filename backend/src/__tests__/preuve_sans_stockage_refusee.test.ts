const preuves: any[] = [];

jest.mock('../lib/prisma', () => {
  const prisma: any = {
    subscriptionProof: {
      findFirst: jest.fn(async () => null),
      create: jest.fn(async ({ data }: any) => {
        const p = { id: `proof-${preuves.length + 1}`, ...data };
        preuves.push(p);
        return p;
      }),
    },
    subscription: { create: jest.fn(async ({ data }: any) => data) },
    user: {
      findUnique: jest.fn(async () => ({ subscriptionExpiresAt: null })),
      update:     jest.fn(async () => ({})),
    },
  };
  prisma.$transaction = async (fn: any) => fn(prisma);
  return { prisma };
});

jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { return {}; } },
}));
jest.mock('../services/referral.service', () => ({
  ReferralService: class { async triggerCommissions() { return {}; } },
}));
jest.mock('../services/payment_method.service', () => ({ listerPubliques: async () => [] }));
jest.mock('../middleware/profile.middleware', () => ({ estProfilComplet: async () => true }));

import { SubscriptionService } from '../services/subscription.service';

/**
 * Sans stockage d'images, une preuve de paiement doit être refusée.
 *
 * ── Ce que faisait le repli ───────────────────────────────────────────────
 *
 * Quand S3 n'était pas configuré, `submitProof` écrivait
 * `dev://proof/<userId>/<horodatage>` — une URL qui ne pointe sur rien — et la
 * soumission **réussissait**. L'image elle-même était jetée : le base64 n'est
 * conservé nulle part.
 *
 * L'utilisateur voyait « preuve envoyée » et attendait son Premium.
 * L'administrateur recevait une preuve sans preuve, et devait décider d'activer
 * ou non un abonnement payé en regardant un lien mort. Depuis que l'identifiant
 * 1xBet est relevé à la validation, il devait même y lire un numéro « lisible
 * sur la capture » — celle qui n'existait pas.
 *
 * ── La règle existait déjà, ailleurs ──────────────────────────────────────
 *
 * L'envoi d'avatar traite exactement la même situation : il répond 503 et
 * refuse. La règle avait été écrite pour la photo de profil, et oubliée pour
 * l'argent. C'est la forme la plus commune du défaut traqué dans ce dépôt :
 * appliquée à un endroit, absente à l'autre — et c'est le mauvais endroit qui
 * l'avait perdue.
 *
 * ── Pourquoi refuser vaut mieux ───────────────────────────────────────────
 *
 * Un utilisateur qui ne peut pas envoyer sa capture recommence dans dix
 * minutes. Un utilisateur dont la capture a disparu en silence a payé pour
 * rien, et personne ne peut le lui prouver ni le lui rendre.
 *
 * ── Pourquoi le refus est le comportement par défaut ──────────────────────
 *
 * L'échappatoire de développement exige `NODE_ENV` valant explicitement
 * `development` ou `test`. Une variable absente ou mal écrite refuse. L'inverse
 * — autoriser sauf si l'on est sûr d'être en production — aurait fait dépendre
 * l'intégrité des paiements d'une variable d'environnement correctement posée.
 */
const svc = new SubscriptionService();

const SOUMISSION = {
  userId:      'u1',
  type:        'xbet_account_screenshot' as const,
  imageBase64: 'AAAA',
  platform:    '1xbet',
};

describe('preuve soumise sans stockage configuré', () => {
  const envInitial = process.env.NODE_ENV;

  beforeEach(() => { preuves.length = 0; });
  afterEach(() => { process.env.NODE_ENV = envInitial; });

  it('en production, la soumission est refusée', async () => {
    process.env.NODE_ENV = 'production';
    await expect(svc.submitProof(SOUMISSION)).rejects.toThrow(/indisponible/i);
  });

  it('et rien n\'est enregistré', async () => {
    process.env.NODE_ENV = 'production';
    await svc.submitProof(SOUMISSION).catch(() => {});

    expect(preuves).toHaveLength(0);
  });

  it('le message ne promet pas que le paiement est perdu', async () => {
    // Quelqu'un qui vient de payer et voit une erreur a besoin de savoir que
    // son argent n'est pas parti avec la requête.
    process.env.NODE_ENV = 'production';
    const erreur = await svc.submitProof(SOUMISSION).catch((e) => e);

    expect(String(erreur.message)).toMatch(/aucun paiement ne sera perdu/i);
  });

  it('une variable absente refuse aussi', async () => {
    // Le refus par défaut : c'est la position sûre. Autoriser tant qu'on n'est
    // pas certain d'être en production ferait dépendre l'intégrité des
    // paiements d'une variable correctement posée.
    delete process.env.NODE_ENV;
    await expect(svc.submitProof(SOUMISSION)).rejects.toThrow(/indisponible/i);
    expect(preuves).toHaveLength(0);
  });

  it('une valeur inattendue refuse également', async () => {
    process.env.NODE_ENV = 'staging';
    await expect(svc.submitProof(SOUMISSION)).rejects.toThrow(/indisponible/i);
  });

  it('en développement, le raccourci reste disponible', async () => {
    // Sans lui, personne ne pourrait exercer le parcours hors production.
    process.env.NODE_ENV = 'development';
    const r = await svc.submitProof(SOUMISSION);

    expect(r.status).toBe('pending');
    expect(preuves).toHaveLength(1);
    expect(String(preuves[0].screenshotUrl)).toContain('dev://');
  });
});
