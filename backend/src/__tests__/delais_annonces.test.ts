import fs from 'fs';
import path from 'path';
import { REVIEW_DELAY_DIRECT, REVIEW_DELAY_CODE } from '../services/subscription.service';

/**
 * Un délai annoncé deux fois finit par être annoncé de deux façons.
 *
 * La réponse à une soumission de preuve portait `estimated_review` — construit
 * depuis la constante — et un `message` qui répétait « sous 30 minutes » en
 * dur. Raccourcir la variable faisait dire à la même réponse deux choses
 * différentes, dans deux champs que l'écran affiche l'un sous l'autre.
 */
const SRC = fs.readFileSync(
  path.join(__dirname, '..', 'services', 'subscription.service.ts'), 'utf8');

/** Le fichier sans ses commentaires : ils citent le défaut, ils ne le portent pas. */
const code = SRC
  .split('\n')
  .filter(l => !l.trimStart().startsWith('*') &&
               !l.trimStart().startsWith('//') &&
               !l.trimStart().startsWith('/*'))
  .join('\n');

describe('délais de validation — une seule source', () => {
  it('les valeurs par défaut sont surchargeables par l\'environnement', () => {
    expect(REVIEW_DELAY_DIRECT).toBeTruthy();
    expect(REVIEW_DELAY_CODE).toBeTruthy();
    expect(code).toContain('process.env.REVIEW_DELAY_DIRECT ??');
    expect(code).toContain('process.env.REVIEW_DELAY_CODE   ??');
  });

  it('aucun délai n\'est réécrit ailleurs dans le fichier', () => {
    // Chaque littéral ne doit apparaître qu'à la ligne qui définit sa constante.
    for (const valeur of [REVIEW_DELAY_DIRECT, REVIEW_DELAY_CODE]) {
      const occurrences = code.split(valeur).length - 1;
      expect(occurrences).toBe(1);
    }

    // Et les formes abrégées de ces mêmes délais — celles qu'on écrit sans y
    // penser dans une phrase — ne doivent pas exister non plus.
    for (const forme of ['sous 30 minutes', 'sous 2 heures', 'sous 30 min']) {
      expect(code).not.toContain(forme);
    }
  });

  it('le message rendu et le délai annoncé disent la même chose', () => {
    // Le lien est syntaxique : le message interpole la constante.
    expect(code).toContain('${REVIEW_DELAY_DIRECT}');
    expect(code).toContain('${REVIEW_DELAY_CODE}');
    expect(code).toContain(
      'estimated_review: type === \'payment_screenshot\' ? REVIEW_DELAY_DIRECT : REVIEW_DELAY_CODE');
  });
});
