import { evaluerFiabilite, PROBABILITE_PLANCHER } from '../services/fiabilite_modele';

/**
 * Deux matchs réels, observés à l'écran.
 *
 * Sur Lask Linz – Celtic, le fournisseur donnait 0 % à Lask Linz et plaçait
 * 100 % de l'avantage chez Celtic sur les cinq critères. Lask Linz a gagné 4–1.
 *
 * Ce n'est pas une prédiction fausse, c'est une prédiction absente : des butées
 * numériques présentées comme une évidence. Le service applique déjà la règle à
 * l'axe 0/0 — « pas une égalité, une absence de donnée » — il lui manquait le
 * cas 0/100, qui porte le même vide sous une apparence de certitude.
 */
const axe = (label: string, home: number, away: number) => ({ label, home, away });

const CINQ_AXES_EQUILIBRES = [
  axe('Forme', 64, 36), axe('Attaque', 75, 25), axe('Défense', 40, 60),
  axe('Buts', 75, 25),  axe('Confrontations', 60, 40),
];

describe('sorties inexploitables du modèle externe', () => {
  it('rejette Lask Linz – Celtic : 0 % et cinq axes saturés', () => {
    const v = evaluerFiabilite({
      percentHome: 0, percentDraw: 50, percentAway: 50,
      comparisons: [
        axe('Forme', 0, 100), axe('Attaque', 0, 100), axe('Défense', 0, 100),
        axe('Buts', 0, 100),  axe('Confrontations', 0, 100),
      ],
    });
    expect(v.exploitable).toBe(false);
  });

  it('rejette une issue déclarée quasi impossible', () => {
    const v = evaluerFiabilite({
      percentHome: 1, percentDraw: 30, percentAway: 69,
      comparisons: CINQ_AXES_EQUILIBRES,
    });
    expect(v.exploitable).toBe(false);
    expect(v.raison).toContain('probabilité minimale');
  });

  it('rejette la saturation même quand les probabilités sont crédibles', () => {
    const v = evaluerFiabilite({
      percentHome: 30, percentDraw: 30, percentAway: 40,
      comparisons: [
        axe('Forme', 100, 0), axe('Attaque', 100, 0), axe('Défense', 100, 0),
      ],
    });
    expect(v.exploitable).toBe(false);
    expect(v.raison).toContain('saturés');
  });

  it('rejette une absence totale de probabilités', () => {
    const v = evaluerFiabilite({
      percentHome: 0, percentDraw: 0, percentAway: 0,
      comparisons: CINQ_AXES_EQUILIBRES,
    });
    expect(v.exploitable).toBe(false);
  });

  it('rejette une somme incohérente — réponse tronquée', () => {
    const v = evaluerFiabilite({
      percentHome: 20, percentDraw: 20, percentAway: 20,
      comparisons: CINQ_AXES_EQUILIBRES,
    });
    expect(v.exploitable).toBe(false);
    expect(v.raison).toContain('somme');
  });
});

describe('sorties légitimes — le contrôle ne doit pas les emporter', () => {
  it('accepte Bodo/Glimt – NEC : 45/45/10, axes contrastés', () => {
    const v = evaluerFiabilite({
      percentHome: 45, percentDraw: 45, percentAway: 10,
      comparisons: [
        axe('Forme', 64, 36), axe('Attaque', 75, 25), axe('Défense', 40, 60),
        axe('Buts', 75, 25),  axe('Confrontations', 100, 0),
      ],
    });
    expect(v.exploitable).toBe(true);
  });

  // Un seul axe à 100/0 reste plausible : une équipe peut avoir gagné toutes
  // ses confrontations. Ce sont les cinq à la fois qui trahissent la butée.
  it('accepte un axe unique saturé', () => {
    const v = evaluerFiabilite({
      percentHome: 55, percentDraw: 25, percentAway: 20,
      comparisons: [axe('Forme', 55, 45), axe('Confrontations', 100, 0)],
    });
    expect(v.exploitable).toBe(true);
  });

  it('accepte une favorite très nette tant qu\'aucune issue n\'est niée', () => {
    const v = evaluerFiabilite({
      percentHome: 78, percentDraw: 15, percentAway: 7,
      comparisons: CINQ_AXES_EQUILIBRES,
    });
    expect(v.exploitable).toBe(true);
  });

  it('accepte le seuil exact du plancher', () => {
    const v = evaluerFiabilite({
      percentHome: PROBABILITE_PLANCHER, percentDraw: 28, percentAway: 70,
      comparisons: CINQ_AXES_EQUILIBRES,
    });
    expect(v.exploitable).toBe(true);
  });

  // Sans axes, seules les probabilités décident : ne pas rejeter par défaut.
  it('accepte des probabilités saines sans aucun axe', () => {
    const v = evaluerFiabilite({
      percentHome: 40, percentDraw: 30, percentAway: 30, comparisons: [],
    });
    expect(v.exploitable).toBe(true);
  });
});
