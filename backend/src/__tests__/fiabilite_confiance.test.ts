/**
 * L'indice de confiance, comparé à ce qui s'est réellement passé.
 *
 * Un « 75 % » doit gagner à peu près trois fois sur quatre. Le panneau ne
 * montrait qu'un taux de réussite global, qui ne dit pas si les annonces sont
 * justes.
 */
import {
  analyserFiabilite, groupe, intervalleWilson, verdictDe, cleMarche,
  ECHANTILLON_MINIMAL, type LigneReglee,
} from '../services/fiabilite_confiance.service';

const ligne = (p: Partial<LigneReglee> = {}): LigneReglee => ({
  result: 'WIN', confidencePct: 75, confidenceScore: 4, oddsRecommended: 1.8,
  predictionType: 'win1', marketName: null, isPremium: true, ...p,
});

/** n pronostics à `pct`, dont `gagnes` gagnés. */
const serie = (n: number, gagnes: number, p: Partial<LigneReglee> = {}) =>
  Array.from({ length: n }, (_, i) => ligne({ result: i < gagnes ? 'WIN' : 'LOSS', ...p }));

describe('intervalle de Wilson', () => {
  it('ne conclut pas à une certitude sur dix matchs', () => {
    const [bas, haut] = intervalleWilson(10, 10)!;
    expect(Math.round(bas * 100)).toBe(72);
    expect(haut).toBe(1);
  });

  it('se resserre avec le volume', () => {
    const [b1, h1] = intervalleWilson(7, 10)!;
    const [b2, h2] = intervalleWilson(70, 100)!;
    expect(h2 - b2).toBeLessThan(h1 - b1);
    expect(intervalleWilson(0, 0)).toBeNull();
  });
});

describe('verdict', () => {
  it('pas de verdict sous le seuil, même avec un écart énorme', () => {
    expect(verdictDe(90, 0, ECHANTILLON_MINIMAL - 1)).toBe('echantillon_faible');
  });

  it('un écart dans le bruit statistique est « fiable »', () => {
    // 75 % annoncés, 7 sur 10 : l'écart de 5 points est du hasard.
    expect(verdictDe(75, 7, 10)).toBe('fiable');
  });

  it('trop optimiste, trop prudent', () => {
    expect(verdictDe(85, 25, 50)).toBe('trop_optimiste');  // 50 % réels
    expect(verdictDe(55, 40, 50)).toBe('trop_prudent');    // 80 % réels
  });
});

describe('un groupe', () => {
  it('le taux, l\'annonce, l\'écart, la cote et la chance qu\'elle donne', () => {
    const g = groupe('x', [...serie(20, 12, { confidencePct: 80, oddsRecommended: 2 })]);
    expect(g).toMatchObject({
      tranches: 20, gagnes: 12, tauxReel: 60, annonceMoyen: 80, ecart: -20,
      verdict: 'trop_optimiste', coteMoyenne: 2, chanceCote: 50,
    });
    // 12 × (2 − 1) − 8 = +4 unités sur 20 paris.
    expect(g.rendement).toMatchObject({ unites: 4, paris: 20, roi_pct: 20 });
  });

  it('un remboursement est compté à part, hors du taux', () => {
    const g = groupe('x', [...serie(10, 5), ligne({ result: 'PUSH' })]);
    expect(g).toMatchObject({ tranches: 10, rembourses: 1, tauxReel: 50 });
  });

  it('sans pronostic tranché : rien à affirmer', () => {
    const g = groupe('x', [ligne({ result: 'PUSH' })]);
    expect(g).toMatchObject({ tranches: 0, tauxReel: null, annonceMoyen: null, ecart: null,
                              intervalle: null, verdict: 'echantillon_faible' });
  });
});

describe('l\'analyse complète', () => {
  const lignes = [
    ...serie(12, 6, { confidencePct: 85 }),                                    // 80-89, trop optimiste ?
    ...serie(10, 7, { confidencePct: 72, predictionType: 'over25' }),          // 70-79
    ...serie(3, 3, { confidencePct: null, confidenceScore: 3, isPremium: false,
                     predictionType: 'other', marketName: 'Double Chance' }),  // reconstitué : 50 %
  ];
  const r = analyserFiabilite(lignes);

  it('chaque pronostic tombe dans la tranche de son annonce', () => {
    expect(r.tranches.map((t) => [t.cle, t.tranches])).toEqual([
      ['1-49', 0], ['50-59', 3], ['60-69', 0], ['70-79', 10], ['80-89', 12], ['90-99', 0],
    ]);
  });

  it('un pronostic sans pourcentage saisi prend le milieu de son palier, et se compte', () => {
    expect(r.tranches[1].annonceMoyen).toBe(50);
    expect(r.reconstitues).toBe(3);
  });

  it('les marchés, du plus joué au moins joué, « other » détaillé par marché brut', () => {
    expect(r.marches.map((m) => [m.cle, m.tranches])).toEqual([
      ['win1', 12], ['over25', 10], ['other:Double Chance', 3],
    ]);
    expect(cleMarche({ predictionType: 'other', marketName: null })).toBe('other:');
  });

  it('Premium et gratuits séparés', () => {
    expect(r.formules.map((f) => [f.cle, f.tranches])).toEqual([['premium', 22], ['gratuit', 3]]);
    expect(r.global.tranches).toBe(25);
  });
});
