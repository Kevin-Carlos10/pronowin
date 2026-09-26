import {
  extraireLigne, libelleSansLigne, marcheLisible, traduireMarche,
} from '../services/cotes_live';

/**
 * L'écran affichait « Over 7.50 » sur le marché « Match Goals ».
 *
 * 7,50 est la **cote**, pas le seuil. Le flux `/odds/live` ne met pas le seuil
 * dans le libellé — contrairement au flux pré-match, pour lequel l'analyseur
 * avait été écrit — et il était donc perdu. Trois lignes Over/Under
 * (1,5 · 2,5 · 3,5) apparaissaient comme trois rangées interchangeables.
 *
 * Le pire n'est pas l'information manquante, c'est qu'elle se lise à l'envers.
 */
describe('seuil d\'une cote', () => {
  it('le lit dans le champ dédié', () => {
    expect(extraireLigne({ value: 'Over', odd: '1.90', handicap: '2.5' })).toBe('2.5');
  });

  // Le nom du champ n'est pas vérifiable hors production : on essaie les
  // porteurs connus plutôt que de parier sur un seul.
  it('accepte les autres porteurs connus', () => {
    expect(extraireLigne({ value: 'Over', line:  '3.5' })).toBe('3.5');
    expect(extraireLigne({ value: 'Over', total: '1.5' })).toBe('1.5');
  });

  it('accepte un seuil négatif de handicap', () => {
    expect(extraireLigne({ value: 'Home', handicap: '-0.5' })).toBe('-0.5');
  });

  it('normalise la virgule décimale', () => {
    expect(extraireLigne({ value: 'Over', handicap: '2,5' })).toBe('2.5');
  });

  it('le retrouve dans le libellé quand l\'API l\'y met', () => {
    expect(extraireLigne({ value: 'Over 2.5', odd: '1.90' })).toBe('2.5');
  });

  it('renonce plutôt que de deviner', () => {
    expect(extraireLigne({ value: 'Over', odd: '1.90' })).toBeUndefined();
    expect(extraireLigne({ value: 'Home', odd: '1.45' })).toBeUndefined();
  });

  // Un champ présent mais non numérique ne prouve rien.
  it('ignore un porteur non numérique', () => {
    expect(extraireLigne({ value: 'Yes', handicap: 'main' })).toBeUndefined();
  });
});

describe('libellé dépouillé de son seuil', () => {
  it('retire le seuil quand il y est', () => {
    expect(libelleSansLigne('Over 2.5')).toBe('Over');
    expect(libelleSansLigne('Home -0.5')).toBe('Home');
  });

  it('laisse intact un libellé sans seuil', () => {
    expect(libelleSansLigne('Over')).toBe('Over');
    expect(libelleSansLigne('Yes')).toBe('Yes');
  });

  // « Score exact 2-1 » ne doit pas perdre son 1.
  it('ne vide jamais un libellé entièrement numérique', () => {
    expect(libelleSansLigne('2.5')).toBe('2.5');
  });
});

describe('un marché ne doit pas pouvoir se lire à l\'envers', () => {
  const v = (value: string, odd: number, ligne?: string) => ({ value, odd, ligne });

  it('accepte un marché sans seuil qui n\'en a pas besoin', () => {
    expect(marcheLisible([v('Home', 1.45), v('Draw', 3.2), v('Away', 2.67)])).toBe(true);
    expect(marcheLisible([v('Yes', 1.7), v('No', 2.0)])).toBe(true);
  });

  it('accepte un Over/Under qui porte ses seuils', () => {
    expect(marcheLisible([v('Over', 1.9, '2.5'), v('Under', 1.9, '2.5')])).toBe(true);
  });

  // Le défaut d'origine, exactement.
  it('refuse un Over sans seuil', () => {
    expect(marcheLisible([v('Over', 7.5), v('Under', 1.07)])).toBe(false);
  });

  it('refuse des libellés répétés sans seuil pour les distinguer', () => {
    // Trois lignes de handicap, rien pour dire laquelle est laquelle.
    expect(marcheLisible([
      v('Home', 1.45), v('Away', 2.67),
      v('Home', 2.67), v('Away', 1.45),
      v('Home', 1.95), v('Away', 1.85),
    ])).toBe(false);
  });

  it('accepte ces mêmes répétitions dès qu\'elles portent leur seuil', () => {
    expect(marcheLisible([
      v('Home', 1.45, '-0.5'), v('Away', 2.67, '-0.5'),
      v('Home', 2.67, '+0.5'), v('Away', 1.45, '+0.5'),
    ])).toBe(true);
  });

  it('refuse dès qu\'une seule répétition manque son seuil', () => {
    expect(marcheLisible([
      v('Home', 1.45, '-0.5'), v('Away', 2.67, '-0.5'),
      v('Home', 2.67),
    ])).toBe(false);
  });
});

/**
 * Reproduction de la capture qui a révélé le défaut, telle quelle.
 *
 * Trois marchés à seuil sans seuil, et un marché qui n'en a pas besoin. Seul
 * le dernier doit survivre au filtre.
 */
describe('l\'écran de la capture, rejoué', () => {
  /** Le traitement appliqué par le service, isolé pour être testable. */
  const traiter = (m: { name: string; values: any[] }) => {
    const values = m.values.map((v: any) => {
      const ligne = extraireLigne(v);
      return {
        value: libelleSansLigne(String(v.value)),
        odd:   parseFloat(v.odd),
        ...(ligne ? { ligne } : {}),
      };
    });
    return { nom: traduireMarche(m.name), values, affiche: marcheLisible(values) };
  };

  it('masque les trois marchés dont le seuil manque', () => {
    const cas = [
      { name: 'Over/Under Line', values: [
          { value: 'Over', odd: '2.15' }, { value: 'Under', odd: '1.68' },
          { value: 'Over', odd: '1.90' }, { value: 'Under', odd: '1.90' },
          { value: 'Over', odd: '1.48' }, { value: 'Under', odd: '2.60' }] },
      { name: 'Asian Handicap', values: [
          { value: 'Home', odd: '1.45' }, { value: 'Away', odd: '2.67' },
          { value: 'Home', odd: '2.67' }, { value: 'Away', odd: '1.45' }] },
      // Le pire : « Over 7.50 » se lisait comme « plus de 7,5 buts ».
      { name: 'Match Goals', values: [
          { value: 'Over', odd: '7.50' }, { value: 'Under', odd: '1.07' }] },
    ];
    for (const m of cas) expect(traiter(m).affiche).toBe(false);
  });

  it('conserve un marché qui se lit sans seuil', () => {
    const r = traiter({ name: 'Match Winner', values: [
      { value: 'Home', odd: '1.30' },
      { value: 'Draw', odd: '5.00' },
      { value: 'Away', odd: '9.00' }] });
    expect(r.affiche).toBe(true);
    expect(r.nom).toBe('Vainqueur du match');
  });

  it('conserve un Over/Under dès que l\'API fournit le seuil', () => {
    const r = traiter({ name: 'Over/Under Line', values: [
      { value: 'Over',  odd: '1.90', handicap: '2.5' },
      { value: 'Under', odd: '1.90', handicap: '2.5' }] });
    expect(r.affiche).toBe(true);
    expect(r.nom).toBe('Plus / Moins de buts');
    expect(r.values[0]).toEqual({ value: 'Over', odd: 1.9, ligne: '2.5' });
  });
});

describe('noms de marchés', () => {
  it('traduit ceux qu\'il connaît', () => {
    expect(traduireMarche('Over/Under Line')).toBe('Plus / Moins de buts');
    expect(traduireMarche('Asian Handicap')).toBe('Handicap asiatique');
    expect(traduireMarche('Match Goals')).toBe('Total de buts');
  });

  it('ignore la casse et les espaces', () => {
    expect(traduireMarche('  MATCH WINNER  ')).toBe('Vainqueur du match');
  });

  // Même règle que pour les recommandations : un nom inconnu passe tel quel et
  // se signale, plutôt que d'être traduit au jugé.
  it('rend intact un marché inconnu', () => {
    expect(traduireMarche('Player Shots On Target')).toBe('Player Shots On Target');
  });
});
