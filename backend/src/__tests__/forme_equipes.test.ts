/**
 * La forme des équipes, tirée de la séquence du fournisseur.
 *
 * `homeFormPoints` / `awayFormPoints` n'étaient écrits nulle part : chaque
 * analyse annonçait « Aucune donnée de forme récente », jusque sur
 * France – Belgique (vidéo du 5 octobre 2026).
 */
const match = {
  id: 'm1', homeTeam: 'France', awayTeam: 'Belgium', status: 'SCHEDULED',
  source: 'API_FOOTBALL', externalId: 123, homeFormPoints: 0, awayFormPoints: 0,
};
const prono = {
  id: 'p1', matchId: 'm1', predictionType: 'win1', oddsHome: 1.57, oddsDraw: 4.2, oddsAway: 5.4,
  oddsRecommended: 1.57, aiProbability: null as number | null, aiExplanation: null as string | null, match,
};

jest.mock('../lib/prisma', () => ({
  prisma: {
    pronostic: { findUnique: jest.fn(), update: jest.fn() },
    match: { findUnique: jest.fn(), update: jest.fn() },
  },
}));
jest.mock('../services/api_football.service', () => ({
  apiFootballInsights: { getPrediction: jest.fn() },
}));

import { pointsDeForme, analyzePronostic } from '../services/ai_prediction.service';

const { prisma } = require('../lib/prisma');
const { apiFootballInsights } = require('../services/api_football.service');

beforeEach(() => {
  jest.clearAllMocks();
  prisma.pronostic.findUnique.mockImplementation(async () => ({ ...prono, match: { ...match } }));
  prisma.pronostic.update.mockResolvedValue({});
  prisma.match.update.mockResolvedValue({});
  apiFootballInsights.getPrediction.mockResolvedValue({
    percentHome: 55, percentDraw: 25, percentAway: 20,
    formHome: 'LDWWWDW', formAway: 'WLLDL',
  });
});

describe('les points de forme', () => {
  it('les cinq derniers matchs, 3 par victoire, 1 par nul', () => {
    expect(pointsDeForme('LDWWWDW')).toBe(3 + 3 + 3 + 1 + 3);  // WWWDW
    expect(pointsDeForme('WLLDL')).toBe(3 + 0 + 0 + 1 + 0);
    expect(pointsDeForme('DL')).toBe(1);
  });

  it('une séquence absente n\'est pas une forme nulle', () => {
    expect(pointsDeForme(null)).toBeNull();
    expect(pointsDeForme('')).toBeNull();
  });
});

describe('l\'analyse d\'un match', () => {
  it('lit la forme dans la prédiction, la garde sur le match, et l\'explique', async () => {
    const r = await analyzePronostic('p1');
    expect(r.explanation).not.toContain('Aucune donnée de forme');
    expect(r.explanation).toContain('France totalise 13 points contre 4 à Belgium');
    expect(prisma.match.update).toHaveBeenCalledWith({
      where: { id: 'm1' }, data: { homeFormPoints: 13, awayFormPoints: 4 },
    });
  });

  it('une analyse en cache faite sans la forme est recalculée', async () => {
    prisma.pronostic.findUnique.mockImplementation(async () => ({
      ...prono, aiProbability: 58,
      aiExplanation: "Aucune donnée de forme récente n'est disponible pour ces équipes : …", match: { ...match },
    }));
    const r = await analyzePronostic('p1');
    expect(apiFootballInsights.getPrediction).toHaveBeenCalled();
    expect(r.explanation).not.toContain('Aucune donnée de forme');
  });

  it('une analyse en cache complète est servie telle quelle', async () => {
    prisma.pronostic.findUnique.mockImplementation(async () => ({
      ...prono, aiProbability: 61, aiExplanation: 'Sur la forme récente, …', match: { ...match },
    }));
    expect(await analyzePronostic('p1')).toEqual({ probability: 61, explanation: 'Sur la forme récente, …' });
    expect(apiFootballInsights.getPrediction).not.toHaveBeenCalled();
  });
});
