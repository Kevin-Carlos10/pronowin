/**
 * L'explication de l'analyse, version iPhone : aucune cote, aucun bookmaker
 * (13 octobre 2026). Apple a refusé l'app tant qu'elle montrait des cotes ;
 * les notes d'examen affirment qu'il n'y en a plus nulle part. Une phrase
 * oubliée dans le texte de l'analyse suffirait à les démentir.
 */
import { explainPrediction, explicationSansCotes } from '../services/ai_prediction.service';

const base = {
  homeTeam: 'Galatasaray', awayTeam: 'Barcelona', predictionType: 'win2',
  probability: 71, oddsRecommended: 1.34,
};

const variantes = {
  'forme connue, modèle externe': explainPrediction({ ...base, homeFormPoints: 0, awayFormPoints: 3, modelPercent: 50 }),
  'aucune forme':                 explainPrediction({ ...base, homeFormPoints: 0, awayFormPoints: 0 }),
  'marché sans lien avec la forme': explainPrediction({ ...base, predictionType: 'over25', homeFormPoints: 4, awayFormPoints: 6 }),
};

describe('explication sans cotes', () => {
  for (const [nom, texte] of Object.entries(variantes)) {
    it(`${nom} : plus aucune cote ni bookmaker, le reste est gardé`, () => {
      expect(texte).toMatch(/cote/i); // la version complète en parle bien
      const ios = explicationSansCotes(texte);
      expect(ios).not.toMatch(/cote|bookmaker/i);
      expect(ios).toContain('En combinant ces signaux, le modèle retient 71%');
      expect(ios).not.toMatch(/\s{2,}|^\s|\s$/);
    });
  }

  it('la forme et le modèle externe restent expliqués', () => {
    const ios = explicationSansCotes(variantes['forme connue, modèle externe']);
    expect(ios).toContain('Sur la forme récente, Galatasaray totalise 0 points contre 3 à Barcelona');
    expect(ios).toContain('donne 50% à cette issue');
  });

  it('un texte sans cote ressort inchangé', () => {
    expect(explicationSansCotes('Rien à retirer ici.')).toBe('Rien à retirer ici.');
  });
});
