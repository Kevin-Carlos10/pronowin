
jest.mock('../services/referral.service', () => ({ ReferralService: class { async triggerCommissions() {} } }));
jest.mock('../services/notification.service', () => ({ NotificationService: class { async sendToUser() {} } }));
import { prisma } from '../lib/prisma';
import { IapService, identifiantsAchat, VerifiedPurchase } from '../services/iap.service';
import { decrireSurBaseLocale, BASE_LOCALE } from './aides/base_locale';

const svc = new IapService();
const marque = 'attribution-' + Date.now();
const comptes: string[] = [];
async function compte() {
  const u = await prisma.user.create({ data: { pseudo: marque + comptes.length, referralCode: marque + comptes.length } });
  comptes.push(u.id); return u.id;
}
function v(id: string, store: 'apple' | 'google' = 'google', extra: Partial<VerifiedPurchase> = {}): VerifiedPurchase {
  return { store, productId: 'com.pronowin.premium.monthly', transactionId: marque + id,
    originalTransactionId: marque + id, expiresAt: new Date(Date.now() + 86400000),
    status: 'active', environment: 'Production', payload: {}, ...extra };
}
afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.iapPurchase.deleteMany({ where: { userId: { in: comptes } } });
  await prisma.subscription.deleteMany({ where: { userId: { in: comptes } } });
  await prisma.user.deleteMany({ where: { id: { in: comptes } } });
  await prisma.$disconnect();
});
decrireSurBaseLocale('Attribution vérifiée des achats', () => {
  afterEach(() => { delete process.env.IAP_EXIGER_COMPTE_APPLE; });
  it('mode strict : refuse un numéro Apple sans preuve de compte avant le premier octroi', async () => {
    process.env.IAP_EXIGER_COMPTE_APPLE = 'true';
    const a = await compte();
    jest.spyOn(svc, 'verifyApple').mockResolvedValue(v('sans-token', 'apple'));
    await expect(svc.verifyAndRecord({ userId: a, store: 'apple', receipt: '123' })).rejects.toMatchObject({ statut: 409 });
    expect(await prisma.subscription.count({ where: { userId: a } })).toBe(0);
  });
  it('par défaut : un achat Apple sans identifiant est activé, comme avec les versions distribuées', async () => {
    // Aucune version publiée ne transmet encore l'identifiant : refuser ici
    // encaisserait le paiement sans activer le Premium.
    const a = await compte();
    jest.spyOn(svc, 'verifyApple').mockResolvedValue(v('sans-token-compatible', 'apple'));
    await expect(svc.verifyAndRecord({ userId: a, store: 'apple', receipt: '123' })).resolves.toMatchObject({ active: true });
    // Il reste au premier compte : un autre ne peut pas le reprendre.
    const b = await compte();
    await expect(svc.verifyAndRecord({ userId: b, store: 'apple', receipt: '123' })).rejects.toMatchObject({ statut: 409 });
  });
  it('restaure un ancien achat Apple déjà rattaché au même compte', async () => {
    const a = await compte(), achat = v('legacy', 'apple');
    await prisma.iapPurchase.create({ data: { ...achat, userId: a, payload: {} } });
    jest.spyOn(svc, 'verifyApple').mockResolvedValue(achat);
    await expect(svc.verifyAndRecord({ userId: a, store: 'apple', receipt: '123' })).resolves.toMatchObject({ active: true });
  });
  it.each(['apple', 'google'] as const)('%s : contrôle le compte retourné par le store', async store => {
    const a = await compte(), b = await compte();
    const achat = v('binding-' + store, store, { accountBinding: identifiantsAchat(a)[store] });
    jest.spyOn(svc, store === 'apple' ? 'verifyApple' : 'verifyGoogle').mockResolvedValue(achat);
    await expect(svc.verifyAndRecord({ userId: b, store, receipt: 'x' })).rejects.toMatchObject({ statut: 409 });
    await expect(svc.verifyAndRecord({ userId: a, store, receipt: 'x' })).resolves.toMatchObject({ active: true });
  });
  it('deux transactions concurrentes d’une chaîne restent au premier compte', async () => {
    const a = await compte(), b = await compte();
    const chaine = marque + 'chaine';
    jest.spyOn(svc, 'verifyGoogle').mockImplementation(async token =>
      v(token, 'google', { originalTransactionId: chaine }));
    const r = await Promise.allSettled([
      svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'r1' }),
      svc.verifyAndRecord({ userId: b, store: 'google', receipt: 'r2' }),
    ]);
    expect(r.filter(x => x.status === 'fulfilled')).toHaveLength(1);
    expect(await prisma.subscription.count({ where: { userId: { in: [a,b] } } })).toBe(1);
  });
  it('Google : un changement de formule garde le titulaire du jeton lié', async () => {
    const a = await compte(), b = await compte();
    const ancien = v('ancien');
    jest.spyOn(svc, 'verifyGoogle').mockResolvedValue(ancien);
    await svc.verifyAndRecord({ userId: a, store: 'google', receipt: 'x' });
    jest.spyOn(svc, 'verifyGoogle').mockResolvedValue(v('nouveau', 'google', { linkedPurchaseToken: ancien.originalTransactionId }));
    await expect(svc.verifyAndRecord({ userId: b, store: 'google', receipt: 'y' })).rejects.toMatchObject({ statut: 409 });
  });
});
