/**
 * Le mur Premium annonçait « +68 % de réussite sur les 30 derniers jours ».
 * Nombre écrit en dur : exact seulement par accident, sur l'écran qui demande
 * de payer, et contredit par l'article 6 des CGU.
 *
 * Le bilan réel le remplace, sous deux garde-fous qu'aucun test de type ne
 * voit : l'écran se charge parfaitement que le chiffre soit publié ou non.
 */
import {
  calculerBilanPremium,
  ECHANTILLON_MINIMAL,
  SEUIL_ANNONCE,
} from '../services/bilan_premium';

const bilan = (gagnes: number, perdus: number, jours = 30) =>
  calculerBilanPremium(gagnes, perdus, jours);

describe('bilan Premium', () => {
  describe('un bilan sous 80 % ne s\'affiche pas', () => {
    it('le seuil d\'annonce est 80 %', () => {
      expect(SEUIL_ANNONCE).toBe(80);
    });

    it('à 80 % tout juste, le taux est publié', () => {
      const b = bilan(8, 2);
      expect(b.affichable).toBe(true);
      expect(b.taux_reussite).toBe(80);
    });

    it('au-dessus, aussi', () => {
      expect(bilan(17, 3).taux_reussite).toBe(85);
    });

    it('sous 80 %, le taux n\'est pas publié', () => {
      const b = bilan(7, 3);
      expect(b.affichable).toBe(false);
      // Nul, et pas seulement signalé : les versions de l'application déjà
      // installées et la vitrine affichent tout taux non nul accompagné d'un
      // échantillon suffisant.
      expect(b.taux_reussite).toBeNull();
      expect(b.echantillon_suffisant).toBe(true);
    });

    it('79,6 % ne passe pas pour 80 % en s\'arrondissant', () => {
      // 39 sur 49 = 79,59 % : l'arrondi afficherait « 80 % ».
      const b = bilan(39, 10);
      expect(b.affichable).toBe(false);
      expect(b.taux_reussite).toBeNull();
    });

    it('un taux nul n\'est évidemment pas annoncé', () => {
      expect(bilan(0, 12).taux_reussite).toBeNull();
    });
  });

  describe('un petit échantillon n\'est pas une performance', () => {
    it('trois pronostics gagnés ne valent pas « 100 % de réussite »', () => {
      const b = bilan(3, 0);
      expect(b.echantillon_suffisant).toBe(false);
      expect(b.affichable).toBe(false);
      expect(b.taux_reussite).toBeNull();
    });

    it('le seuil est franchi à dix paris tranchés', () => {
      expect(ECHANTILLON_MINIMAL).toBe(10);
      expect(bilan(9, 0).echantillon_suffisant).toBe(false);
      expect(bilan(9, 1).echantillon_suffisant).toBe(true);
      expect(bilan(9, 1).affichable).toBe(true);
    });

    it('sans aucun pronostic tranché, rien n\'est publié', () => {
      const b = bilan(0, 0);
      expect(b.echantillon_suffisant).toBe(false);
      expect(b.taux_reussite).toBeNull();
    });
  });

  describe('les seuils sont exposés, pas cachés', () => {
    it('la réponse porte le minimum d\'échantillon et le seuil d\'annonce', () => {
      const b = bilan(2, 1);
      expect(b.echantillon_minimal).toBe(ECHANTILLON_MINIMAL);
      expect(b.seuil_annonce).toBe(SEUIL_ANNONCE);
    });

    it('le détail gagnés/perdus accompagne toujours le taux', () => {
      // Un pourcentage seul n'est pas vérifiable ; avec 8 et 2 en face, il l'est.
      const b = bilan(8, 2);
      expect(b.gagnes).toBe(8);
      expect(b.perdus).toBe(2);
      expect(b.pronostics_tranches).toBe(10);
      expect(b.periode_jours).toBe(30);
    });
  });
});
