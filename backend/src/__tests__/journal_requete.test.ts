/**
 * Chaque requête a un identifiant, que le journal et la réponse portent
 * (constat Q1 : journaux en texte libre, sans identifiant commun).
 */
import express from 'express';
import request from 'supertest';

import { identifiantDeRequete, requeteCourante } from '../utils/logger';

const app = express();
app.use(identifiantDeRequete);
app.get('/x', async (_req, res) => {
  // Après un saut asynchrone, le contexte suit toujours la requête.
  await new Promise((r) => setTimeout(r, 5));
  res.json({ vu: requeteCourante() });
});

describe('identifiant de requête', () => {
  it('est fabriqué, renvoyé, et lisible pendant tout le traitement', async () => {
    const r = await request(app).get('/x');
    expect(r.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
    expect(r.body.vu).toBe(r.headers['x-request-id']);
  });

  it('reprend celui du proxy quand il a une forme raisonnable', async () => {
    const r = await request(app).get('/x').set('X-Request-Id', 'nginx-1234abcd');
    expect(r.body.vu).toBe('nginx-1234abcd');
  });

  it('ignore une valeur fantaisiste', async () => {
    const r = await request(app).get('/x').set('X-Request-Id', '<script>alert(1)</script>');
    expect(r.body.vu).not.toContain('<');
  });

  it('n\'existe pas hors requête', () => {
    expect(requeteCourante()).toBeNull();
  });
});
