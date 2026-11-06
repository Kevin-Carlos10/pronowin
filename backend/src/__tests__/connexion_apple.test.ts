/**
 * « Se connecter avec Apple » (règle 4.8 de l'App Store).
 *
 * Une paire de clés du banc signe les jetons à la place d'Apple ; la liste
 * des clés publiques est substituée. Tout ce que le serveur doit refuser
 * l'est ici : autre audience, autre émetteur, jeton expiré, nonce absent ou
 * différent, jeton signé par un secret partagé.
 *
 * Les comptes : bancs sur la base de développement.
 */
process.env.JWT_SECRET = process.env.JWT_SECRET || 'banc-jwt';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'banc-refresh';

import crypto from 'crypto';
import jwt from 'jsonwebtoken';

import { prisma } from '../lib/prisma';
import {
  _banc, _http, chiffrer, dechiffrer, empreinteNonce, obtenirJetonRevocable, revoquer, verifierJetonApple,
} from '../services/apple_auth';
import { AuthService } from '../services/auth.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...(publicKey.export({ format: 'jwk' }) as any), kid: 'banc-kid', alg: 'RS256' };
let lectures = 0;
_banc.lireCles = async () => { lectures++; return [jwk]; };

const NONCE = 'nonce-brut-du-telephone-0123456789';
const marque = `banc-apple-${Date.now()}`;

/** Un jeton comme Apple l'émettrait, modifiable champ par champ. */
function jeton(champs: Record<string, unknown> = {}, options: jwt.SignOptions = {}) {
  return jwt.sign({
    nonce: empreinteNonce(NONCE), email: `${marque}@privaterelay.appleid.com`,
    email_verified: 'true', is_private_email: 'true', ...champs,
  }, privateKey, {
    algorithm: 'RS256', keyid: 'banc-kid', issuer: 'https://appleid.apple.com',
    audience: 'com.pronowin.app', subject: `${marque}-sub`, expiresIn: '5m', ...options,
  });
}

beforeEach(() => { _banc.oublier(); lectures = 0; });

describe('le jeton d\'identité Apple', () => {
  it('un jeton valide rend l\'identifiant Apple et l\'adresse vérifiée', async () => {
    await expect(verifierJetonApple(jeton(), NONCE)).resolves.toEqual({
      sub: `${marque}-sub`, email: `${marque}@privaterelay.appleid.com`, relais: true });
  });

  it.each([
    ['une autre app', {}, { audience: 'com.autre.app' }],
    ['un autre émetteur', {}, { issuer: 'https://faux.example' }],
    ['un jeton expiré', {}, { expiresIn: -10 }],
  ])('refuse %s', async (_nom, champs, options) => {
    await expect(verifierJetonApple(jeton(champs, options as jwt.SignOptions), NONCE))
      .rejects.toThrow('Jeton Apple invalide.');
  });

  it('refuse un nonce absent ou différent : un jeton intercepté ne se rejoue pas', async () => {
    await expect(verifierJetonApple(jeton(), '')).rejects.toThrow('Jeton Apple invalide.');
    await expect(verifierJetonApple(jeton(), 'un-autre-nonce-0123456789')).rejects.toThrow('Jeton Apple invalide.');
    await expect(verifierJetonApple(jeton({ nonce: NONCE }), NONCE)).rejects.toThrow('Jeton Apple invalide.');
  });

  it('refuse un jeton signé par un secret partagé au lieu de la clé d\'Apple', async () => {
    const forge = jwt.sign({ nonce: empreinteNonce(NONCE) }, 'secret', {
      algorithm: 'HS256', keyid: 'banc-kid', issuer: 'https://appleid.apple.com',
      audience: 'com.pronowin.app', subject: 'intrus' });
    await expect(verifierJetonApple(forge, NONCE)).rejects.toThrow('Jeton Apple invalide.');
  });

  it('une adresse non vérifiée n\'est pas retenue', async () => {
    expect((await verifierJetonApple(jeton({ email_verified: 'false' }), NONCE)).email).toBeNull();
  });

  it('les clés d\'Apple sont gardées en cache, et relues pour une clé inconnue', async () => {
    await verifierJetonApple(jeton(), NONCE);
    await verifierJetonApple(jeton(), NONCE);
    expect(lectures).toBe(1);
    await expect(verifierJetonApple(jeton({}, { keyid: 'nouvelle' }), NONCE)).rejects.toThrow();
    expect(lectures).toBe(2);
  });
});

describe('révocation à la suppression du compte', () => {
  const ENV = { ...process.env };
  const { privateKey: ec } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const appels: { url: string; champs: Record<string, string> }[] = [];
  const posterReel = _http.poster;

  beforeEach(() => {
    appels.length = 0;
    _http.poster = async (url, champs) => {
      appels.push({ url, champs });
      return url.endsWith('/auth/token') ? { refresh_token: 'rt-apple-secret' } : {};
    };
  });
  afterEach(() => { process.env = { ...ENV }; _http.poster = posterReel; });

  it('sans clé Apple configurée, rien n\'est échangé ni révoqué', async () => {
    delete process.env.APPLE_SIWA_KEY_ID;
    expect(await obtenirJetonRevocable('code')).toBeNull();
    expect(await revoquer('x')).toBe(false);
    expect(appels).toEqual([]);
  });

  it('avec la clé : le jeton est gardé chiffré, puis révoqué en clair auprès d\'Apple', async () => {
    process.env.APPLE_TEAM_ID = 'FCK95AP299';
    process.env.APPLE_SIWA_KEY_ID = 'BANCKEY123';
    process.env.APPLE_SIWA_PRIVATE_KEY = ec.export({ format: 'pem', type: 'pkcs8' }) as string;

    const garde = await obtenirJetonRevocable('code-autorisation');
    expect(garde).not.toContain('rt-apple-secret');                 // jamais en clair en base
    expect(dechiffrer(garde!)).toBe('rt-apple-secret');

    expect(await revoquer(garde)).toBe(true);
    const revocation = appels.find((a) => a.url.endsWith('/auth/revoke'))!;
    expect(revocation.champs).toMatchObject({ client_id: 'com.pronowin.app', token: 'rt-apple-secret',
      token_type_hint: 'refresh_token' });
    // Le secret client est un JWT ES256 signé par notre clé, pour Apple.
    const secret = jwt.decode(revocation.champs.client_secret, { complete: true })!;
    expect(secret.header).toMatchObject({ alg: 'ES256', kid: 'BANCKEY123' });
    expect(secret.payload).toMatchObject({ iss: 'FCK95AP299', aud: 'https://appleid.apple.com', sub: 'com.pronowin.app' });
  });

  it('un chiffré altéré ne se déchiffre pas', () => {
    const c = chiffrer('rt');
    const [iv, tag, corps] = c.split('.');
    const altere = [iv, tag, Buffer.from('xx').toString('base64')].join('.');
    expect(() => dechiffrer(altere)).toThrow();
    expect(corps).toBeTruthy();
  });
});

const auth = new AuthService();
const crees: string[] = [];

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.refreshToken.deleteMany({ where: { userId: { in: crees } } });
  await prisma.user.deleteMany({ where: { id: { in: crees } } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('les comptes (Apple)', () => {
  const connexion = (champs: Record<string, unknown> = {}, extra: object = {}, options: jwt.SignOptions = {}) =>
    auth.loginWithApple({ identityToken: jeton(champs, options), nonce: NONCE, ...extra });

  it('une première connexion crée le compte, avec le nom transmis par le téléphone', async () => {
    const r = await connexion({}, { givenName: 'Awa', familyName: 'Traoré' });
    crees.push(r.user.id);
    expect(r.user).toMatchObject({ appleId: `${marque}-sub`, firstName: 'Awa', lastName: 'Traoré',
      email: `${marque}@privaterelay.appleid.com`, emailVerified: true });
    expect(r.access_token).toBeTruthy();
  });

  it('la suivante le retrouve par l\'identifiant Apple, même sans adresse', async () => {
    const r = await connexion({ email: undefined, email_verified: undefined });
    expect(r.user.appleId).toBe(`${marque}-sub`);
    expect(await prisma.user.count({ where: { appleId: `${marque}-sub` } })).toBe(1);
  });

  it('une personne déjà inscrite par e-mail retrouve son compte, désormais lié à Apple', async () => {
    const existant = await prisma.user.create({ data: {
      email: `${marque}-inscrit@example.com`, pseudo: `${marque}-e`, referralCode: `${marque.slice(-9)}E`.toUpperCase() } });
    crees.push(existant.id);
    const r = await connexion({ email: `${marque}-inscrit@example.com` }, {}, { subject: `${marque}-sub2` });
    expect(r.user.id).toBe(existant.id);
    expect(r.user.appleId).toBe(`${marque}-sub2`);
  });

  it('deux premières connexions simultanées ne créent qu\'un compte', async () => {
    const [a, b] = await Promise.all([
      connexion({ email: undefined }, {}, { subject: `${marque}-sub3` }),
      connexion({ email: undefined }, {}, { subject: `${marque}-sub3` }),
    ]);
    crees.push(a.user.id);
    expect(a.user.id).toBe(b.user.id);
    expect(await prisma.user.count({ where: { appleId: `${marque}-sub3` } })).toBe(1);
  });
});
