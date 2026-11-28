/**
 * Un webhook de store n'acquitte que ce qu'il a inscrit.
 *
 * Les contrôleurs répondaient 200 même quand le traitement échouait : pour le
 * store, l'événement était livré, et il ne le renvoyait jamais (constat I10).
 * Ils inscrivent désormais l'événement avant de répondre ; si l'inscription
 * échoue, ils répondent 503 et c'est le store qui réessaie.
 */
const recevoir = jest.fn();
jest.mock('../services/iap_notifications.service', () => ({
  FileNotificationsIap: class {
    recevoir(...a: any[]) { return recevoir(...a); }
    async traiterEnAttente() { return 0; }
  },
  identifiantApple: () => 'uuid-apple',
  identifiantGoogle: (m: any) => m.messageId,
}));
jest.mock('../services/iap.service', () => ({ IapService: class {}, IAP_PRODUCTS: {} }));

import express from 'express';
import request from 'supertest';
import { appleNotifications, googleNotifications } from '../controllers/iap.controller';

const app = express();
app.use(express.json());
app.post('/apple', appleNotifications);
app.post('/google', googleNotifications);

const google = { message: { messageId: 'm-1', data: Buffer.from('{}').toString('base64') } };

describe('acquittement des webhooks', () => {
  it('inscrit, puis acquitte', async () => {
    recevoir.mockResolvedValueOnce({ doublon: false });
    const r = await request(app).post('/google').send(google);
    expect(r.status).toBe(200);
    expect(recevoir).toHaveBeenCalledWith('google', 'm-1', { message: google.message });
  });

  it('répond 503 quand l\'inscription échoue, pour que le store réessaie', async () => {
    recevoir.mockRejectedValueOnce(new Error('base injoignable'));
    const r = await request(app).post('/google').send(google);
    expect(r.status).toBe(503);
    // Et rien de la panne ne sort dans la réponse.
    expect(JSON.stringify(r.body)).not.toMatch(/injoignable/);
  });

  it('acquitte un doublon sans le réinscrire', async () => {
    recevoir.mockResolvedValueOnce({ doublon: true });
    const r = await request(app).post('/apple').send({ signedPayload: 'a.b.c' });
    expect(r.status).toBe(200);
    expect(r.body.doublon).toBe(true);
  });
});
