import { suggestStake } from '../services/bankroll.service';

// suggestStake est une fonction pure : aucun mock nécessaire

describe('suggestStake — logique Kelly simplifiée', () => {
  describe('confidence 5/5 → 5%', () => {
    it('arrondit à la centaine (balance 10 000)', () => {
      expect(suggestStake(10_000, 5)).toBe(500);
    });
    it('minimum 100 XOF si le solde est trop faible', () => {
      expect(suggestStake(1_000, 5)).toBe(100);
    });
    it('arrondit correctement pour un solde irrégulier', () => {
      // 15 250 × 5% = 762.5 → arrondi à 800
      expect(suggestStake(15_250, 5)).toBe(800);
    });
  });

  describe('confidence 4/5 → 3%', () => {
    it('calcul pour 100 000 XOF', () => {
      // 100 000 × 3% = 3 000
      expect(suggestStake(100_000, 4)).toBe(3_000);
    });
  });

  describe('confidence 3/5 → 3%', () => {
    it("même taux qu'en 4/5", () => {
      expect(suggestStake(100_000, 3)).toBe(3_000);
    });
  });

  describe('confidence 1-2/5 → 1.5%', () => {
    it('calcul pour confidence 2', () => {
      // 200 000 × 1.5% = 3 000
      expect(suggestStake(200_000, 2)).toBe(3_000);
    });
    it('calcul pour confidence 1', () => {
      // 10 000 × 1.5% = 150 → arrondi à 200
      expect(suggestStake(10_000, 1)).toBe(200);
    });
    it('minimum 100 XOF si solde trop faible', () => {
      expect(suggestStake(500, 1)).toBe(100);
    });
  });

  describe('cas limites', () => {
    it('solde 0 → renvoie 100 (minimum)', () => {
      expect(suggestStake(0, 5)).toBe(100);
    });
    it('confidence 0 → traité comme 1-2 (1.5%)', () => {
      expect(suggestStake(10_000, 0)).toBe(200);
    });
  });
});
