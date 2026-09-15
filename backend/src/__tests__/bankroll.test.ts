import { suggestStake } from '../services/bankroll.service';

/**
 * La mise suggérée, vue depuis le service.
 *
 * ── Trois attentes ont changé, et il faut le dire ──────────────────────────
 *
 * Ce banc figeait un plancher de 100 appliqué **sans regarder le solde** :
 *
 *     it('minimum 100 XOF si le solde est trop faible', () => {
 *       expect(suggestStake(1_000, 5)).toBe(100);   // 5 % de 1 000 = 50
 *     });
 *     it('minimum 100 XOF si solde trop faible', () => {
 *       expect(suggestStake(500, 1)).toBe(100);     // 1,5 % de 500 = 7,5
 *     });
 *     it('solde 0 → renvoie 100 (minimum)', () => {
 *       expect(suggestStake(0, 5)).toBe(100);       // sur une banque vide
 *     });
 *
 * Le dernier conseillait de miser 100 à qui ne possède rien ; l'avant-dernier
 * proposait 20 % du capital sur la **plus faible** note de confiance. Ces trois
 * lignes tenaient le défaut en place : tant qu'elles passaient, le corriger
 * faisait tomber le banc.
 *
 * Elles sont donc récrites, pas supprimées — et l'ancienne valeur reste écrite
 * ci-dessus, pour que la personne qui relira sache ce qui a été échangé.
 *
 * Le détail du calcul et ses contreparties sont dans `mise_suggeree.test.ts`.
 */
describe('suggestStake — une part du capital selon la confiance', () => {
  describe('confiance 5/5 → 5 %', () => {
    it('arrondit à la centaine (solde 10 000)', () => {
      expect(suggestStake(10_000, 5)).toBe(500);
    });

    it('reste proportionnel sur un petit solde', () => {
      // Était : 100, soit le double de la part annoncée.
      expect(suggestStake(1_000, 5)).toBe(50);
    });

    it('arrondit correctement pour un solde irrégulier', () => {
      // 15 250 × 5 % = 762,5 → arrondi à 800
      expect(suggestStake(15_250, 5)).toBe(800);
    });
  });

  describe('confiance 4/5 → 3 %', () => {
    it('calcul pour 100 000 XOF', () => {
      expect(suggestStake(100_000, 4)).toBe(3_000);
    });
  });

  describe('confiance 3/5 → 3 %', () => {
    it("même taux qu'en 4/5", () => {
      expect(suggestStake(100_000, 3)).toBe(3_000);
    });
  });

  describe('confiance 1-2/5 → 1,5 %', () => {
    it('calcul pour confiance 2', () => {
      expect(suggestStake(200_000, 2)).toBe(3_000);
    });

    it('calcul pour confiance 1', () => {
      // 10 000 × 1,5 % = 150 → arrondi à 200
      expect(suggestStake(10_000, 1)).toBe(200);
    });

    it('reste proportionnel sur un petit solde', () => {
      // Était : 100, soit 20 % du capital — sur la plus faible confiance.
      expect(suggestStake(500, 1)).toBe(8);
    });
  });

  describe('cas limites', () => {
    it('solde 0 → rien à suggérer', () => {
      // Était : 100. Conseiller une mise à qui n'a rien n'est pas un conseil.
      expect(suggestStake(0, 5)).toBe(0);
    });

    it('confiance 0 → traitée comme 1-2 (1,5 %)', () => {
      expect(suggestStake(10_000, 0)).toBe(200);
    });

    it('ne dépasse jamais le solde, quelle que soit la note', () => {
      for (const note of [0, 1, 2, 3, 4, 5, 60]) {
        expect(suggestStake(50, note)).toBeLessThanOrEqual(50);
      }
    });
  });
});
