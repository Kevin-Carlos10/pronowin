/**
 * Ce qu'une erreur laisse voir hors de l'API.
 *
 * S2 — quatre-vingt-sept routes renvoyaient `err.message` dans leurs réponses
 *      500 : pour une erreur Prisma, la table, la colonne, la contrainte.
 * P5 — le middleware d'authentification répondait 401 à toute erreur, base
 *      injoignable comprise ; l'application en concluait que la session était
 *      morte et déconnectait l'utilisateur.
 * I8 — sans identifiants SMTP ou WhatsApp, l'envoi du code se déclarait
 *      réussi, en production aussi, et le code s'écrivait dans le journal.
 */
import express from 'express';
import jwt from 'jsonwebtoken';
import request from 'supertest';

const journal: string[] = [];
jest.mock('../utils/logger', () => {
  const noter = (...a: any[]) => { journal.push(a.map(String).join(' ')); };
  return {
    __esModule: true,
    default: { error: noter, warn: noter, info: noter, http: noter },
    journal: { error: noter, warn: noter, info: noter },
    requeteCourante: () => null,
  };
});

const findUnique = jest.fn();
jest.mock('../lib/prisma', () => ({
  prisma: { user: { findUnique: (...a: any[]) => findUnique(...a), update: jest.fn(async () => ({})) } },
}));

import { ErreurMetier, repondreErreur } from '../utils/erreurs';
import { authMiddleware } from '../middleware/auth.middleware';

process.env.JWT_SECRET = 'secret-de-banc';

function appli(erreur: unknown, statut?: number) {
  const app = express();
  app.get('/x', (_req, res) => repondreErreur(res, erreur, statut));
  return app;
}

/** Une erreur comme Prisma en lève : son message décrit la base. */
function erreurPrisma(code: string, nom = 'PrismaClientKnownRequestError') {
  const e: any = new Error(
    'Invalid `prisma.user.findMany()` invocation:\n\nThe column `users.secret_col` does not exist');
  e.name = nom;
  e.code = code;
  return e;
}

describe('sortie unique des erreurs (S2)', () => {
  it('une erreur Prisma sort sans détail, avec une référence', async () => {
    journal.length = 0;
    const r = await request(appli(erreurPrisma('P2022'))).get('/x');
    expect(r.status).toBe(500);
    expect(JSON.stringify(r.body)).not.toMatch(/prisma|users|secret_col|column/i);
    expect(r.body.reference).toMatch(/^[0-9a-f]{8}$/);
    // Le détail n'est pas perdu : il est au journal, sous la même référence.
    expect(journal.join('\n')).toContain(r.body.reference);
    expect(journal.join('\n')).toContain('secret_col');
  });

  it('une base injoignable répond 503, pas 500', async () => {
    const r = await request(appli(erreurPrisma('P1001', 'PrismaClientInitializationError'))).get('/x');
    expect(r.status).toBe(503);
    expect(r.body.code).toBe('SERVICE_INDISPONIBLE');
  });

  it('une erreur réseau d\'un fournisseur ne dit pas lequel', async () => {
    const e: any = new Error('connect ECONNREFUSED 10.0.0.4:5432');
    const r = await request(appli(e)).get('/x');
    expect(JSON.stringify(r.body)).not.toMatch(/10\.0\.0\.4|5432/);
  });

  it('un message métier sort tel quel, avec le statut de la route', async () => {
    const r = await request(appli(new Error('Preuve déjà traitée.'), 400)).get('/x');
    expect(r.status).toBe(400);
    expect(r.body.message).toBe('Preuve déjà traitée.');
  });

  it('une ErreurMetier impose son statut et son code', async () => {
    const r = await request(appli(new ErreurMetier('Introuvable.', 404, 'INTROUVABLE'))).get('/x');
    expect(r.status).toBe(404);
    expect(r.body).toEqual({ message: 'Introuvable.', code: 'INTROUVABLE' });
  });

  it('un statut porté par l\'erreur est respecté (quota d\'envoi)', async () => {
    const e: any = new Error('Trop de codes demandés.');
    e.statut = 429;
    const r = await request(appli(e)).get('/x');
    expect(r.status).toBe(429);
  });
});

describe('authentification : une panne n\'est pas un jeton refusé (P5)', () => {
  const app = express();
  app.get('/prive', authMiddleware as any, (_req, res) => res.json({ ok: true }));
  const jeton = jwt.sign({ userId: 'u1' }, 'secret-de-banc');

  it('base injoignable → 503, la session reste valable', async () => {
    findUnique.mockRejectedValueOnce(erreurPrisma('P1001', 'PrismaClientInitializationError'));
    const r = await request(app).get('/prive').set('Authorization', `Bearer ${jeton}`);
    expect(r.status).toBe(503);
  });

  it('jeton invalide → 401', async () => {
    const r = await request(app).get('/prive').set('Authorization', 'Bearer pas-un-jeton');
    expect(r.status).toBe(401);
  });

  it('jeton valide et base disponible → la requête passe', async () => {
    findUnique.mockResolvedValueOnce({ id: 'u1', isActive: true, lastSeenAt: new Date() });
    const r = await request(app).get('/prive').set('Authorization', `Bearer ${jeton}`);
    expect(r.status).toBe(200);
  });
});

describe('envoi du code sans canal configuré (I8)', () => {
  const env = { ...process.env };
  afterEach(() => { process.env = { ...env }; jest.resetModules(); });

  it.each([
    ['e-mail',   '../services/email.service',    'sendEmailOtp',    ['SMTP_USER', 'SMTP_PASS']],
    ['WhatsApp', '../services/whatsapp.service', 'sendWhatsAppOtp', ['WHATSAPP_PHONE_NUMBER_ID', 'WHATSAPP_ACCESS_TOKEN']],
  ])('%s : en production, un refus explicite et aucun code au journal', async (_c, module, fonction, cles) => {
    process.env.NODE_ENV = 'production';
    for (const c of cles as string[]) delete process.env[c];
    journal.length = 0;
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const envoyer = require(module as string)[fonction as string];
    // Par le nom et non par la classe : `resetModules` recharge le module des
    // erreurs entre deux cas, et deux chargements font deux classes.
    await expect(envoyer('destinataire', '482913'))
      .rejects.toMatchObject({ name: 'ServiceIndisponible', statut: 503 });
    expect(journal.join('\n')).not.toContain('482913');
  });

  it('en développement, le code reste lisible au journal', async () => {
    // Contrepartie : sans elle, un repli supprimé partout passerait le point
    // précédent — et les bancs d'essai ne pourraient plus se connecter.
    process.env.NODE_ENV = 'development';
    delete process.env.SMTP_USER;
    journal.length = 0;
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { sendEmailOtp } = require('../services/email.service');
    await expect(sendEmailOtp('dev@exemple', '111222')).resolves.toBeUndefined();
    expect(journal.join('\n')).toContain('111222');
  });
});
