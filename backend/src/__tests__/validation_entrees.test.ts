/**
 * La validation d'entrée par schéma (constat S3 de l'audit du 24 septembre
 * 2026).
 *
 * Le symptôme qui l'a fait écrire : `parseFloat('')` vaut NaN, et `NaN < 1.2`
 * est faux — une cote vide passait le contrôle du minimum. Un schéma convertit
 * une fois, à l'entrée : un nombre y est un nombre fini, ou la demande est
 * refusée avant d'atteindre le contrôleur.
 */
import express from 'express';
import request from 'supertest';

import { valider } from '../middleware/valider';
import { budgetBankroll, confirmationMise, jetonNotification, pronosticAdmin } from '../schemas/entrees';

/** Une route qui renvoie ce que le contrôleur recevrait. */
function route(schema: Parameters<typeof valider>[0]) {
  return express().use(express.json())
    .post('/x', valider(schema), (req, res) => res.json(req.body));
}

const formulaire = {
  match_id: 'm1', prediction_type: 'win1', prediction_label: 'Victoire Lyon',
  odds_home: '1.85', odds_draw: '3.4', odds_away: '4,2', odds_recommended: '1.85',
  confidence_score: '4', analyst_note: '', is_premium: 'on', publish: 'true', _csrf: 'jeton',
};

describe('pronostic du panneau', () => {
  const app = route({ body: pronosticAdmin });

  it('le formulaire arrive typé : nombres, virgule comprise, et vrais booléens', async () => {
    const r = await request(app).post('/x').send(formulaire);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({
      odds_home: 1.85, odds_away: 4.2, odds_recommended: 1.85, confidence_score: 4,
      is_premium: true, publish: true });
    expect(r.body.analyst_note).toBeUndefined();
    expect(r.body._csrf).toBeUndefined();                // champs inconnus écartés
  });

  it('une cote conseillée vide est refusée — elle devenait NaN', async () => {
    const r = await request(app).post('/x').send({ ...formulaire, odds_recommended: '' });
    expect(r.status).toBe(422);
    expect(r.body).toMatchObject({ code: 'VALIDATION', message: 'Indiquez la cote conseillée.' });
    expect(r.body.champs[0].champ).toBe('odds_recommended');
  });

  it('une cote illisible, ou sous 1, aussi', async () => {
    expect((await request(app).post('/x').send({ ...formulaire, odds_recommended: 'abc' })).body.message)
      .toBe('La cote conseillée doit être un nombre.');
    expect((await request(app).post('/x').send({ ...formulaire, odds_home: '0.5' })).body.message)
      .toBe('La cote domicile vaut au moins 1.');
  });

  it('une cote du match absente vaut 0, comme en base', async () => {
    const { odds_draw: _n, ...sansNul } = formulaire;
    expect((await request(app).post('/x').send(sansNul)).body.odds_draw).toBe(0);
  });

  it('la confiance est une note entière de 1 à 5', async () => {
    for (const v of ['0', '6', '3.5', '']) {
      expect((await request(app).post('/x').send({ ...formulaire, confidence_score: v })).status).toBe(422);
    }
  });
});

describe('bankroll et notifications', () => {
  it('un budget n\'est ni vide, ni négatif, ni illisible', async () => {
    const app = route({ body: budgetBankroll });
    for (const v of ['', '-5', 'beaucoup', null]) {
      expect((await request(app).post('/x').send({ total_budget: v })).status).toBe(422);
    }
    expect((await request(app).post('/x').send({ total_budget: '50 000'.replace(' ', ''), currency: 'eur' })).body)
      .toEqual({ total_budget: 50000, currency: 'EUR' });
  });

  it('confirmer une mise : sans montant, c\'est « oui » ; un montant négatif est refusé', async () => {
    const app = route({ body: confirmationMise });
    expect((await request(app).post('/x').send({})).body).toEqual({});
    expect((await request(app).post('/x').send({ mise_reelle: '0' })).body).toEqual({ mise_reelle: 0 });
    expect((await request(app).post('/x').send({ mise_reelle: -1 })).status).toBe(422);
  });

  it('un jeton de notification est un texte, et la plateforme inconnue devient android', async () => {
    const app = route({ body: jetonNotification });
    expect((await request(app).post('/x').send({ fcm_token: 42 })).status).toBe(422);
    expect((await request(app).post('/x').send({ fcm_token: ' abc ', platform: 'windows' })).body)
      .toEqual({ fcm_token: 'abc', platform: 'android' });
  });
});

describe('les routes appliquent leur schéma', () => {
  // Un schéma écrit mais non branché ne protège rien, et passerait tous les
  // tests ci-dessus.
  const fs = require('fs') as typeof import('fs');
  const path = require('path') as typeof import('path');
  const lire = (f: string) => fs.readFileSync(path.join(__dirname, '..', 'routes', f), 'utf8');

  it.each([
    ['pronostics.routes.ts', "r.post('/admin/pronostic',", 'pronosticAdmin'],
    ['bankroll.routes.ts', "r.post  ('/budget',", 'budgetBankroll'],
    ['bankroll.routes.ts', "r.post  ('/bet',", 'pariBankroll'],
    ['bankroll.routes.ts', "r.post  ('/bet/:id/confirmer',", 'confirmationMise'],
    ['notification.routes.ts', "r.post ('/register-token',", 'jetonNotification'],
  ])('%s — %s', (fichier, debut, schema) => {
    const ligne = lire(fichier).split('\n').find((l) => l.startsWith(debut));
    expect(ligne).toContain(`valider({ body: ${schema} })`);
  });
});
