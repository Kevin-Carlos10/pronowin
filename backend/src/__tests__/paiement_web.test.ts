/**
 * Paiement Mobile Money depuis le site (pronowin.space/premium), 13 octobre
 * 2026.
 *
 * Ce qui doit tenir : la page ne dit pas qui est inscrit ; le code vérifié
 * ouvre un jeton qui ne sert qu'à payer — jamais une session de
 * l'application ; le paiement suit le même chemin que dans l'app, avec un
 * retour vers la page du site.
 */
const mockCodes: Array<{ email: string; code: string }> = [];
jest.mock('../services/email.service', () => ({
  sendEmailOtp: async (email: string, code: string) => { mockCodes.push({ email, code }); },
}));
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { /* hors sujet */ } },
}));
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { prisma } from '../lib/prisma';
import { geniusPayHttp } from '../services/geniuspay.service';
import {
  envoyerCode, lireJetonPaiement, payer, signerJetonPaiement, suivre, verifierCode,
} from '../services/paiement_web.service';
import { decrireSurBaseLocale } from './aides/base_locale';

describe('jeton de paiement', () => {
  const avant = process.env.JWT_SECRET;
  beforeAll(() => { process.env.JWT_SECRET = avant ?? 'secret-de-banc'; });
  afterAll(() => { process.env.JWT_SECRET = avant; });

  it('ne sert qu\'à payer : une session de l\'application le refuse, et inversement', () => {
    const jeton = signerJetonPaiement('u-1');
    expect(lireJetonPaiement(jeton)).toBe('u-1');
    // Le contrôle des sessions vérifie avec JWT_SECRET seul.
    expect(() => jwt.verify(jeton, process.env.JWT_SECRET!)).toThrow();
    const session = jwt.sign({ userId: 'u-1', sessionId: 's' }, process.env.JWT_SECRET!);
    expect(lireJetonPaiement(session)).toBeNull();
    expect(lireJetonPaiement(undefined)).toBeNull();
    expect(lireJetonPaiement('n-importe-quoi')).toBeNull();
  });
});

decrireSurBaseLocale('paiement depuis le site, avec PostgreSQL', () => {
  const marque = `banc-web-${Date.now()}`;
  const comptes: string[] = [];
  const envAvant = { ...process.env };
  const creations: any[] = [];

  beforeAll(() => {
    Object.assign(process.env, {
      GENIUSPAY_PUBLIC_KEY: 'sk_sandbox_banc', GENIUSPAY_SECRET_KEY: 'secret-de-banc-123456',
    });
    jest.spyOn(geniusPayHttp, 'creer').mockImplementation(async (_cfg, corps) => {
      creations.push(corps);
      const reference = `MTX-${crypto.randomBytes(5).toString('hex').toUpperCase()}`;
      return { reference, status: 'pending', environment: 'sandbox', checkout_url: `https://geniuspay.ci/checkout/${reference}` };
    });
    jest.spyOn(geniusPayHttp, 'lire').mockImplementation(async (_cfg, reference) =>
      ({ reference, status: 'completed', amount: 6000, currency: 'XOF', environment: 'sandbox' }));
  });
  afterAll(async () => {
    process.env = envAvant;
    await prisma.paiementGeniusPay.deleteMany({ where: { userId: { in: comptes } } });
    await prisma.subscription.deleteMany({ where: { userId: { in: comptes } } });
    await prisma.otpCode.deleteMany({ where: { phoneNumber: { startsWith: marque } } });
    await prisma.user.deleteMany({ where: { id: { in: comptes } } });
    await prisma.$disconnect();
  });

  async function compte(suffixe: string) {
    const u = await prisma.user.create({ data: {
      pseudo: `${marque}-${suffixe}`, referralCode: `W${suffixe}${Date.now()}`.slice(-14).toUpperCase(),
      email: `${marque}-${suffixe}@example.invalid`,
    } });
    comptes.push(u.id);
    return u;
  }

  it('une adresse inconnue reçoit la même réponse, sans code envoyé', async () => {
    const connu = await compte('connu');
    mockCodes.length = 0;
    const r1 = await envoyerCode(`${marque}-personne@example.invalid`);
    const r2 = await envoyerCode(connu.email!.toUpperCase());
    expect(r1).toEqual(r2);
    expect(mockCodes.map((c) => c.email)).toEqual([connu.email]);
    await expect(envoyerCode('pas-une-adresse')).rejects.toMatchObject({ statut: 400 });
  });

  it('le bon code ouvre un jeton de paiement, une seule fois ; un mauvais code est refusé', async () => {
    const u = await compte('code');
    mockCodes.length = 0;
    await envoyerCode(u.email);
    const { code } = mockCodes[0];
    await expect(verifierCode(u.email, '000000' === code ? '111111' : '000000')).rejects.toMatchObject({ statut: 400 });
    const ok = await verifierCode(u.email, code);
    expect(lireJetonPaiement(ok.jeton)).toBe(u.id);
    expect(ok.compte.pseudo).toBe(u.pseudo);
    await expect(verifierCode(u.email, code)).rejects.toMatchObject({ statut: 400 });
  });

  it('payer depuis le site : retour vers la page Premium, Premium accordé au compte', async () => {
    const u = await compte('paye');
    process.env.GENIUSPAY_TESTEURS = u.email!;
    const p = await payer(u.id, 'premium_monthly');
    expect(creations.at(-1).success_url).toContain(`/premium?p=${p.id}`);
    expect(creations.at(-1).metadata).toMatchObject({ user_id: u.id, plan: 'premium_monthly' });
    const etat = await suivre(u.id, p.id);
    expect(etat).toMatchObject({ statut: 'completed', premium_active: true });
    expect(etat.expire_le).not.toBeNull();
    // Un autre compte ne lit pas ce paiement.
    const autre = await compte('autre');
    await expect(suivre(autre.id, p.id)).rejects.toMatchObject({ statut: 404 });
  });
});
