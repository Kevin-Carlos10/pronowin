import { miseSuggeree, partSelonConfiance, pasDeDevise } from '../services/mise_suggeree';
describe('barème obligatoire et arrondi inférieur', () => {
  it('conserve les trois taux décidés', () => {
    expect([1,2,3,4,5].map(partSelonConfiance)).toEqual([.015,.015,.03,.03,.05]);
  });
  it.each([0,6,60,-1,NaN,Infinity,3.5])('aucune mise pour une confiance invalide %s', note => {
    expect(miseSuggeree(10000,note)).toBe(0);
  });
  it('ne gonfle pas le montant pour atteindre une centaine', () => {
    expect(miseSuggeree(10000,1)).toBe(150);
    expect(miseSuggeree(42000,4)).toBe(1260);
    expect(miseSuggeree(15250,5)).toBe(762);
    expect(miseSuggeree(500,1)).toBe(7);
  });
  it('respecte les unités monétaires et les petits soldes', () => {
    expect(pasDeDevise('xof')).toBe(1);
    expect(pasDeDevise('EUR')).toBe(.01);
    expect(miseSuggeree(201,3,'EUR')).toBe(6.03);
    expect(miseSuggeree(20,1,'XOF')).toBe(0);
    expect(miseSuggeree(50,5,'XOF')).toBe(2);
  });
  it('ne dépasse le taux pour aucun solde testé', () => {
    for(const balance of [0,1,20,500,1000,9999,12345.67,100000]) for(const note of [1,2,3,4,5]) for(const currency of ['XOF','EUR']) {
      const stake = miseSuggeree(balance,note,currency);
      expect(stake).toBeGreaterThanOrEqual(0);
      expect(stake).toBeLessThanOrEqual(balance*partSelonConfiance(note)+1e-8);
    }
  });
  it.each([-1,NaN,Infinity])('solde invalide %s', balance => expect(miseSuggeree(balance,5)).toBe(0));
});
