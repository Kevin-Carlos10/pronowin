/**
 * Les achats App Store et Google Play, vus depuis le panneau.
 *
 * Aucun écran ne les montrait : une vente Apple ne se voyait que dans App
 * Store Connect, et un abonnement payé mais pas activé ne se découvrait que
 * par la réclamation de son acheteur.
 */
import { prisma } from '../lib/prisma';
import {
  etatDe, renouvellementDe, montantDe, typeDeNotification, resumeAchatsStore,
} from '../services/achats_store_admin.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const JOUR = 86_400_000;
const dans = (j: number) => new Date(Date.now() + j * JOUR);

describe('lecture des états', () => {
  it('actif, résilié, impayé, expiré, remboursé', () => {
    expect(etatDe('active', dans(10), true)).toBe('actif');
    expect(etatDe('active', dans(10), false)).toBe('resilie');   // Apple : renouvellement coupé
    expect(etatDe('canceled', dans(10), null)).toBe('resilie');  // Google : court jusqu'au terme
    expect(etatDe('billing_retry', dans(10), true)).toBe('impaye');
    expect(etatDe('active', dans(-1), true)).toBe('expire');
    expect(etatDe('revoked', dans(10), true)).toBe('rembourse');
  });

  it('le renouvellement et le prix, quand le store les donne', () => {
    expect(renouvellementDe('apple', { renewal: { autoRenewStatus: 0 } })).toBe(false);
    expect(renouvellementDe('apple', {})).toBeNull();
    expect(renouvellementDe('google', { lineItems: [{ autoRenewingPlan: { autoRenewEnabled: true } }] })).toBe(true);
    expect(montantDe('apple', { transaction: { price: 14990, currency: 'USD' } })).toBe('14.99 USD');
    expect(montantDe('google', {})).toBeNull();
  });

  it('le type des notifications, depuis la charge telle que reçue', () => {
    const jws = ['e30', Buffer.from(JSON.stringify({ notificationType: 'DID_RENEW', subtype: 'BILLING_RECOVERY' })).toString('base64url'), 'sig'].join('.');
    expect(typeDeNotification('apple', { signedPayload: jws })).toBe('DID_RENEW · BILLING_RECOVERY');
    const data = Buffer.from(JSON.stringify({ subscriptionNotification: { notificationType: 12 } })).toString('base64');
    expect(typeDeNotification('google', { message: { data } })).toBe('REVOKED');
    expect(typeDeNotification('apple', { signedPayload: 'pas-un-jws' })).toBe('illisible');
  });
});

const marque = `banc-store-${Date.now()}`;
const comptes: string[] = [];
async function compte(suffixe: string, premium: boolean) {
  const u = await prisma.user.create({ data: {
    pseudo: `${marque}-${suffixe}`, referralCode: `${suffixe}${Date.now()}`.slice(-14).toUpperCase(),
    subscriptionPlan: premium ? 'premium' : 'free', subscriptionExpiresAt: premium ? dans(20) : null,
  } });
  comptes.push(u.id);
  return u.id;
}
async function achat(userId: string, transactionId: string, original: string, p: Partial<{
  status: string; expiresAt: Date; environment: string; createdAt: Date; productId: string;
}> = {}) {
  await prisma.iapPurchase.create({ data: {
    userId, store: 'apple', productId: p.productId ?? 'com.pronowin.premium.monthly',
    transactionId, originalTransactionId: original,
    expiresAt: p.expiresAt ?? dans(20), status: p.status ?? 'active',
    environment: p.environment ?? 'Production', createdAt: p.createdAt ?? new Date(),
    payload: { renewal: { autoRenewStatus: 1 } },
  } });
}

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.iapPurchase.deleteMany({ where: { userId: { in: comptes } } });
  await prisma.user.deleteMany({ where: { id: { in: comptes } } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('le résumé du panneau', () => {
  it('une ligne par abonnement, les anomalies en tête, les tests à part', async () => {
    const fidele = await compte('fidele', true);
    const oublie = await compte('oublie', false);
    const testeur = await compte('testeur', true);

    // Trois paiements du même abonnement : une seule ligne.
    await achat(fidele, `${marque}-t1`, `${marque}-o1`, { createdAt: new Date(Date.now() - 70 * JOUR), expiresAt: dans(-40) });
    await achat(fidele, `${marque}-t2`, `${marque}-o1`, { createdAt: new Date(Date.now() - 40 * JOUR), expiresAt: dans(-10) });
    await achat(fidele, `${marque}-t3`, `${marque}-o1`, { createdAt: new Date(Date.now() - 10 * JOUR), expiresAt: dans(20) });
    // Payé chez Apple, compte resté gratuit : l'anomalie à traiter.
    await achat(oublie, `${marque}-t4`, `${marque}-o4`);
    // Un achat TestFlight.
    await achat(testeur, `${marque}-t5`, `${marque}-o5`, { environment: 'Sandbox' });

    const r = await resumeAchatsStore({ recherche: marque });
    const lignes = r.abonnements.filter((a) => a.compte.pseudo.startsWith(marque));
    expect(lignes.map((a) => a.compte.pseudo)).toEqual([`${marque}-oublie`, `${marque}-fidele`]);
    expect(lignes[0].anomalie).toBe(true);
    expect(lignes[1]).toMatchObject({ paiements: 3, etat: 'actif', anomalie: false, transaction: `${marque}-t3` });

    const avecTests = await resumeAchatsStore({ recherche: marque, tests: true });
    expect(avecTests.abonnements.some((a) => a.test && a.compte.pseudo === `${marque}-testeur`)).toBe(true);

    const anomalies = await resumeAchatsStore({ etat: 'anomalie', recherche: marque });
    expect(anomalies.abonnements.map((a) => a.compte.pseudo)).toEqual([`${marque}-oublie`]);
  });
});
