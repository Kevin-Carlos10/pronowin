import { probabilitesDepuisCotes } from '../services/probabilites_cotes';

/**
 * Le cas qui a motivé ce module : Lask Linz – Celtic.
 *
 * Le modèle externe donnait Lask Linz sous 1 %. Les cotes affichées dans
 * l'onglet voisin le donnaient favori à 48,5 %. Lask Linz a gagné 4–1.
 */
describe('probabilités déduites des cotes', () => {
  it('reproduit Lask Linz – Celtic', () => {
    const p = probabilitesDepuisCotes(2.01, 4.07, 3.54);
    expect(p).not.toBeNull();
    expect(p!.home).toBeCloseTo(48.5, 1);
    expect(p!.draw).toBeCloseTo(24.0, 1);
    expect(p!.away).toBeCloseTo(27.5, 1);
    expect(p!.margePct).toBeCloseTo(2.6, 1);
  });

  it('la somme fait 100 — la marge est bien retirée', () => {
    for (const cotes of [[2.01, 4.07, 3.54], [1.30, 5.5, 9.0], [2.9, 3.2, 2.6]]) {
      const p = probabilitesDepuisCotes(cotes[0], cotes[1], cotes[2])!;
      expect(p.home + p.draw + p.away).toBeCloseTo(100, 0);
    }
  });

  it('la cote la plus basse donne la probabilité la plus haute', () => {
    const p = probabilitesDepuisCotes(1.30, 5.5, 9.0)!;
    expect(p.home).toBeGreaterThan(p.draw);
    expect(p.draw).toBeGreaterThan(p.away);
  });

  it('mesure la marge du bookmaker', () => {
    // 1/2 + 1/4 + 1/4 = 1 exactement → marge nulle.
    expect(probabilitesDepuisCotes(2, 4, 4)!.margePct).toBeCloseTo(0, 1);
    // Cotes plus serrées → marge visible.
    expect(probabilitesDepuisCotes(1.9, 3.8, 3.8)!.margePct).toBeGreaterThan(4);
  });
});

describe('ce que le module refuse de convertir', () => {
  it('une cote absente', () => {
    expect(probabilitesDepuisCotes(2.01, null, 3.54)).toBeNull();
    expect(probabilitesDepuisCotes(undefined, 4.07, 3.54)).toBeNull();
  });

  // `oddsHome` vaut 0 par défaut en base : c'est le cas le plus fréquent.
  it('une cote à zéro — la valeur par défaut du schéma', () => {
    expect(probabilitesDepuisCotes(0, 0, 0)).toBeNull();
    expect(probabilitesDepuisCotes(2.01, 0, 3.54)).toBeNull();
  });

  it('une cote à 1,00 — un pari qui ne rapporte rien', () => {
    expect(probabilitesDepuisCotes(1, 4.07, 3.54)).toBeNull();
  });

  it('une cote négative ou non finie', () => {
    expect(probabilitesDepuisCotes(-2, 4, 3)).toBeNull();
    expect(probabilitesDepuisCotes(NaN, 4, 3)).toBeNull();
    expect(probabilitesDepuisCotes(Infinity, 4, 3)).toBeNull();
  });

  // Somme des inverses < 1 : le triplet offrirait un gain garanti. C'est une
  // donnée corrompue, pas une opportunité.
  it('un triplet qui permettrait un gain garanti', () => {
    expect(probabilitesDepuisCotes(5, 5, 5)).toBeNull();
  });

  it('une marge démesurée — cotes obsolètes ou marché suspendu', () => {
    expect(probabilitesDepuisCotes(1.5, 2.5, 2.5)).toBeNull();
  });

  it('accepte une marge élevée mais plausible', () => {
    // ~11 %, courant sur une petite compétition.
    expect(probabilitesDepuisCotes(2.5, 3.1, 2.55)).not.toBeNull();
  });
});
