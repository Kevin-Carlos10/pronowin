import { suggestStake } from '../services/bankroll.service';
describe('mise imposée calculée par le service',()=>{
  it.each([[1,150],[2,150],[3,300],[4,300],[5,500]])('note %s : %s sur un solde de 10 000', (note,amount)=>expect(suggestStake(10000,note)).toBe(amount));
  it('arrondit vers le bas',()=>expect(suggestStake(15250,5)).toBe(762));
  it('renvoie zéro si aucun montant valide ne peut être calculé',()=>{
    expect(suggestStake(0,5)).toBe(0); expect(suggestStake(20,1)).toBe(0); expect(suggestStake(10000,0)).toBe(0);
  });
});
