/**
 * Les marchés 1xBet hors de l'API de cotes (phase 1 : réglés par le score).
 *
 * Ce moteur crédite et débite des bankrolls : chaque marché est vérifié sur
 * des scores précis, dans les deux sens (« Oui » et « Non »).
 */
import { _resolvePronosticResult, type ScoreLine } from '../services/settlement';
import { catalog, prediction, selection } from '../i18n/football';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { MARCHES, LIGNES, encoder, regler } = require('../marches/complementaires');

const s = (home: number, away: number): ScoreLine => ({ home, away });
// Aston Villa – Brentford : 1-0 à la pause, 2-2 à la fin (2e mi-temps 1-2).
const FT = s(2, 2), FH = s(1, 0);
const r = (nom: string, valeur: string, ft = FT, fh: ScoreLine | null = FH) => regler(nom, valeur, ft, fh);

describe('gagner, faire nul, marquer par mi-temps', () => {
  it('gagne au moins une mi-temps', () => {
    expect(r('To Win Either Half', 'Home / Yes')).toBe('WIN');   // 1re MT 1-0
    expect(r('To Win Either Half', 'Away / Yes')).toBe('WIN');   // 2e MT 1-2
    expect(r('To Win Either Half', 'Home / No')).toBe('LOSS');
    expect(r('To Win Either Half', 'Away / Yes', s(1, 1), s(0, 0))).toBe('LOSS'); // 0-0 puis 1-1
  });

  it('nul dans au moins une mi-temps', () => {
    expect(r('Draw In Either Half', 'Yes')).toBe('LOSS');        // 1-0 puis 1-2
    expect(r('Draw In Either Half', 'No')).toBe('WIN');
    expect(r('Draw In Either Half', 'Yes', s(1, 0), s(0, 0))).toBe('WIN');
  });

  it('but dans chaque mi-temps, et une équipe qui marque dans les deux', () => {
    expect(r('Goal In Both Halves', 'Yes')).toBe('WIN');
    expect(r('Goal In Both Halves', 'Yes', s(2, 0), s(2, 0))).toBe('LOSS');
    expect(r('To Score In Both Halves', 'Home / Yes')).toBe('WIN');  // 1 + 1
    expect(r('To Score In Both Halves', 'Away / Yes')).toBe('LOSS'); // 0 puis 2
    expect(r('To Score In Both Halves', 'Away / No')).toBe('WIN');
  });

  it('sans le score de la mi-temps, rien n\'est décidé', () => {
    for (const nom of ['To Win Either Half', 'Draw In Either Half', 'Goal In Both Halves']) {
      const valeur = nom === 'To Win Either Half' ? 'Home / Yes' : 'Yes';
      expect(r(nom, valeur, FT, null)).toBeNull();
    }
  });
});

describe('les combinés : « Oui / Non » porte sur la combinaison entière', () => {
  it('résultat + les deux équipes marquent', () => {
    expect(r('Result/Both Teams Score', 'Draw / Yes')).toBe('WIN');
    expect(r('Result/Both Teams Score', 'Home / Yes')).toBe('LOSS');
    // « V1 et les deux marquent – Non » : gagné dès que l'un des deux manque.
    expect(r('Result/Both Teams Score', 'Home / No')).toBe('WIN');
    expect(r('Result/Both Teams Score', 'Home / No', s(2, 1))).toBe('LOSS');
  });

  it('double chance + les deux équipes marquent', () => {
    expect(r('Double Chance/Both Teams Score', '1X / Yes')).toBe('WIN');
    expect(r('Double Chance/Both Teams Score', '12 / Yes')).toBe('LOSS');
    expect(r('Double Chance/Both Teams Score', 'X2 / No', s(0, 1))).toBe('WIN');
  });

  it('les deux équipes marquent + total', () => {
    expect(r('Both Teams Score/Total', 'Over 2.5 / Yes')).toBe('WIN');
    expect(r('Both Teams Score/Total', 'Over 2.5 / Yes', s(3, 0))).toBe('LOSS');
  });

  it('mi-temps/fin + total', () => {
    expect(r('HT/FT/Total', 'Home / Draw / Over 3.5 / Yes')).toBe('WIN');
    expect(r('HT/FT/Total', 'Home / Home / Over 3.5 / Yes')).toBe('LOSS');
    expect(r('HT/FT/Total', 'Home / Home / Over 3.5 / No')).toBe('WIN');
  });

  it('double chance + total d\'une équipe', () => {
    // « 1X Et Plus de (0.5) » sur Aston Villa : nul, et Villa a marqué.
    expect(r('Double Chance/Team Total', '1X / Home / Over 0.5 / Yes')).toBe('WIN');
    expect(r('Double Chance/Team Total', '1X / Home / Over 2.5 / Yes')).toBe('LOSS');
    expect(r('Double Chance/Team Total', '1X / Home / Under 1.5 / No')).toBe('WIN');
  });

  it('au moins une équipe ne marque pas + total', () => {
    expect(r('At Least One Team Not To Score/Total', 'Over 1.5 / Yes', s(2, 0))).toBe('WIN');
    expect(r('At Least One Team Not To Score/Total', 'Over 1.5 / Yes')).toBe('LOSS');
  });
});

describe('gagner sans encaisser, au moins une équipe qui marque', () => {
  it('gagne sans encaisser', () => {
    expect(r('To Win To Nil', 'Home / Yes', s(2, 0))).toBe('WIN');
    expect(r('To Win To Nil', 'Home / Yes', s(2, 1))).toBe('LOSS');
    expect(r('Either Team To Win To Nil', 'Yes', s(0, 1))).toBe('WIN');
    expect(r('Either Team To Win To Nil', 'Yes', s(0, 0))).toBe('LOSS');  // un nul n'est pas une victoire
    expect(r('Either Team To Win To Nil', 'No')).toBe('WIN');
  });

  it('au moins une équipe marque plus de n', () => {
    // 1xBet : « Plus de (1.5) – Oui » à 1,45 : une équipe au moins à 2 buts.
    expect(r('At Least One Team To Score', 'Over 1.5 / Yes')).toBe('WIN');
    expect(r('At Least One Team To Score', 'Over 2.5 / Yes')).toBe('LOSS');
    expect(r('At Least One Team To Score', 'Over 2.5 / No')).toBe('WIN');
  });
});

describe('handicap européen', () => {
  it('le handicap de l\'équipe choisie ; pour le nul, celui de l\'équipe 1', () => {
    const ft = s(2, 1);
    expect(regler('European Handicap', 'Home / -1', ft, null)).toBe('LOSS');     // 1-1
    expect(regler('European Handicap', 'Draw / -1', ft, null)).toBe('WIN');
    expect(regler('European Handicap', 'Away / +1', ft, null)).toBe('LOSS');     // 2-2 : nul
    expect(regler('European Handicap', 'Away / +2', ft, null)).toBe('WIN');      // 2-3
    expect(regler('European Handicap', 'Home / +1', s(0, 0), null)).toBe('WIN');
  });

  it('une valeur mal formée reste à régler à la main', () => {
    expect(regler('European Handicap', 'Home / 1', s(2, 1), null)).toBeNull();
    expect(regler('European Handicap', 'Home / 0', s(2, 1), null)).toBeNull();
    expect(regler('European Handicap', 'Draw', s(2, 1), null)).toBeNull();
  });
});

describe("un marché de l'API ajouté au règlement", () => {
  it('gagne les deux mi-temps (Albanie 2-1 Saint-Marin, 1-0 puis 1-1 : perdu)', () => {
    const marche = (v: string, ft: ScoreLine, fh: ScoreLine | null) =>
      _resolvePronosticResult({ predictionType: 'other', marketName: 'Win Both Halves', marketValue: v }, ft, fh);
    expect(marche('Home', s(2, 1), s(1, 0))).toBe('LOSS');
    expect(marche('Home', s(3, 0), s(1, 0))).toBe('WIN');
    expect(marche('Away', s(0, 2), s(0, 1))).toBe('WIN');
    expect(marche('Home', s(3, 0), null)).toBeNull();
  });
});

describe('valeurs illisibles et marchés inconnus', () => {
  it('ne règlent rien plutôt que de deviner', () => {
    expect(r('To Win Either Half', 'Home')).toBeNull();
    expect(r('To Win Either Half', 'Team 1 / Yes')).toBeNull();
    expect(r('Both Teams Score/Total', 'Over 2 / Yes')).toBeNull();      // ligne entière : pas de x,5
    expect(r('At Least One Team To Score', 'Under 1.5 / Yes')).toBeNull();
    expect(r('Marché inventé', 'Yes')).toBeNull();
  });
});

describe('le panneau et le moteur parlent la même langue', () => {
  // Les choix de chaque option, tels que le panneau les propose.
  const exemples: Record<string, unknown> = {
    equipe: 'Away', issue: 'Draw', issueMt: 'Home', double: 'X2', ouiNon: 'No',
    total: 'Under 2.5', auMoins: 'Over 0.5', handicap: -2,
  };

  it('chaque valeur construite par le panneau est réglée par le moteur', () => {
    // Phase 1 seulement : la phase 2 a besoin des données du match
    // (marches_donnees_match.test.ts).
    for (const m of (MARCHES as { nom: string; options: string[]; donnees?: string }[]).filter(x => !x.donnees)) {
      const choix = Object.fromEntries(m.options.map(o => [o, exemples[o]]));
      const valeur = encoder(m.nom, choix);
      expect(valeur).not.toBeNull();
      expect(regler(m.nom, valeur, s(1, 2), s(1, 0))).not.toBeNull();
    }
  });

  it('un choix incomplet ne produit aucune valeur', () => {
    expect(encoder('To Win Either Half', { equipe: 'Home' })).toBeNull();
    expect(encoder('European Handicap', { issue: 'Home', handicap: 0 })).toBeNull();
    expect(encoder('Both Teams Score/Total', { total: 'Over 7.5', ouiNon: 'Yes' })).toBeNull();
    expect(LIGNES).toContain(2.5);
  });

  it('le pronostic « autre marché » passe par ce moteur', () => {
    expect(_resolvePronosticResult(
      { predictionType: 'other', marketName: 'To Win Either Half', marketValue: 'Away / Yes' }, FT, FH,
    )).toBe('WIN');
  });

  it('chaque marché a son nom français et anglais, et ses libellés se traduisent', () => {
    const noms = new Set((catalog.markets as { en: string }[]).map(x => x.en));
    for (const m of MARCHES as { nom: string }[]) expect(noms.has(m.nom)).toBe(true);
    // Le libellé public que le panneau compose : « Marché : sélection ».
    const fr = 'Gagne au moins une mi-temps : ' + selection('Home / Yes', 'fr', 'Aston Villa', 'Brentford').text;
    expect(fr).toBe('Gagne au moins une mi-temps : Aston Villa / Oui');
    expect(prediction(fr, 'en', 'Aston Villa', 'Brentford'))
      .toEqual({ text: 'To Win Either Half : Aston Villa / Yes', known: true });
    const handicap = 'Handicap européen : ' + selection(encoder('European Handicap', { issue: 'Draw', handicap: -1 }), 'fr').text;
    expect(handicap).toBe('Handicap européen : Nul / -1');
    expect(prediction(handicap, 'en').text).toBe('European Handicap : Draw / -1');
    expect(prediction('Handicap européen : Brentford / +1', 'en', 'Aston Villa', 'Brentford'))
      .toEqual({ text: 'European Handicap : Brentford / +1', known: true });
  });
});
