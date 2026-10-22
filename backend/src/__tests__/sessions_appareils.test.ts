import { prisma } from '../lib/prisma';
import { AuthService, empreinteJeton } from '../services/auth.service';
import { listerSessions, noterSession, plateformeSession } from '../services/sessions.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';
import jwt from 'jsonwebtoken';

const auth = new AuthService();
const users: string[] = [];
const marque = `sessions-${Date.now()}`;
beforeAll(async () => {
  if (!BASE_LOCALE) return;
  for (let i = 0; i < 2; i++) {
    const u = await prisma.user.create({data: {pseudo: `${marque}-${i}`, referralCode: `${Date.now()}${i}`}});
    users.push(u.id);
  }
});
afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.user.deleteMany({where: {id: {in: users}}});
  await prisma.$disconnect();
});
const creer = (id: string) => (auth as any)._generateTokens(id);
const sid = (access: string) => (jwt.decode(access) as {sessionId: string}).sessionId;

decrireSurBaseLocale('Appareils connectés', () => {
  beforeEach(async () => { await prisma.refreshToken.deleteMany({where: {userId: {in: users}}}); });
  it('limite la liste au compte, exclut les sessions expirées/utilisées et ne renvoie aucun secret', async () => {
    const a = await creer(users[0]); const b = await creer(users[0]);
    await creer(users[1]);
    const expire = await creer(users[0]); const utilise = await creer(users[0]);
    await prisma.refreshToken.update({where: {token: empreinteJeton(expire.refresh_token)}, data: {expiresAt: new Date(0)}});
    await prisma.refreshToken.update({where: {token: empreinteJeton(utilise.refresh_token)}, data: {used: true}});
    const result = await listerSessions(users[0], sid(a.access_token), undefined, {'x-app-plateforme': 'ios'});
    expect(result).toHaveLength(2);
    expect(result[0]).toMatchObject({id: sid(a.access_token), current: true, platform: 'ios'});
    expect(result[1].id).toBe(sid(b.access_token));
    expect(Object.keys(result[0]).sort()).toEqual(['current','id','lastSeenAt','platform','startedAt']);
  });
  it('conserve la même session et sa date de connexion après rotation', async () => {
    const a = await creer(users[0]);
    await noterSession(users[0], sid(a.access_token), {'x-app-plateforme': 'android'}, true);
    const before = await listerSessions(users[0], sid(a.access_token));
    const b = await auth.refreshToken(a.refresh_token);
    expect(sid(b.access_token)).toBe(sid(a.access_token));
    const after = await listerSessions(users[0], sid(b.access_token));
    expect(after).toHaveLength(1);
    expect(after[0].startedAt).toEqual(before[0].startedAt);
    expect(after[0].platform).toBe('android');
  });
  it('reconnaît une ancienne session sans identifiant, mais jamais le jeton d’un autre compte', async () => {
    const a = await creer(users[0]); const b = await creer(users[1]);
    await prisma.refreshToken.update({where: {token: empreinteJeton(a.refresh_token)}, data: {sessionId: null, platform: null}});
    const foreign = await listerSessions(users[0], undefined, b.refresh_token, {'x-app-plateforme': 'web'});
    expect(foreign.every(s => !s.current)).toBe(true);
    const own = await listerSessions(users[0], undefined, a.refresh_token, {'x-app-plateforme': 'ios'});
    expect(own[0]).toMatchObject({current: true, platform: 'ios'});
    const other = await listerSessions(users[1], sid(b.access_token));
    expect(other[0].platform).toBeNull();
  });
  it('retire la session après déconnexion', async () => {
    const a = await creer(users[0]);
    await auth.logout(users[0], a.refresh_token);
    expect(await listerSessions(users[0])).toEqual([]);
  });
});
it('n’accepte que les plateformes connues', () => {
  expect(plateformeSession({'x-app-plateforme': 'ios'})).toBe('ios');
  expect(plateformeSession({'x-app-plateforme': '<script>'})).toBeNull();
  expect(plateformeSession({'x-app-plateforme': ['android']})).toBeNull();
});
