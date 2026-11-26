/**
 * Les préférences de l'alerte de couverture (26 novembre 2026) : un
 * interrupteur, et un seuil de 30, 50 ou 70 % — rien d'autre.
 */
import { prisma } from '../lib/prisma';
import { updateNotificationPrefs } from '../controllers/profile.controller';

const reponse = () => { const r: any = { json: jest.fn() }; r.status = jest.fn(() => r); return r; };

beforeEach(() => {
  jest.spyOn(prisma.user, 'findUnique').mockResolvedValue({ notificationPrefs: { match: true } } as any);
  jest.spyOn(prisma.user, 'update').mockResolvedValue({} as any);
});
afterEach(() => jest.restoreAllMocks());

it('l\'interrupteur et le seuil s\'enregistrent avec le reste', async () => {
  const r = reponse();
  await updateNotificationPrefs({ userId: 'u1', body: { couverture: false, seuil_couverture: 70 } } as any, r);
  expect(r.json).toHaveBeenCalledWith({ success: true, notification_prefs: { match: true, couverture: false, seuil_couverture: 70 } });
});

it('un seuil hors de la liste est ignoré', async () => {
  const r = reponse();
  await updateNotificationPrefs({ userId: 'u1', body: { couverture: true, seuil_couverture: 45 } } as any, r);
  expect(r.json.mock.calls[0][0].notification_prefs).toEqual({ match: true, couverture: true });
  const r2 = reponse();
  await updateNotificationPrefs({ userId: 'u1', body: { seuil_couverture: 99 } } as any, r2);
  expect(r2.status).toHaveBeenCalledWith(400);
});
