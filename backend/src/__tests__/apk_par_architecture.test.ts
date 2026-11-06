/**
 * `/config` publie un APK par architecture (constat M3 de l'audit du
 * 24 septembre 2026) : l'universel pèse 68 Mo, l'arm64 seul 25.
 *
 * Sans base : les réglages viennent de l'environnement, comme sur un serveur
 * qui n'a encore rien enregistré dans le panneau.
 */
jest.mock('../lib/prisma', () => ({
  prisma: { appSetting: { findMany: async () => [] } },
}));

import express from 'express';
import request from 'supertest';

import configRoutes from '../routes/config.routes';
import { ecrireConfig } from '../services/app_config.service';

const app = express().use('/config', configRoutes);
const ENV = { ...process.env };
afterEach(() => { process.env = { ...ENV }; });

describe('APK par architecture (M3)', () => {
  it('publie les liens renseignés, sous les noms Android des architectures', async () => {
    process.env.APK_URL = 'https://pronowin.space/downloads/app-release.apk';
    process.env.APK_URL_ARM64 = 'https://pronowin.space/downloads/pronowin-arm64-v8a.apk';
    process.env.APK_URL_ARMV7 = 'https://pronowin.space/downloads/pronowin-armeabi-v7a.apk';

    const r = await request(app).get('/config');
    expect(r.body.apkUrl).toBe(process.env.APK_URL);
    expect(r.body.apkUrls).toEqual({
      'arm64-v8a':   process.env.APK_URL_ARM64,
      'armeabi-v7a': process.env.APK_URL_ARMV7,
    });
  });

  it('sans lien par architecture, la liste est vide et l\'universel reste', async () => {
    // Les applications déjà installées ne lisent que `apkUrl` : il ne doit
    // pas disparaître.
    process.env.APK_URL = 'https://pronowin.space/downloads/app-release.apk';
    delete process.env.APK_URL_ARM64;
    delete process.env.APK_URL_ARMV7;

    const r = await request(app).get('/config');
    expect(r.body.apkUrls).toEqual({});
    expect(r.body.apkUrl).toBe(process.env.APK_URL);
  });

  it('le panneau refuse un lien qui n\'est pas une adresse web', async () => {
    await expect(ecrireConfig({ APK_URL_ARM64: 'ftp://exemple/app.apk' })).rejects.toThrow(/http/);
    await expect(ecrireConfig({ APK_URL_ARMV7: 'app.apk' })).rejects.toThrow(/http/);
  });
});
