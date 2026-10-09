/**
 * Une route qui ne reçoit pas d'image n'accepte pas 10 Mo (constat S4).
 */
import express from 'express';
import request from 'supertest';

import { monterAnalyseursJson } from '../utils/analyseurs_json';

const app = express();
monterAnalyseursJson(app);
const recu = (req: any, res: any) => res.json({ octets: JSON.stringify(req.body).length });
app.post('/api/v1/subscriptions/submit-proof', recu);
app.post('/api/v1/auth/send-otp', recu);
app.post('/api/v1/admin/tutorials', recu);
// Le gestionnaire d'erreurs de l'API répond 413 à un corps trop gros ; ici
// on lit le statut que l'analyseur attribue.
app.use((err: any, _req: any, res: any, _next: any) => res.status(err.status ?? 500).json({ type: err.type }));

const corps = (octets: number) => ({ image_base64: 'A'.repeat(octets) });

describe('taille des corps JSON', () => {
  it('une route ordinaire refuse 1 Mo', async () => {
    const r = await request(app).post('/api/v1/auth/send-otp').send(corps(1024 * 1024));
    expect(r.status).toBe(413);
  });

  it('une route ordinaire accepte un corps normal', async () => {
    const r = await request(app).post('/api/v1/auth/send-otp').send({ phone_number: '+22670000000' });
    expect(r.status).toBe(200);
  });

  it('la route des preuves accepte une image de 5 Mo en base64', async () => {
    const r = await request(app).post('/api/v1/subscriptions/submit-proof').send(corps(6.7 * 1024 * 1024));
    expect(r.status).toBe(200);
  });

  it('l\'administration accepte un contenu éditorial long, pas une image', async () => {
    expect((await request(app).post('/api/v1/admin/tutorials').send(corps(1024 * 1024))).status).toBe(200);
    expect((await request(app).post('/api/v1/admin/tutorials').send(corps(5 * 1024 * 1024))).status).toBe(413);
  });
});
