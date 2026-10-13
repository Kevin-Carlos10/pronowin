/**
 * Paiement Mobile Money par GeniusPay (13 octobre 2026).
 *
 * Ce qui doit tenir : rien n'est accordé sur la seule parole de l'application
 * ou du webhook ; le Premium ne l'est qu'une fois, quel que soit le nombre de
 * confirmations ; un paiement non conforme (montant, environnement) n'ouvre
 * rien ; en test, seuls les comptes testeurs voient le paiement.
 */
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { /* hors sujet */ } },
}));
import crypto from 'crypto';
import { prisma } from '../lib/prisma';
import {
  configGeniusPay, creerPaiement, geniusPayHttp, geniusPayOuvert, rapprocherPaiement,
  signatureValide, traiterWebhook,
} from '../services/geniuspay.service';
import { decrireSurBaseLocale } from './aides/base_locale';

const SANDBOX = { GENIUSPAY_PUBLIC_KEY: 'pk_sandbox_abc', GENIUSPAY_SECRET_KEY: 'sk_sandbox_def' };

describe('configuration', () => {
  it('sans clés, ou avec des clés de deux environnements, rien n\'est proposé', () => {
    expect(configGeniusPay({})).toBeNull();
    expect(configGeniusPay({ ...SANDBOX, GENIUSPAY_SECRET_KEY: 'sk_live_x' })).toBeNull();
    expect(configGeniusPay({ GENIUSPAY_PUBLIC_KEY: 'cle', GENIUSPAY_SECRET_KEY: 'secret' })).toBeNull();
  });
  it('l\'environnement suit le préfixe des clés', () => {
    expect(configGeniusPay(SANDBOX)?.environnement).toBe('sandbox');
    expect(configGeniusPay({ GENIUSPAY_PUBLIC_KEY: 'pk_live_a', GENIUSPAY_SECRET_KEY: 'sk_live_b' })?.environnement)
      .toBe('live');
  });
  it('en test, seuls les comptes testeurs voient le paiement ; en réel, tous', () => {
    const test = configGeniusPay({ ...SANDBOX, GENIUSPAY_TESTEURS: ' Moi@Exemple.com , u-2 ' });
    expect(geniusPayOuvert(test, { id: 'u-1', email: 'moi@exemple.com' })).toBe(true);
    expect(geniusPayOuvert(test, { id: 'u-2' })).toBe(true);
    expect(geniusPayOuvert(test, { id: 'u-3', email: 'autre@exemple.com' })).toBe(false);
    const reel = configGeniusPay({ GENIUSPAY_PUBLIC_KEY: 'pk_live_a', GENIUSPAY_SECRET_KEY: 'sk_live_b' });
    expect(geniusPayOuvert(reel, { id: 'u-3' })).toBe(true);
    expect(geniusPayOuvert(null, { id: 'u-1' })).toBe(false);
  });
});

describe('signature du webhook', () => {
  const secret = 'whsec_sandbox_test';
  const corps = Buffer.from('{"event":"payment.success","data":{"reference":"MTX-1"}}');
  const maintenant = 1_800_000_000_000;
  const t = String(maintenant / 1000);
  const hmac = crypto.createHmac('sha256', secret).update(`${t}.`).update(corps).digest();

  it('accepte la signature du corps reçu, en hexadécimal ou en base64', () => {
    expect(signatureValide(secret, t, hmac.toString('hex'), corps, maintenant)).toBe(true);
    expect(signatureValide(secret, t, 'sha256=' + hmac.toString('hex'), corps, maintenant)).toBe(true);
    expect(signatureValide(secret, t, hmac.toString('base64'), corps, maintenant)).toBe(true);
  });
  it('refuse un autre secret, un corps modifié, un horodatage trop ancien', () => {
    expect(signatureValide('whsec_autre', t, hmac.toString('hex'), corps, maintenant)).toBe(false);
    expect(signatureValide(secret, t, hmac.toString('hex'), Buffer.from(corps.toString() + ' '), maintenant)).toBe(false);
    expect(signatureValide(secret, t, hmac.toString('hex'), corps, maintenant + 301_000)).toBe(false);
    expect(signatureValide(secret, undefined, hmac.toString('hex'), corps, maintenant)).toBe(false);
    expect(signatureValide('', t, hmac.toString('hex'), corps, maintenant)).toBe(false);
  });
});

decrireSurBaseLocale('paiements avec PostgreSQL', () => {
  const marque = `banc-geniuspay-${Date.now()}`;
  const comptes: string[] = [];
  const envAvant = { ...process.env };
  let reponses: Record<string, any>;
  let creations: any[];

  async function compte(suffixe: string) {
    const u = await prisma.user.create({ data: {
      pseudo: `${marque}-${suffixe}`, referralCode: `G${suffixe}${Date.now()}`.slice(-14).toUpperCase(),
      email: `${marque}-${suffixe}@example.invalid`,
    } });
    comptes.push(u.id);
    return u;
  }
  /** Ce que GeniusPay répondra à la relecture de la référence. */
  function paye(reference: string, champs: Record<string, unknown> = {}) {
    reponses[reference] = { reference, amount: 6000, currency: 'XOF', status: 'completed',
      environment: 'sandbox', payment_method: 'orange_money', fees: 160, net_amount: 5840, ...champs };
  }
  const abonnements = (userId: string) =>
    prisma.subscription.findMany({ where: { userId, paymentMethod: 'geniuspay' } });

  beforeAll(() => {
    jest.spyOn(geniusPayHttp, 'creer').mockImplementation(async (_cfg, corps) => {
      creations.push(corps);
      const reference = `MTX-${crypto.randomBytes(5).toString('hex').toUpperCase()}`;
      return { reference, status: 'pending', environment: 'sandbox',
        checkout_url: `https://pay.genius.ci/checkout/${reference}` };
    });
    jest.spyOn(geniusPayHttp, 'lire').mockImplementation(async (_cfg, reference) =>
      reponses[reference] ?? { reference, status: 'pending', amount: 6000, environment: 'sandbox' });
  });
  beforeEach(() => {
    reponses = {}; creations = [];
    Object.assign(process.env, SANDBOX, { GENIUSPAY_WEBHOOK_SECRET: 'whsec_sandbox_banc' });
  });
  afterAll(async () => {
    process.env = envAvant;
    await prisma.paiementGeniusPay.deleteMany({ where: { userId: { in: comptes } } });
    await prisma.subscription.deleteMany({ where: { userId: { in: comptes } } });
    await prisma.user.deleteMany({ where: { id: { in: comptes } } });
    await prisma.$disconnect();
  });

  it('ouvre un paiement au prix du serveur, avec sa référence et son retour', async () => {
    const u = await compte('ouvre');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const p = await creerPaiement(u.id, 'premium_monthly');
    expect(p.checkout_url).toMatch(/^https:\/\/pay\.genius\.ci\/checkout\/MTX-/);
    expect(creations[0]).toMatchObject({ amount: 6000, currency: 'XOF',
      metadata: { paiement_id: p.id, user_id: u.id, plan: 'premium_monthly' } });
    expect(creations[0].success_url).toContain(`/paiement/retour?p=${p.id}`);
    const ligne = await prisma.paiementGeniusPay.findUniqueOrThrow({ where: { id: p.id } });
    expect(ligne).toMatchObject({ reference: p.reference, statut: 'pending', environnement: 'sandbox', montant: 6000 });
    await expect(creerPaiement(u.id, 'premium_a_vie')).rejects.toMatchObject({ statut: 400 });
  });

  it('en test, un compte qui n\'est pas testeur ne peut pas ouvrir de paiement', async () => {
    const u = await compte('intrus');
    process.env.GENIUSPAY_TESTEURS = 'quelqu-un-d-autre';
    await expect(creerPaiement(u.id, 'premium_monthly')).rejects.toMatchObject({ statut: 503 });
    expect(creations).toHaveLength(0);
  });

  it('payé et conforme : le Premium est accordé une seule fois, même confirmé trois fois', async () => {
    const u = await compte('paye');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const p = await creerPaiement(u.id, 'premium_monthly');
    expect((await rapprocherPaiement(p.id))?.premiumAccordeLe).toBeNull(); // encore en attente
    paye(p.reference);
    await Promise.all([rapprocherPaiement(p.id), rapprocherPaiement(p.id), rapprocherPaiement(p.id)]);
    expect(await abonnements(u.id)).toHaveLength(1);
    expect((await abonnements(u.id))[0].amountPaid).toBe(6000);
    const ligne = await prisma.paiementGeniusPay.findUniqueOrThrow({ where: { id: p.id } });
    expect(ligne).toMatchObject({ statut: 'completed', moyen: 'orange_money', frais: 160, montantNet: 5840 });
    const apres = await prisma.user.findUniqueOrThrow({ where: { id: u.id } });
    expect(apres.subscriptionPlan).toBe('premium');
    const jours = (apres.subscriptionExpiresAt!.getTime() - Date.now()) / 86_400_000;
    expect(jours).toBeGreaterThan(29);
    expect(jours).toBeLessThan(31);
  });

  it('l\'annuel ouvre 365 jours', async () => {
    const u = await compte('annuel');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const p = await creerPaiement(u.id, 'premium_annual');
    expect(creations[0].amount).toBe(54000);
    paye(p.reference, { amount: 54000 });
    await rapprocherPaiement(p.id);
    const apres = await prisma.user.findUniqueOrThrow({ where: { id: u.id } });
    expect((apres.subscriptionExpiresAt!.getTime() - Date.now()) / 86_400_000).toBeGreaterThan(364);
  });

  it('payé mais pas ce qui était demandé : rien n\'est accordé', async () => {
    const u = await compte('ecart');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const montant = await creerPaiement(u.id, 'premium_monthly');
    paye(montant.reference, { amount: 200 });
    expect((await rapprocherPaiement(montant.id))?.statut).toBe('anomalie');
    const environnement = await creerPaiement(u.id, 'premium_monthly');
    paye(environnement.reference, { environment: 'live' });
    expect((await rapprocherPaiement(environnement.id))?.statut).toBe('anomalie');
    expect(await abonnements(u.id)).toHaveLength(0);
  });

  it('échoué : le statut suit, rien n\'est accordé', async () => {
    const u = await compte('echec');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const p = await creerPaiement(u.id, 'premium_monthly');
    paye(p.reference, { status: 'failed' });
    expect((await rapprocherPaiement(p.id))?.statut).toBe('failed');
    expect(await abonnements(u.id)).toHaveLength(0);
  });

  it('le webhook signé déclenche la confirmation ; mal signé, il est ignoré', async () => {
    const u = await compte('webhook');
    process.env.GENIUSPAY_TESTEURS = u.id;
    const p = await creerPaiement(u.id, 'premium_monthly');
    paye(p.reference);
    const corps = Buffer.from(JSON.stringify({ event: 'payment.success', data: { reference: p.reference } }));
    const t = String(Math.floor(Date.now() / 1000));
    const signe = (secret: string) =>
      crypto.createHmac('sha256', secret).update(`${t}.`).update(corps).digest('hex');

    expect(await traiterWebhook({ 'x-webhook-timestamp': t, 'x-webhook-signature': signe('faux') }, corps)).toBe(401);
    expect(await abonnements(u.id)).toHaveLength(0);

    expect(await traiterWebhook({ 'x-webhook-timestamp': t, 'x-webhook-signature': signe('whsec_sandbox_banc') }, corps))
      .toBe(200);
    expect(await abonnements(u.id)).toHaveLength(1);
  });
});
