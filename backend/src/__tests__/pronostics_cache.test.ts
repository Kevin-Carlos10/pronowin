/**
 * Isolation du cache des listes de pronostics, au niveau HTTP.
 *
 * Le test unitaire `premium_gating` couvre la sérialisation ; il ne peut pas
 * couvrir la clé de cache, qui vit dans le contrôleur. Or c'est exactement là
 * qu'une régression a été introduite : en rendant la réponse dépendante des
 * droits de l'appelant, le cache — qui n'avait aucune dimension utilisateur —
 * s'est mis à resservir la première réponse à tout le monde. Un abonné
 * recevait la version verrouillée d'un invité, et surtout un invité pouvait
 * recevoir la version complète d'un abonné.
 *
 * On monte le vrai routeur avec Prisma mocké : pas de base de test à gérer, et
 * la chaîne middleware + contrôleur + cache est réellement traversée.
 */

// ── Mock Prisma avant tout import ─────────────────────────────────────────────
jest.mock('../lib/prisma', () => {
  const mockPronosticFindMany = jest.fn();
  const mockUserFindUnique    = jest.fn();
  return {
    prisma: {
      pronostic:        { findMany: mockPronosticFindMany },
      match:            { findMany: jest.fn().mockResolvedValue([]) },
      user:             { findUnique: mockUserFindUnique, update: jest.fn().mockResolvedValue({}) },
      leagueVisibility: { findMany: jest.fn().mockResolvedValue([]) },
    },
    _mocks: { mockPronosticFindMany, mockUserFindUnique },
  };
});

process.env.JWT_SECRET = 'test-secret-access';

import express from 'express';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import pronosticsRoutes from '../routes/pronostics.routes';
import { cache } from '../services/cache.service';

const { _mocks } = require('../lib/prisma');

const app = express();
app.use(express.json());
app.use('/api/v1/pronostics', pronosticsRoutes);

const PICK = '+2.5 buts';

const premiumRow = {
  id: 'prono-1', matchId: 'match-1',
  predictionType: 'over25', predictionLabel: PICK,
  oddsHome: 1.8, oddsDraw: 3.4, oddsAway: 4.2, oddsRecommended: 1.95,
  confidenceScore: 4, isPremium: true, isPublished: true,
  analystNote: 'Note abonnés.', result: 'WIN',
  analyst: { name: 'Carlos' },
  match: {
    id: 'match-1', league: 'Ligue 1', leagueCode: 'FR1',
    homeTeam: 'PSG', awayTeam: 'OM', homeTeamLogo: null, awayTeamLogo: null,
    matchDate: new Date('2026-09-01T18:00:00Z'), status: 'SCHEDULED',
    homeScore: null, awayScore: null, homeFormPoints: 10, awayFormPoints: 7,
  },
};

/** Utilisateurs distincts : on ne bascule jamais le plan d'un même compte. */
const USERS: Record<string, any> = {
  'user-free':    { subscriptionPlan: 'free',    subscriptionExpiresAt: null,  isActive: true },
  'user-premium': { subscriptionPlan: 'premium', subscriptionExpiresAt: new Date(Date.now() + 30 * 86400000), isActive: true },
};

const token = (id: string) => jwt.sign({ userId: id }, process.env.JWT_SECRET!, { expiresIn: '1h' });

/** Un appel à /pronostics, en invité si `userId` est omis. */
async function fetchList(userId?: string) {
  const req = request(app).get('/api/v1/pronostics?limit=20');
  if (userId) req.set('Authorization', `Bearer ${token(userId)}`);
  const res = await req;
  expect(res.status).toBe(200);
  return res.body.data[0];
}

describe('Cache de /pronostics — isolation par palier', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    cache.clear();
    _mocks.mockPronosticFindMany.mockResolvedValue([premiumRow]);
    _mocks.mockUserFindUnique.mockImplementation(
      ({ where }: any) => Promise.resolve(USERS[where.id] ?? null));
  });

  it('sert la version verrouillée à un invité', async () => {
    const row = await fetchList();
    expect(row.locked).toBe(true);
    expect(row.prediction_label).toBeNull();
  });

  it('ne resert pas la réponse d\'un invité à un abonné', async () => {
    await fetchList();                       // remplit le cache en « guest »
    const row = await fetchList('user-premium');

    expect(row.locked).toBe(false);
    expect(row.prediction_label).toBe(PICK);
  });

  it('ne resert pas la réponse d\'un abonné à un invité', async () => {
    await fetchList('user-premium');         // remplit le cache en « premium »
    const row = await fetchList();

    expect(row.locked).toBe(true);
    expect(row.prediction_label).toBeNull();
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('ne resert pas la réponse d\'un abonné à un compte gratuit', async () => {
    await fetchList('user-premium');
    const row = await fetchList('user-free');

    expect(row.locked).toBe(true);
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('les trois paliers restent cohérents en séquence entrelacée', async () => {
    const seq = [
      [undefined,      true],
      ['user-premium', false],
      ['user-free',    true],
      [undefined,      true],
      ['user-premium', false],
    ] as [string | undefined, boolean][];

    for (const [userId, expectLocked] of seq) {
      const row = await fetchList(userId);
      expect(row.locked).toBe(expectLocked);
      expect(row.prediction_label === null).toBe(expectLocked);
    }
  });

  it('le cache fonctionne toujours À L\'INTÉRIEUR d\'un palier', async () => {
    // Sans cette garantie, on aurait « corrigé » le bug en désactivant le
    // cache, ce qui règle la fuite mais coûte une requête par appel.
    await fetchList();
    await fetchList();
    await fetchList();

    expect(_mocks.mockPronosticFindMany).toHaveBeenCalledTimes(1);
  });

  it('chaque palier interroge la base une fois, pas plus', async () => {
    await fetchList();
    await fetchList();
    await fetchList('user-premium');
    await fetchList('user-premium');
    await fetchList('user-free');

    // 3 paliers distincts → 3 requêtes, et pas 5.
    expect(_mocks.mockPronosticFindMany).toHaveBeenCalledTimes(3);
  });
});
