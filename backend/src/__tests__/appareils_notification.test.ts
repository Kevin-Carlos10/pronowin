/**
 * Un jeton de notification par appareil, et un appareil par compte (constat
 * I12 de l'audit du 24 septembre 2026).
 *
 * Le compte gardait un seul jeton, dans `users.fcm_token`. Il ne recevait que
 * sur son dernier appareil ; et un téléphone repris par un autre compte
 * gardait son jeton sur l'ancien : les notifications privées du premier —
 * versements, parrainage, Premium — arrivaient chez le second.
 *
 * Banc sur la base de développement, avec un Firebase simulé qui enregistre
 * ce qui part et peut déclarer des jetons morts.
 */
process.env.FIREBASE_PROJECT_ID = 'banc';
process.env.FIREBASE_PRIVATE_KEY = 'banc';

const mockLots: string[][] = [];
const mockMorts = new Set<string>();

jest.mock('firebase-admin', () => ({
  __esModule: true,
  default: {
    apps: [{}], // déjà initialisé : initializeApp n'est pas appelé
    messaging: () => ({
      sendEachForMulticast: (m: { tokens: string[] }) => {
        mockLots.push([...m.tokens]);
        const responses = m.tokens.map(t => mockMorts.has(t)
          ? { success: false, error: { code: 'messaging/registration-token-not-registered', message: 'mort' } }
          : { success: true });
        const successCount = responses.filter(r => r.success).length;
        return Promise.resolve({ responses, successCount, failureCount: responses.length - successCount });
      },
    }),
  },
}));

import { prisma } from '../lib/prisma';
import { APPAREILS_PAR_COMPTE, NotificationService } from '../services/notification.service';
import { AuthService } from '../services/auth.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const marque = `banc-i12-${Date.now()}`;
const svc = new NotificationService();
const auth = new AuthService();
const comptes: Record<'a' | 'b' | 'c', string> = { a: '', b: '', c: '' };
const jeton = (n: string) => `${marque}-${n}`;
const message = { title: 'Versement effectué', body: '5 000 FCFA' };
const appareilsDe = async (userId: string) =>
  (await prisma.appareilNotification.findMany({ where: { userId }, select: { jeton: true } }))
    .map(a => a.jeton).sort();

beforeAll(async () => {
  if (!BASE_LOCALE) return;
  for (const k of ['a', 'b', 'c'] as const) {
    const u = await prisma.user.create({
      data: { pseudo: `${marque}-${k}`, referralCode: `${marque.slice(-9)}${k}`.toUpperCase() },
    });
    comptes[k] = u.id;
  }
});

beforeEach(() => { mockLots.length = 0; mockMorts.clear(); });

afterAll(async () => {
  if (!BASE_LOCALE) return;
  const ids = Object.values(comptes).filter(Boolean);
  await prisma.notification.deleteMany({ where: { userId: { in: ids } } });
  await prisma.refreshToken.deleteMany({ where: { userId: { in: ids } } });
  await prisma.user.deleteMany({ where: { id: { in: ids } } }); // appareils : en cascade
  await prisma.$disconnect();
});

decrireSurBaseLocale('appareils de notification (I12)', () => {
  it('un téléphone repris par un autre compte ne reçoit plus pour le précédent', async () => {
    await svc.registerToken(comptes.a, jeton('partage'), 'android');
    await svc.registerToken(comptes.b, jeton('partage'), 'android');

    const r = await svc.sendToUser(comptes.a, message);
    expect(r).toMatchObject({ success: false, reason: 'no_token' });
    expect(mockLots.flat()).not.toContain(jeton('partage'));

    await svc.sendToUser(comptes.b, message);
    expect(mockLots).toEqual([[jeton('partage')]]);
  });

  it('un compte reçoit sur chacun de ses appareils', async () => {
    await svc.registerToken(comptes.a, jeton('a1'), 'android');
    await svc.registerToken(comptes.a, jeton('a2'), 'ios');

    const r = await svc.sendToUser(comptes.a, message);
    expect(r).toMatchObject({ success: true, envoyes: 2 });
    expect(mockLots.flat().sort()).toEqual([jeton('a1'), jeton('a2')]);
  });

  it('un jeton déclaré mort est oublié ; l\'envoi réussit par les autres', async () => {
    mockMorts.add(jeton('a2'));
    const r = await svc.sendToUser(comptes.a, message);
    expect(r).toMatchObject({ success: true, envoyes: 1 });
    expect(await appareilsDe(comptes.a)).toEqual([jeton('a1')]);
  });

  it('tous les appareils morts : l\'envoi est un échec, pas un succès', async () => {
    mockMorts.add(jeton('a1'));
    const r = await svc.sendToUser(comptes.a, message);
    expect(r).toMatchObject({ success: false });
    expect(await appareilsDe(comptes.a)).toEqual([]);
  });

  it(`au-delà de ${APPAREILS_PAR_COMPTE} appareils, les moins récemment vus partent`, async () => {
    const heure = 3600_000;
    await prisma.appareilNotification.createMany({
      data: Array.from({ length: APPAREILS_PAR_COMPTE }, (_, i) => ({
        userId: comptes.c, jeton: jeton(`c${i}`), vuLe: new Date(Date.now() - (i + 1) * heure),
      })),
    });
    await svc.registerToken(comptes.c, jeton('c-neuf'), 'android');

    const restants = await appareilsDe(comptes.c);
    expect(restants).toHaveLength(APPAREILS_PAR_COMPTE);
    expect(restants).toContain(jeton('c-neuf'));
    // Le plus ancien — vu il y a dix heures — est celui qui part.
    expect(restants).not.toContain(jeton(`c${APPAREILS_PAR_COMPTE - 1}`));
  });

  it('se déconnecter d\'une session détache son appareil, pas les autres', async () => {
    await svc.registerToken(comptes.a, jeton('d1'), 'android');
    await svc.registerToken(comptes.a, jeton('d2'), 'android');
    const { refresh_token } = await (auth as any)._generateTokens(comptes.a);

    await auth.logout(comptes.a, refresh_token, jeton('d1'));
    expect(await appareilsDe(comptes.a)).toEqual([jeton('d2')]);
  });

  it('sans refresh token, toutes les sessions ferment, et tous les appareils avec', async () => {
    await auth.logout(comptes.a, undefined);
    expect(await appareilsDe(comptes.a)).toEqual([]);
  });

  it('une campagne compte les personnes atteintes, pas les appareils', async () => {
    // b : trois appareils, deux qui reçoivent et un mort — une personne
    // atteinte, pas deux. c : que des morts.
    await prisma.appareilNotification.deleteMany({ where: { userId: { in: [comptes.b, comptes.c] } } });
    for (const n of ['b1', 'b2', 'b3']) await svc.registerToken(comptes.b, jeton(n), 'android');
    await svc.registerToken(comptes.c, jeton('c1'), 'android');
    mockMorts.add(jeton('b3'));
    mockMorts.add(jeton('c1'));

    // Le segment réduit aux comptes du banc : les campagnes écrivent dans
    // l'historique de chaque destinataire, on n'en laisse pas aux autres.
    const cibles = await prisma.user.findMany({
      where: { id: { in: [comptes.b, comptes.c] } },
      select: { id: true, notificationPrefs: true, appareils: { select: { jeton: true } } },
    });
    jest.spyOn(svc as any, '_reachableUsers').mockResolvedValueOnce(cibles);

    const r = await svc.sendToSegment('all', message);
    expect(r).toMatchObject({ sent: 1, failed: 1, pruned: 2 });
    expect(await appareilsDe(comptes.b)).toEqual([jeton('b1'), jeton('b2')]);
    expect(await appareilsDe(comptes.c)).toEqual([]);
  });
});
