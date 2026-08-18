import { computeProbability, modelSignal } from '../services/ai_prediction.service';
import type { MatchPrediction } from '../services/api_football_insights.service';

/**
 * Intégration du modèle API-Football comme troisième signal.
 *
 * Deux propriétés comptent ici, et une seule est évidente :
 *
 * 1. sans signal externe, le calcul doit rendre **exactement** ce qu'il rendait
 *    avant — sinon l'ajout serait une régression silencieuse sur tous les
 *    pronostics déjà publiés ;
 * 2. le signal ne doit s'appliquer qu'au marché « vainqueur ». L'API ne donne
 *    de pourcentages que pour domicile/nul/extérieur ; les transposer à un
 *    total de buts serait une invention.
 */

const prediction = (h: number, d: number, a: number): MatchPrediction => ({
  advice: null, winnerName: null, winnerComment: null,
  percentHome: h, percentDraw: d, percentAway: a,
  underOver: null, comparisons: [],
  formHome: null, formAway: null,
  leagueId: null, season: null, homeTeamId: null, awayTeamId: null,
  cleanSheetHome: 0, cleanSheetAway: 0,
  failedToScoreHome: 0, failedToScoreAway: 0,
});

describe('modelSignal', () => {
  it('mappe chaque issue 1X2 sur son pourcentage', () => {
    const p = prediction(45, 30, 25);
    expect(modelSignal('win1', p)).toBeCloseTo(0.45);
    expect(modelSignal('draw', p)).toBeCloseTo(0.30);
    expect(modelSignal('win2', p)).toBeCloseTo(0.25);
  });

  it('rend null hors du marché vainqueur', () => {
    const p = prediction(45, 30, 25);
    for (const type of ['over25', 'under25', 'btts', 'over35', 'other']) {
      expect(modelSignal(type, p)).toBeNull();
    }
  });

  it('rend null sans prédiction', () => {
    expect(modelSignal('win1', null)).toBeNull();
  });
});

describe('computeProbability — non-régression', () => {
  // Le paramètre est optionnel : tout appel existant doit donner le même
  // résultat qu'avant l'ajout.
  it('sans signal externe, identique à l’ancien calcul', () => {
    const sansParam  = computeProbability('win1', 1.8, 3.5, 4.2, 1.8, 9, 3);
    const avecNull   = computeProbability('win1', 1.8, 3.5, 4.2, 1.8, 9, 3, null);
    expect(sansParam).toBe(avecNull);

    // Cote 1.80 → 55.6 % implicite ; forme 9 vs 3 → part domicile 0.75.
    // 0.556 × 0.65 + 0.75 × 0.35 = 0.624 → 62 %.
    expect(sansParam).toBe(62);
  });

  it('sans forme ni modèle, la cote décide seule', () => {
    // Marché de totaux : la forme est écartée par construction.
    expect(computeProbability('over25', 2, 3, 2, 2.0, 9, 3)).toBe(50);
  });
});

describe('computeProbability — avec le modèle', () => {
  it('le modèle tire la probabilité vers lui', () => {
    const sans = computeProbability('win1', 1.8, 3.5, 4.2, 1.8, 9, 3);
    const haut = computeProbability('win1', 1.8, 3.5, 4.2, 1.8, 9, 3, 0.90);
    const bas  = computeProbability('win1', 1.8, 3.5, 4.2, 1.8, 9, 3, 0.20);

    expect(haut).toBeGreaterThan(sans);
    expect(bas).toBeLessThan(sans);
  });

  it('la cote reste le signal dominant', () => {
    // Cote très favorable (1.20 → 83 %), modèle très défavorable (10 %).
    // Le résultat doit rester du côté de la cote, pas s'effondrer.
    const p = computeProbability('win1', 1.2, 5, 9, 1.2, 0, 0, 0.10);
    expect(p).toBeGreaterThan(50);
  });

  it('respecte les bornes 15–95', () => {
    expect(computeProbability('win1', 1.01, 20, 30, 1.01, 12, 0, 0.99))
      .toBeLessThanOrEqual(95);
    expect(computeProbability('win2', 30, 20, 1.01, 30, 12, 0, 0.01))
      .toBeGreaterThanOrEqual(15);
  });

  it('sans forme, le modèle pèse 30 % face à la cote', () => {
    // Cote 2.00 → 50 %. Modèle 100 %. 0.50 × 0.70 + 1.00 × 0.30 = 0.65.
    expect(computeProbability('win1', 2, 3, 4, 2, 0, 0, 1.0)).toBe(65);
  });
});
