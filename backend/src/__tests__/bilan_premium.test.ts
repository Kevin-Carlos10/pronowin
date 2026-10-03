/**
 * Le mur Premium annonçait « +68 % de réussite sur les 30 derniers jours ».
 * Nombre écrit en dur : exact seulement par accident, sur l'écran qui demande
 * de payer, et contredit par l'article 6 des CGU.
 *
 * Deux règles remplacent cette constante, et aucune n'est visible d'un test de
 * type : l'écran se charge parfaitement dans les deux cas.
 */

const ECHANTILLON_MINIMAL = 10;

/**
 * Reproduit exactement le calcul de `getBilanPremium`. Le contrôleur lui-même
 * n'est pas appelable sans base ni serveur ; ce qui doit être verrouillé, c'est
 * l'arithmétique et le seuil.
 */
function bilan(gagnes: number, perdus: number, jours = 30) {
  const tranches = gagnes + perdus;
  return {
    periode_jours:         jours,
    pronostics_tranches:   tranches,
    gagnes,
    perdus,
    taux_reussite:         tranches > 0 ? Math.round((gagnes / tranches) * 100) : null,
    echantillon_minimal:   ECHANTILLON_MINIMAL,
    echantillon_suffisant: tranches >= ECHANTILLON_MINIMAL,
  };
}

describe('bilan Premium', () => {
  describe('le taux n\'existe qu\'avec un dénominateur', () => {
    it('sans aucun pronostic tranché, le taux est null — pas zéro', () => {
      // Même règle que la carte Compte : 0 % mesuré et 0 % inconnu sont deux
      // choses différentes, et l'une des deux accuse à tort.
      expect(bilan(0, 0).taux_reussite).toBeNull();
    });

    it('un taux réellement nul reste zéro', () => {
      expect(bilan(0, 12).taux_reussite).toBe(0);
    });

    it('calcule le pourcentage sur les seuls paris tranchés', () => {
      expect(bilan(7, 3).taux_reussite).toBe(70);
      expect(bilan(2, 1).taux_reussite).toBe(67);
    });
  });

  describe('un petit échantillon n\'est pas une performance', () => {
    it('trois pronostics gagnés ne valent pas « 100 % de réussite »', () => {
      const b = bilan(3, 0);
      expect(b.taux_reussite).toBe(100);
      // Le taux est calculé, mais le drapeau interdit de l'annoncer : sur trois
      // paris, 100 % est un artefact. C'est précisément la promesse que le
      // « +68 % » codé en dur faisait sans jamais rien mesurer.
      expect(b.echantillon_suffisant).toBe(false);
    });

    it('le seuil est franchi à dix paris tranchés', () => {
      expect(bilan(5, 4).echantillon_suffisant).toBe(false);
      expect(bilan(5, 5).echantillon_suffisant).toBe(true);
    });

    it('un échantillon vide n\'est jamais suffisant', () => {
      expect(bilan(0, 0).echantillon_suffisant).toBe(false);
    });
  });

  describe('le seuil est exposé, pas caché', () => {
    it('la réponse porte le minimum exigé', () => {
      // L'appelant peut ainsi expliquer pourquoi il ne montre rien, au lieu de
      // disparaître sans raison.
      expect(bilan(2, 1).echantillon_minimal).toBe(ECHANTILLON_MINIMAL);
    });

    it('le détail gagnés/perdus accompagne toujours le taux', () => {
      // Un pourcentage seul n'est pas vérifiable ; avec 7 et 3 en face, il l'est.
      const b = bilan(7, 3);
      expect(b.gagnes).toBe(7);
      expect(b.perdus).toBe(3);
      expect(b.pronostics_tranches).toBe(10);
    });
  });
});
