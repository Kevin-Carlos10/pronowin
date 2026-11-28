/**
 * L'indice de confiance se saisit en pourcentage (décision du 1er octobre 2026).
 *
 * L'analyste saisit un pourcentage ; l'application et le site l'affichent tel
 * quel. Le niveau 1–5 en est déduit : le barème de mise, les recommandations
 * et les applications déjà installées n'en lisent pas d'autre. Ce banc tient
 * les deux bouts : la règle de déduction, et l'API qui publie les deux.
 */
import express from 'express';
import fs from 'fs';
import path from 'path';
import request from 'supertest';

import { valider } from '../middleware/valider';
import { pronosticAdmin } from '../schemas/entrees';
import {
  niveauDepuisPourcentage, pourcentageConfiance, pourcentageDepuisNiveau,
} from '../utils/confiance';

describe('du pourcentage au niveau', () => {
  it('paliers de 20 points', () => {
    expect([1, 19, 20, 39, 40, 59, 60, 79, 80, 99].map(niveauDepuisPourcentage))
      .toEqual([1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
  });

  it('un pronostic sans pourcentage prend le milieu de son palier', () => {
    expect([1, 2, 3, 4, 5].map(pourcentageDepuisNiveau)).toEqual([10, 30, 50, 70, 90]);
    // Et redéduire le niveau redonne celui de départ : rien n'est inventé.
    for (const n of [1, 2, 3, 4, 5]) expect(niveauDepuisPourcentage(pourcentageDepuisNiveau(n))).toBe(n);
  });

  it('le pourcentage saisi prime sur le niveau', () => {
    expect(pourcentageConfiance({ confidencePct: 73, confidenceScore: 4 })).toBe(73);
    expect(pourcentageConfiance({ confidencePct: null, confidenceScore: 4 })).toBe(70);
  });
});

describe('le formulaire du panneau', () => {
  const app = express().use(express.json())
    .post('/x', valider({ body: pronosticAdmin }), (req, res) => res.json(req.body));
  const base = {
    match_id: 'm1', prediction_type: 'win1', prediction_label: 'Victoire Lyon',
    odds_recommended: '1.85', publish: 'true',
  };

  it('accepte un pourcentage entier de 1 à 99', async () => {
    const r = await request(app).post('/x').send({ ...base, confidence_pct: '73' });
    expect(r.status).toBe(200);
    expect(r.body.confidence_pct).toBe(73);
  });

  it('refuse 0 et 100 : « 100 % » se lit comme une victoire certaine', async () => {
    for (const v of ['0', '100', '73.5', 'beaucoup']) {
      expect((await request(app).post('/x').send({ ...base, confidence_pct: v })).status).toBe(422);
    }
  });

  it('un ancien appel qui n\'envoie qu\'un niveau passe encore', async () => {
    expect((await request(app).post('/x').send({ ...base, confidence_score: '4' })).status).toBe(200);
  });

  it('sans aucune confiance, la demande est refusée', async () => {
    const r = await request(app).post('/x').send(base);
    expect(r.status).toBe(422);
    expect(r.body.message).toBe("Indiquez l'indice de confiance.");
  });
});

describe('l\'API publie les deux', () => {
  // Chaque réponse qui publie le niveau doit publier le pourcentage à côté :
  // l'application ne sait plus afficher autre chose, et un écran qui
  // recevrait le niveau seul retomberait sur une conversion.
  const sources = [
    'controllers/bankroll.controller.ts', 'controllers/favorites.controller.ts',
    'controllers/pronostics.controller.ts', 'services/pronostics.service.ts',
    'services/personalized_ai.service.ts',
  ];
  it.each(sources)('%s', (f) => {
    const code = fs.readFileSync(path.join(__dirname, '..', f), 'utf8');
    const niveaux = (code.match(/^\s*confidence_score:/gm) ?? []).length;
    const pourcentages = (code.match(/^\s*confidence_pct:/gm) ?? []).length;
    expect(pourcentages).toBe(niveaux);
  });

  it('l\'enregistrement déduit le niveau du pourcentage', () => {
    const code = fs.readFileSync(path.join(__dirname, '..', 'controllers/pronostics.controller.ts'), 'utf8');
    expect(code).toContain('niveauDepuisPourcentage(pctSaisi)');
    expect(code).toContain('confidencePct,');
  });
});
