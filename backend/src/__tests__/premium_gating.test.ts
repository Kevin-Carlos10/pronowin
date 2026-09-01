/**
 * Étanchéité du contenu payant.
 *
 * Ces tests figent ce qui a été trouvé et corrigé à la main : `/pronostics`
 * servait le pronostic premium en clair à tout le monde (le mobile le floutait
 * côté client, mais un simple appel HTTP sans jeton le révélait), et la
 * correction avait ouvert une seconde brèche — le cache des listes n'avait
 * aucune dimension de palier, si bien qu'une réponse d'invité pouvait être
 * resservie à un abonné et inversement.
 *
 * C'est la logique qui protège le chiffre d'affaires : elle doit casser
 * bruyamment si quelqu'un la touche.
 */

// ── Mock Prisma avant tout import du service ──────────────────────────────────
jest.mock('../lib/prisma', () => {
  const mockPronosticFindMany = jest.fn();
  const mockMatchFindMany     = jest.fn().mockResolvedValue([]);
  const mockUserFindUnique    = jest.fn();
  const mockLeagueFindMany    = jest.fn().mockResolvedValue([]);
  return {
    prisma: {
      pronostic:        { findMany: mockPronosticFindMany },
      match:            { findMany: mockMatchFindMany },
      user:             { findUnique: mockUserFindUnique },
      leagueVisibility: { findMany: mockLeagueFindMany },
    },
    _mocks: { mockPronosticFindMany, mockUserFindUnique, mockMatchFindMany },
  };
});

import { PronosticsService } from '../services/pronostics.service';
const { _mocks } = require('../lib/prisma');

const PICK = '+2.5 buts';

/** Pronostic premium minimal, tel que Prisma le renverrait. */
const premiumPronostic = (over: any = {}) => ({
  id: 'prono-1', matchId: 'match-1',
  predictionType: 'over25', predictionLabel: PICK,
  oddsHome: 1.8, oddsDraw: 3.4, oddsAway: 4.2, oddsRecommended: 1.95,
  confidenceScore: 4, isPremium: true, isPublished: true,
  analystNote: 'Note réservée aux abonnés.', result: 'WIN',
  analyst: { name: 'Carlos' },
  match: {
    id: 'match-1', league: 'Ligue 1', leagueCode: 'FR1',
    homeTeam: 'PSG', awayTeam: 'OM', homeTeamLogo: null, awayTeamLogo: null,
    matchDate: new Date('2026-09-01T18:00:00Z'), status: 'SCHEDULED',
    homeScore: null, awayScore: null, homeFormPoints: 10, awayFormPoints: 7,
  },
  ...over,
});

const asUser = (plan: 'free' | 'premium', expired = false) => ({
  subscriptionPlan: plan,
  subscriptionExpiresAt: plan === 'premium'
    ? new Date(Date.now() + (expired ? -86400000 : 30 * 86400000))
    : null,
});

describe('Étanchéité du pronostic premium — getPublishedPronostics', () => {
  let svc: PronosticsService;

  beforeEach(() => {
    svc = new PronosticsService();
    jest.clearAllMocks();
    _mocks.mockPronosticFindMany.mockResolvedValue([premiumPronostic()]);
  });

  const run = async (userId?: string) =>
    (await svc.getPublishedPronostics({ userId, limit: 20 })).data[0];

  it('un invité ne reçoit jamais le pronostic', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(null);
    const row = await run(undefined);

    expect(row.locked).toBe(true);
    expect(row.prediction_label).toBeNull();
    expect(row.prediction_type).toBeNull();
    expect(row.confidence_score).toBeNull();
    expect(row.odds_recommended).toBeNull();
    expect(row.analyst_note).toBeNull();
    // Aucun champ de la réponse ne doit contenir le pick, même indirectement.
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('un utilisateur gratuit ne reçoit pas non plus le pronostic', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(asUser('free'));
    const row = await run('user-free');

    expect(row.locked).toBe(true);
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('un abonné dont l\'abonnement a expiré est traité comme gratuit', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(asUser('premium', true));
    const row = await run('user-expire');

    expect(row.locked).toBe(true);
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('un abonné actif reçoit le pronostic complet', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(asUser('premium'));
    const row = await run('user-premium');

    expect(row.locked).toBe(false);
    expect(row.prediction_label).toBe(PICK);
    expect(row.confidence_score).toBe(4);
    expect(row.analyst_note).toBe('Note réservée aux abonnés.');
  });

  it('les données du match restent servies même verrouillées', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(null);
    const row = await run(undefined);

    // Ce n'est pas le produit vendu : le masquer transformerait la page en
    // cul-de-sac sans rien protéger.
    expect(row.home_team).toBe('PSG');
    expect(row.away_team).toBe('OM');
    expect(row.odds_home).toBe(1.8);
    expect(row.home_form_points).toBe(10);
    // Le résultat passé reste visible : c'est l'argument de vente.
    expect(row.result).toBe('WIN');
  });

  it('un pronostic NON premium est servi en entier à un invité', async () => {
    _mocks.mockPronosticFindMany.mockResolvedValue([
      premiumPronostic({ isPremium: false }),
    ]);
    _mocks.mockUserFindUnique.mockResolvedValue(null);
    const row = await run(undefined);

    expect(row.locked).toBe(false);
    expect(row.prediction_label).toBe(PICK);
  });
});

describe('Étanchéité du pronostic premium — getAllMatches', () => {
  let svc: PronosticsService;

  beforeEach(() => {
    svc = new PronosticsService();
    jest.clearAllMocks();
    _mocks.mockMatchFindMany.mockResolvedValue([{
      ...premiumPronostic().match,
      pronostic: premiumPronostic(),
    }]);
  });

  const run = async (userId?: string) =>
    (await svc.getAllMatches({ userId, limit: 20 })).data[0];

  it('un invité ne reçoit pas le pronostic premium', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(null);
    const row = await run(undefined);

    expect(row.locked).toBe(true);
    expect(row.prediction_label).toBeNull();
    expect(JSON.stringify(row)).not.toContain(PICK);
  });

  it('un abonné actif le reçoit', async () => {
    _mocks.mockUserFindUnique.mockResolvedValue(asUser('premium'));
    const row = await run('user-premium');

    expect(row.locked).toBe(false);
    expect(row.prediction_label).toBe(PICK);
  });
});
