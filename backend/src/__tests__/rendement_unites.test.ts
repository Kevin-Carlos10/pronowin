/**
 * Le rendement en unités à côté du taux de réussite (constat A8 de l'audit
 * du 24 septembre 2026) : à la cote 1,13, 86 % de réussite perd de l'argent.
 */
import { rendementUnites } from '../utils/rendement';

const serie = (gagnes: number, perdus: number, cote: number) => [
  ...Array.from({ length: gagnes }, () => ({ result: 'WIN', oddsRecommended: cote })),
  ...Array.from({ length: perdus }, () => ({ result: 'LOSS', oddsRecommended: cote })),
];

describe('rendement en unités (A8)', () => {
  it('86 % de réussite à la cote 1,13 : un taux flatteur, un rendement négatif', () => {
    const r = rendementUnites(serie(86, 14, 1.13));
    expect(r.paris).toBe(100);
    expect(r.unites).toBeCloseTo(86 * 0.13 - 14, 2);   // −2,82 u
    expect(r.unites).toBeLessThan(0);
    expect(r.roi_pct).toBe(-2.8);
  });

  it('50 % à la cote 2,20 : un taux médiocre, un rendement positif', () => {
    const r = rendementUnites(serie(10, 10, 2.2));
    expect(r).toEqual({ unites: 2, paris: 20, roi_pct: 10 });
  });

  it('un remboursé ou un pari en cours ne compte ni en gain ni en nombre', () => {
    const r = rendementUnites([
      { result: 'WIN', oddsRecommended: 1.8 }, { result: 'PUSH', oddsRecommended: 3 },
      { result: null, oddsRecommended: 2 }]);
    expect(r).toEqual({ unites: 0.8, paris: 1, roi_pct: 80 });
  });

  it('sans pari réglé, pas de pourcentage inventé', () => {
    expect(rendementUnites([])).toEqual({ unites: 0, paris: 0, roi_pct: null });
  });
});
