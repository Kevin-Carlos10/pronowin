/**
 * `/config` publie le code promo du partenaire (7 novembre 2026), pour toutes
 * les versions de l'application, invités compris.
 */
jest.mock('../lib/prisma', () => ({
  prisma: { appSetting: { findMany: async () => [] } },
}));

import express from 'express';
import request from 'supertest';

import configRoutes from '../routes/config.routes';

const app = express().use('/config', configRoutes);
const ENV = { ...process.env };
afterEach(() => { process.env = { ...ENV }; });

describe('code promo publié par /config', () => {
  it('le code général, ou celui propre au partenaire s’il en a un', async () => {
    process.env.AFFILIATE_NAME = '1xBet';
    process.env.PROMO_CODE = 'PRONOWIN2026';
    delete process.env.PROMO_CODE_1XBET;
    expect((await request(app).get('/config')).body.promoCode).toBe('PRONOWIN2026');

    process.env.PROMO_CODE_1XBET = 'PRONOWIN1X';
    expect((await request(app).get('/config')).body.promoCode).toBe('PRONOWIN1X');
  });

  it('rien de configuré : null, et l’application n’affiche rien', async () => {
    delete process.env.PROMO_CODE;
    delete process.env.PROMO_CODE_1XBET;
    delete process.env.XBET_PROMO_CODE;
    expect((await request(app).get('/config')).body.promoCode).toBeNull();
  });
});
