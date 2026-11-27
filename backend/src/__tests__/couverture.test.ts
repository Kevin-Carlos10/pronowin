/**
 * Couverture d'une mise (26 novembre 2026) : l'évènement inverse, sa cote,
 * et combien miser dessus pour garantir un gain quel que soit le résultat.
 */
import {
  calculerCouverture, coteDe, libelleSelection, noteRemboursement, remboursable, resultatInverse, seuilAtteint, seuilDe,
  selectionDuPronostic, selectionInverse, type MarcheCote,
} from '../services/couverture';
import { pariBankroll } from '../schemas/entrees';

describe('la sélection d\'un pronostic', () => {
  it('d\'après le marché enregistré par le panneau', () => {
    expect(selectionDuPronostic({ marketName: 'Match Winner', marketValue: 'Away' }))
      .toEqual({ marche: 'resultat', issue: 'Away' });
    expect(selectionDuPronostic({ marketName: 'Double Chance', marketValue: 'Home/Draw' }))
      .toEqual({ marche: 'double_chance', paire: 'HomeDraw' });
    expect(selectionDuPronostic({ marketName: 'Goals Over/Under', marketValue: 'Over 1.5' }))
      .toEqual({ marche: 'buts', plus: true, ligne: 1.5 });
    expect(selectionDuPronostic({ marketName: 'Both Teams Score', marketValue: 'No' }))
      .toEqual({ marche: 'btts', oui: false });
  });

  it('à défaut, d\'après son type', () => {
    expect(selectionDuPronostic({ predictionType: 'win1' })).toEqual({ marche: 'resultat', issue: 'Home' });
    expect(selectionDuPronostic({ predictionType: 'under35' })).toEqual({ marche: 'buts', plus: false, ligne: 3.5 });
    expect(selectionDuPronostic({ predictionType: 'btts' })).toEqual({ marche: 'btts', oui: true });
  });

  it('un marché sans inverse exact n\'est pas couvert : score exact, handicap, quart de ligne', () => {
    expect(selectionDuPronostic({ marketName: 'Exact Score', marketValue: '2:1' })).toBeNull();
    expect(selectionDuPronostic({ marketName: 'Asian Handicap', marketValue: 'Home -1' })).toBeNull();
    // Sur un quart de ligne, la mise est coupée en deux : l'inverse n'est plus exact.
    expect(selectionDuPronostic({ marketName: 'Goals Over/Under', marketValue: 'Over 2.25' })).toBeNull();
    expect(selectionDuPronostic({ predictionType: 'other' })).toBeNull();
  });

  it('ligne entière et « remboursé si match nul » (27 novembre 2026) : couverts, et remboursables ensemble', () => {
    const plus2 = selectionDuPronostic({ marketName: 'Goals Over/Under', marketValue: 'Over 2' })!;
    expect(plus2).toEqual({ marche: 'buts', plus: true, ligne: 2 });
    expect(remboursable(plus2)).toBe(true);
    expect(noteRemboursement(plus2, 'fr')).toBe('S\'il y a exactement 2 buts, les deux mises sont remboursées : ni gain ni perte.');
    const dnb = selectionDuPronostic({ marketName: 'Home/Away', marketValue: 'Home' })!;
    expect(dnb).toEqual({ marche: 'nul_rembourse', issue: 'Home' });
    expect(selectionInverse(dnb)).toEqual({ marche: 'nul_rembourse', issue: 'Away' });
    expect(selectionDuPronostic({ marketName: 'Draw No Bet', marketValue: 'Away' })).toEqual({ marche: 'nul_rembourse', issue: 'Away' });
    expect(remboursable(dnb)).toBe(true);
    expect(remboursable({ marche: 'buts', plus: true, ligne: 2.5 })).toBe(false);
    expect(libelleSelection({ marche: 'nul_rembourse', issue: 'Away' }, 'Arsenal', 'Chelsea', 'fr')).toBe('Chelsea, remboursé si match nul');
    // Les deux écritures de la cote : avant le match et en direct.
    expect(coteDe([{ nom: 'Home/Away', valeurs: [{ valeur: 'Away', cote: 3.1 }] }], { marche: 'nul_rembourse', issue: 'Away' })).toBe(3.1);
    expect(coteDe([{ nom: 'draw no bet', valeurs: [{ valeur: '2', cote: 2.9 }] }], { marche: 'nul_rembourse', issue: 'Away' })).toBe(2.9);
  });

  it('le résultat de l\'inverse suit celui de la sélection couverte', () => {
    expect(resultatInverse('WIN')).toBe('LOSS');
    expect(resultatInverse('LOSS')).toBe('WIN');
    expect(resultatInverse('PUSH')).toBe('PUSH');
    expect(resultatInverse(null)).toBeNull();
  });
});

describe('l\'évènement inverse', () => {
  it('exactement l\'une des deux issues se produit', () => {
    expect(selectionInverse({ marche: 'resultat', issue: 'Home' })).toEqual({ marche: 'double_chance', paire: 'DrawAway' });
    expect(selectionInverse({ marche: 'resultat', issue: 'Draw' })).toEqual({ marche: 'double_chance', paire: 'HomeAway' });
    expect(selectionInverse({ marche: 'double_chance', paire: 'HomeDraw' })).toEqual({ marche: 'resultat', issue: 'Away' });
    expect(selectionInverse({ marche: 'buts', plus: true, ligne: 2.5 })).toEqual({ marche: 'buts', plus: false, ligne: 2.5 });
    expect(selectionInverse({ marche: 'btts', oui: true })).toEqual({ marche: 'btts', oui: false });
  });
});

describe('la cote de l\'inverse', () => {
  const avantMatch: MarcheCote[] = [
    { nom: 'Match Winner', valeurs: [{ valeur: 'Home', cote: 1.8 }, { valeur: 'Draw', cote: 3.6 }, { valeur: 'Away', cote: 4.2 }] },
    { nom: 'Double Chance', valeurs: [{ valeur: 'Home/Draw', cote: 1.2 }, { valeur: 'Draw/Away', cote: 1.95 }] },
    { nom: 'Goals Over/Under', valeurs: [{ valeur: 'Over 2.5', cote: 1.9 }, { valeur: 'Under 2.5', cote: 1.95 }, { valeur: 'Under 3.5', cote: 1.4 }] },
  ];
  const direct: MarcheCote[] = [
    { nom: 'over/under line', valeurs: [{ valeur: 'Over', cote: 1.3, ligne: '2.5' }, { valeur: 'Under', cote: 4.0, ligne: '2.5' }] },
    { nom: 'double chance', valeurs: [{ valeur: 'X2', cote: 2.6 }] },
    { nom: 'both teams to score', valeurs: [{ valeur: 'Yes', cote: 1.5 }, { valeur: 'No', cote: 2.5 }] },
  ];

  it('avant le match (« Under 2.5 ») comme en direct (« Under » et la ligne à part)', () => {
    const moins25 = { marche: 'buts' as const, plus: false, ligne: 2.5 };
    expect(coteDe(avantMatch, moins25)).toBe(1.95);
    expect(coteDe(direct, moins25)).toBe(4.0);
    expect(coteDe(avantMatch, { marche: 'buts', plus: false, ligne: 1.5 })).toBeNull();
  });

  it('double chance sous ses deux écritures ; les deux équipes marquent', () => {
    expect(coteDe(avantMatch, { marche: 'double_chance', paire: 'DrawAway' })).toBe(1.95);
    expect(coteDe(direct, { marche: 'double_chance', paire: 'DrawAway' })).toBe(2.6);
    expect(coteDe(direct, { marche: 'btts', oui: false })).toBe(2.5);
    expect(coteDe(direct, { marche: 'resultat', issue: 'Home' })).toBeNull();
  });
});

describe('le calcul', () => {
  it('1 000 F sur Plus de 2,5 à 2,00 ; Moins de 2,5 monte à 4,00 : 500 F dessus, +500 F garantis', () => {
    expect(calculerCouverture(1000, 2, 4)).toEqual({
      miseCouverture: 500, gainGaranti: 500, gainPotentiel: 1000, part: 0.5, siSelection: 500, siInverse: 500,
    });
  });

  it('récupérer sa mise : 334 F sur l\'inverse (arrondi au-dessus), +666 F si la sélection passe, jamais de perte', () => {
    const c = calculerCouverture(1000, 2, 4, 1, 'mise_remboursee')!;
    expect(c.miseCouverture).toBe(334);                 // 1 000 ÷ 3 = 333,3 → 334
    expect(c.siSelection).toBe(666);
    expect(c.siInverse).toBe(2);
    expect(c.gainGaranti).toBe(2);
    // Même règle que le gain égal : sans gain garanti possible, rien à sauver.
    expect(calculerCouverture(1000, 2, 1.9, 1, 'mise_remboursee')!.siSelection).toBeLessThan(0);
  });

  it('arrondi au franc ; le gain garanti tient compte de l\'arrondi', () => {
    const c = calculerCouverture(1000, 1.85, 3.1)!;
    expect(c.miseCouverture).toBe(597);                // 1 850 ÷ 3,1 = 596,77
    expect(c.gainGaranti).toBe(Math.round(Math.min(1850 - 1000 - 597, 597 * 3.1 - 1000 - 597)));
    expect(Number.isInteger(c.gainGaranti)).toBe(true);
  });

  it('au centime pour l\'euro', () => {
    expect(calculerCouverture(10, 2, 3, 0.01)!.miseCouverture).toBeCloseTo(6.67, 2);
  });

  it('cotes resserrées : aucun gain garanti, pas d\'alerte', () => {
    const c = calculerCouverture(1000, 2, 1.9)!;
    expect(c.gainGaranti).toBeLessThan(0);
    expect(seuilAtteint(c, 30)).toBe(false);
  });

  it('le seuil : la moitié tout juste passe, un peu moins non', () => {
    expect(seuilAtteint(calculerCouverture(1000, 2, 4)!, 50)).toBe(true);
    expect(seuilAtteint(calculerCouverture(1000, 2, 3.9)!, 50)).toBe(false);
    expect(seuilAtteint(calculerCouverture(1000, 2, 3.9)!, 30)).toBe(true);
  });

  it('des entrées absurdes : rien', () => {
    expect(calculerCouverture(0, 2, 3)).toBeNull();
    expect(calculerCouverture(1000, 1, 3)).toBeNull();
    expect(calculerCouverture(1000, 2, 1)).toBeNull();
  });
});

describe('le seuil choisi', () => {
  it('30, 50 ou 70 ; sinon 50', () => {
    expect(seuilDe(null)).toBe(50);
    expect(seuilDe({ seuil_couverture: 70 })).toBe(70);
    expect(seuilDe({ seuil_couverture: 45 })).toBe(50);
    expect(seuilDe({ seuil_couverture: '30' })).toBe(50);
  });
});

describe('les libellés', () => {
  it('avec les équipes, en français et en anglais', () => {
    expect(libelleSelection({ marche: 'double_chance', paire: 'DrawAway' }, 'Arsenal', 'Chelsea', 'fr')).toBe('Nul ou Chelsea');
    expect(libelleSelection({ marche: 'resultat', issue: 'Home' }, 'Arsenal', 'Chelsea', 'en')).toBe('Arsenal to win');
    expect(libelleSelection({ marche: 'buts', plus: false, ligne: 2.5 }, 'A', 'B', 'fr')).toBe('Moins de 2,5 buts');
    expect(libelleSelection({ marche: 'btts', oui: false }, 'A', 'B', 'en')).toBe('Both teams to score: no');
  });
});

describe('la cote obtenue chez le bookmaker', () => {
  it('facultative ; une cote absurde est refusée', () => {
    const base = { pronostic_id: 'p1', staked_amount: 1000 };
    expect(pariBankroll.safeParse(base).success).toBe(true);
    expect(pariBankroll.safeParse({ ...base, cote_obtenue: 2.15 }).success).toBe(true);
    expect(pariBankroll.safeParse({ ...base, cote_obtenue: 0.9 }).success).toBe(false);
    expect(pariBankroll.safeParse({ ...base, cote_obtenue: 5000 }).success).toBe(false);
  });
});
