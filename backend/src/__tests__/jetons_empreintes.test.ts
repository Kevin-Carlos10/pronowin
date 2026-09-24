/**
 * Des empreintes en base, et des jetons qui ne servent qu'une fois.
 *
 * S11 — refresh tokens et codes de connexion étaient stockés en clair ; la
 *       rotation lisait puis marquait sans condition, si bien que deux
 *       rafraîchissements simultanés réussissaient ; et deux jetons émis dans
 *       la même seconde pour un compte étaient identiques.
 * S12 — changer le mot de passe d'un administrateur ne fermait pas les
 *       sessions déjà ouvertes : son jeton de 8 heures restait valable.
 *
 * Banc sur la base de développement (`DATABASE_URL`), avec des comptes créés
 * pour lui et supprimés ensuite.
 */
process.env.JWT_SECRET = process.env.JWT_SECRET || 'banc-jwt';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'banc-refresh';
process.env.ADMIN_DELEGATION_SECRET = process.env.ADMIN_DELEGATION_SECRET || 'banc-delegation';

import bcrypt from 'bcryptjs';
import express from 'express';
import request from 'supertest';

import { prisma } from '../lib/prisma';
import { AuthService, empreinteJeton, empreinteOtp } from '../services/auth.service';
import { AdminAuthService } from '../services/admin_auth.service';
import { signerDelegation, ENTETE_DELEGATION } from '../utils/delegation_admin';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { adminMiddleware } = require('../middleware/admin.middleware');

const marque = `banc-s11-${Date.now()}`;
const auth = new AuthService();
let userId = '';
let adminId = '';
const courriel = `${marque}@banc.invalid`;

beforeAll(async () => {
  const u = await prisma.user.create({
    data: { pseudo: marque, referralCode: marque.slice(-12).toUpperCase() },
  });
  userId = u.id;
  const a = await prisma.admin.create({
    data: { email: courriel, passwordHash: await bcrypt.hash('AncienMotDePasse1', 4), name: 'Banc', role: 'super_admin' },
  });
  adminId = a.id;
});

afterAll(async () => {
  await prisma.refreshToken.deleteMany({ where: { userId } });
  await prisma.otpCode.deleteMany({ where: { phoneNumber: { startsWith: marque } } });
  await prisma.user.delete({ where: { id: userId } }).catch(() => {});
  await prisma.admin.delete({ where: { id: adminId } }).catch(() => {});
  await prisma.$disconnect();
});

describe('refresh tokens (S11)', () => {
  it('la base ne garde que l\'empreinte', async () => {
    const { refresh_token } = await (auth as any)._generateTokens(userId);
    expect(await prisma.refreshToken.count({ where: { token: refresh_token } })).toBe(0);
    expect(await prisma.refreshToken.count({ where: { token: empreinteJeton(refresh_token) } })).toBe(1);
  });

  it('deux jetons émis la même seconde sont différents', async () => {
    const [a, b] = await Promise.all([
      (auth as any)._generateTokens(userId), (auth as any)._generateTokens(userId)]);
    expect(a.refresh_token).not.toBe(b.refresh_token);
  });

  it('un jeton rafraîchi deux fois en même temps ne l\'est qu\'une', async () => {
    const { refresh_token } = await (auth as any)._generateTokens(userId);
    const issues = await Promise.allSettled([
      auth.refreshToken(refresh_token), auth.refreshToken(refresh_token)]);
    expect(issues.filter((i) => i.status === 'fulfilled')).toHaveLength(1);
  });

  it('un jeton émis avant les empreintes reste utilisable une fois', async () => {
    // Contrepartie de la migration : sans elle, chaque utilisateur connecté
    // aurait été déconnecté au premier rafraîchissement.
    const ancien = `ancien-jeton-${marque}`;
    await prisma.refreshToken.create({
      data: { userId, token: ancien, expiresAt: new Date(Date.now() + 86400000) } });
    await expect(auth.refreshToken(ancien)).resolves.toHaveProperty('refresh_token');
    await expect(auth.refreshToken(ancien)).rejects.toThrow(/compromise/);
  });
});

describe('codes de connexion (S11)', () => {
  const dest = `${marque}-otp`;
  const poser = (code: string, brut = false) => prisma.otpCode.create({ data: {
    phoneNumber: dest, code: brut ? code : empreinteOtp(dest, code),
    expiresAt: new Date(Date.now() + 600000) } });

  it('un code vérifié deux fois en même temps ne sert qu\'une fois', async () => {
    await poser('482913');
    const issues = await Promise.all([
      (auth as any)._consommerOtp(dest, '482913'), (auth as any)._consommerOtp(dest, '482913')]);
    expect(issues.filter(Boolean)).toHaveLength(1);
  });

  it('la base ne contient pas le code', async () => {
    await poser('777111');
    expect(await prisma.otpCode.count({ where: { phoneNumber: dest, code: '777111' } })).toBe(0);
  });

  it('un mauvais code est refusé, un code en clair d\'avant la migration est accepté', async () => {
    await poser('123456', true);
    expect(await (auth as any)._consommerOtp(dest, '000000')).toBe(false);
    expect(await (auth as any)._consommerOtp(dest, '123456')).toBe(true);
  });
});

describe('sessions administrateur (S12)', () => {
  const app = express();
  app.get('/pronostics/admin/upcoming', adminMiddleware, (_req, res) => res.json({ ok: true }));
  const appel = (jeton: string) => request(app).get('/pronostics/admin/upcoming')
    .set('Authorization', `Bearer ${jeton}`)
    .set(ENTETE_DELEGATION, signerDelegation({ id: 'main', nom: 'Banc', role: 'main', perms: [] },
      process.env.ADMIN_DELEGATION_SECRET!));

  it('changer le mot de passe ferme les sessions ouvertes, pas celle qui le change', async () => {
    const svc = new AdminAuthService();
    const { token: avant } = await svc.login(courriel, 'AncienMotDePasse1');
    expect((await appel(avant)).status).toBe(200);

    const { token: neuf } = await svc.changePassword(adminId, 'AncienMotDePasse1', 'NouveauMotDePasse2') as any;
    const refus = await appel(avant);
    expect(refus.status).toBe(401);
    expect(refus.body.code).toBe('SESSION_REVOQUEE');
    expect((await appel(neuf)).status).toBe(200);
  });
});
