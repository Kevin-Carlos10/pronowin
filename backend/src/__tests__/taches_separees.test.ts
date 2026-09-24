/**
 * Les tâches planifiées hors de l'API (constat P1 de l'audit du 24 septembre
 * 2026).
 *
 * Elles tournaient dans le processus de l'API : deux exemplaires de l'API,
 * et chaque rappel, chaque notification partait deux fois. Elles peuvent
 * désormais tourner dans un processus dédié — à condition que l'API cesse de
 * les lancer, que ce processus s'arrête proprement, et que la page Santé
 * continue de voir ce qu'elles font.
 */
const mockAppels: string[] = [];
let mockPublie: { value: string; updatedAt: Date } | null = null;

jest.mock('../lib/prisma', () => ({
  prisma: {
    $queryRaw: jest.fn(async () => [{ '?column?': 1 }]),
    match: { count: jest.fn(async () => 0) },
    iapNotification: { groupBy: jest.fn(async () => []) },
    subscriptionProof: { count: jest.fn(async () => 0), findFirst: jest.fn(async () => null) },
    appSetting: {
      upsert: jest.fn(async ({ update }: any) => {
        mockPublie = { value: update.value, updatedAt: new Date() };
      }),
      findUnique: jest.fn(async () => mockPublie),
    },
  },
}));
jest.mock('../services/pronostics.service', () => ({
  PronosticsService: class {
    async syncMatchScores() { mockAppels.push('scores'); }
    async checkMatchesSoon() { mockAppels.push('bientot'); return { notified: 0 }; }
  },
}));
jest.mock('../services/subscription.service', () => ({
  SubscriptionService: class {
    async notifyExpiringSubscriptions() { mockAppels.push('expiration'); return { notified: 0 }; }
  },
}));
jest.mock('../services/iap_notifications.service', () => ({
  FileNotificationsIap: class { async traiterEnAttente() { mockAppels.push('store'); return 0; } },
}));
jest.mock('../services/alerte_achats.service', () => ({
  signalerAchatsEnRetard: async () => { mockAppels.push('achats'); return { enRetard: 0, alerteEnvoyee: false }; },
  SEUIL_ATTENTE_HEURES: 6,
  INTERVALLE_CONTROLE_MS: 6 * 3600_000,
}));

import { demarrerTaches, tachesDansLApi } from '../taches';
import { _reinitialiser, publierEtat, SILENCE_MAX_MS, suivre } from '../services/etat_taches';
import { lireSante } from '../services/sante.service';

const ENV = { ...process.env };
afterEach(() => {
  process.env = { ...ENV };
  publierEtat(false);
  _reinitialiser();
  mockAppels.length = 0;
  mockPublie = null;
  jest.useRealTimers();
});

describe('qui lance les tâches', () => {
  it('l\'API, tant qu\'aucun processus dédié ne s\'en charge', () => {
    expect(tachesDansLApi({})).toBe(true);
    expect(tachesDansLApi({ TACHES_SEPAREES: '1' })).toBe(false);
  });
});

describe('le processus des tâches', () => {
  it('lance chaque tâche, et plus aucune une fois arrêté', async () => {
    jest.useFakeTimers();
    process.env.API_FOOTBALL_KEY = 'banc';
    const arreter = demarrerTaches();

    await jest.advanceTimersByTimeAsync(3 * 60_000 + 1000);
    expect(new Set(mockAppels)).toEqual(new Set(['scores', 'bientot', 'expiration', 'store', 'achats']));

    arreter();
    mockAppels.length = 0;
    await jest.advanceTimersByTimeAsync(24 * 3600_000);
    // Sans l'arrêt, la base serait sollicitée pendant qu'elle se ferme.
    expect(mockAppels).toEqual([]);
  });

  it('publie l\'état de ses tâches en base, l\'API non', async () => {
    await suivre('file_notifications_store', async () => 3, (n) => `${n} examinée(s)`);
    await new Promise(r => setImmediate(r));
    expect(mockPublie).toBeNull();                  // l'API garde l'état en mémoire

    publierEtat();
    await suivre('file_notifications_store', async () => 3, (n) => `${n} examinée(s)`);
    await new Promise(r => setImmediate(r));
    expect(JSON.parse(mockPublie!.value).taches.file_notifications_store.detail).toBe('3 examinée(s)');
  });
});

describe('la page Santé, tâches séparées', () => {
  beforeEach(() => { process.env.TACHES_SEPAREES = '1'; });

  it('montre les tâches publiées par le processus dédié', async () => {
    publierEtat();
    await suivre('rappel_expiration', async () => ({ notified: 2 }), (r) => `${r.notified} rappel(s)`);
    await new Promise(r => setImmediate(r));
    _reinitialiser();                                // ce n'est pas la mémoire de l'API qui parle

    const s = await lireSante();
    expect(s.taches.rappel_expiration.detail).toBe('2 rappel(s)');
    expect(s.processusTaches).toMatchObject({ separe: true, silencieux: false });
  });

  it('signale un processus muet', async () => {
    mockPublie = {
      value: JSON.stringify({ demarreLe: '2026-09-24T00:00:00Z', taches: {}, quotaFootball: null }),
      updatedAt: new Date(Date.now() - SILENCE_MAX_MS - 60_000),
    };
    expect((await lireSante()).processusTaches).toMatchObject({ separe: true, silencieux: true });

    mockPublie = null;                               // jamais démarré
    expect((await lireSante()).processusTaches).toMatchObject({ separe: true, silencieux: true });
  });
});
