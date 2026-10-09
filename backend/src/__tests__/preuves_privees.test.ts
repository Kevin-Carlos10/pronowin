/**
 * Les captures de paiement sont privées.
 *
 * Constat S10 de l'audit du 24 septembre 2026 : elles partaient sur S3 en
 * `public-read`, à une adresse publique permanente — numéros Mobile Money,
 * montants, noms. `submitProof` acceptait aussi une adresse de capture fournie
 * par le client, sans vérifier qu'elle venait d'un envoi autorisé. Et le type
 * annoncé dans l'en-tête `data:` était cru sur parole.
 */
process.env.AWS_REGION = 'eu-west-1';
process.env.AWS_S3_BUCKET = 'banc-bucket';
process.env.AWS_ACCESS_KEY_ID = 'AKIABANCDESSAI000000';
process.env.AWS_SECRET_ACCESS_KEY = 'secret-de-banc-secret-de-banc-0000000000';

const envois: any[] = [];
jest.mock('@aws-sdk/client-s3', () => {
  const reel = jest.requireActual('@aws-sdk/client-s3');
  return {
    ...reel,
    S3Client: class extends reel.S3Client {
      async send(commande: any) { envois.push(commande); return {}; }
    },
  };
});

jest.mock('../lib/prisma', () => ({
  prisma: {
    subscriptionProof: { findFirst: jest.fn(async () => null), create: jest.fn(async ({ data }: any) => ({ id: 'p1', ...data })) },
    user: { findUnique: jest.fn(async () => ({ id: 'u1' })) },
  },
}));
jest.mock('../services/notification.service', () => ({
  NotificationService: class { async sendToUser() { return {}; } },
}));
jest.mock('../services/referral.service', () => ({
  ReferralService: class { async triggerCommissions() { return {}; } },
}));
jest.mock('../services/payment_method.service', () => ({ listerPubliques: async () => [] }));
jest.mock('../middleware/profile.middleware', () => ({ estProfilComplet: async () => true }));

import { S3Service, cleDe } from '../services/s3.service';
import { SubscriptionService } from '../services/subscription.service';

const JPEG = 'data:image/jpeg;base64,' + Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]).toString('base64');
const HOTE = 'https://banc-bucket.s3.eu-west-1.amazonaws.com';

describe('dépôt des images', () => {
  const s3 = new S3Service();

  it('une capture de paiement est déposée sans accès public', async () => {
    envois.length = 0;
    await s3.uploadImage({ base64: JPEG, folder: 'proofs', userId: 'u1' });
    expect(envois[0].input.Key).toMatch(/^proofs\/u1\//);
    expect(envois[0].input.ACL).toBeUndefined();
  });

  it('un avatar reste public', async () => {
    // Contrepartie : l'application affiche les avatars à tout le monde.
    envois.length = 0;
    await s3.uploadImage({ base64: JPEG, folder: 'avatars', userId: 'u1' });
    expect(envois[0].input.ACL).toBe('public-read');
  });

  it('un type annoncé que les octets démentent est refusé', async () => {
    const faux = 'data:image/png;base64,' + Buffer.from('<html>pas une image</html>').toString('base64');
    await expect(s3.uploadImage({ base64: faux, folder: 'proofs', userId: 'u1' }))
      .rejects.toMatchObject({ statut: 422 });
    const pdf = 'data:application/pdf;base64,' + Buffer.from('%PDF-1.4').toString('base64');
    await expect(s3.uploadImage({ base64: pdf, folder: 'proofs', userId: 'u1' }))
      .rejects.toMatchObject({ statut: 422 });
  });

  it('l\'envoi direct d\'une preuve ne demande pas non plus d\'accès public', async () => {
    const { uploadUrl } = await s3.getPresignedUrl({
      folder: 'proofs', userId: 'u1', mimeType: 'image/jpeg', expiresIn: 300 });
    expect(uploadUrl).not.toMatch(/x-amz-acl/i);
  });
});

describe('lecture des captures', () => {
  const s3 = new S3Service();

  it('une adresse de notre bucket devient une adresse signée qui expire', async () => {
    const lue = await s3.urlLectureSignee(`${HOTE}/proofs/u1/abc.jpg`, 600);
    expect(lue).toMatch(/X-Amz-Signature=/);
    expect(lue).toMatch(/X-Amz-Expires=600/);
  });

  it('une adresse étrangère n\'est pas signée', async () => {
    expect(await s3.urlLectureSignee('https://ailleurs.example/x.jpg')).toBe('https://ailleurs.example/x.jpg');
  });

  it.each([
    ['https://autre-bucket.s3.eu-west-1.amazonaws.com/proofs/u1/a.jpg', null],
    ['http://banc-bucket.s3.eu-west-1.amazonaws.com/proofs/u1/a.jpg', null],
    // Le chemin est normalisé avant tout contrôle : c'est la cible réelle qui
    // est comparée au dossier du compte.
    [`${HOTE}/proofs/u1/../u2/a.jpg`, 'proofs/u2/a.jpg'],
    [`${HOTE}/proofs/u1/a.jpg`, 'proofs/u1/a.jpg'],
  ])('clé de %s → %s', (url, cle) => {
    expect(cleDe(url)).toBe(cle);
  });
});

describe('adresse de capture fournie par le client', () => {
  const svc = new SubscriptionService();
  const base = {
    userId: 'u1', type: 'payment_screenshot' as const,
    amount: 50000, senderPhone: '+22670000000', planId: 'premium_monthly',
  };

  it.each([
    ['d\'un autre compte', `${HOTE}/proofs/u2/a.jpg`],
    ['d\'un autre site',   'https://exemple.invalid/capture.jpg'],
    ['d\'un autre dossier', `${HOTE}/avatars/u1/a.jpg`],
    ['qui remonte vers un autre compte', `${HOTE}/proofs/u1/../u2/a.jpg`],
  ])('une adresse %s est refusée', async (_c, url) => {
    await expect(svc.submitProof({ ...base, screenshotUrl: url }))
      .rejects.toMatchObject({ statut: 422 });
  });

  it('l\'adresse d\'un envoi direct de ce compte est acceptée', async () => {
    // Contrepartie : sans elle, un service qui refuserait toute adresse
    // passerait les trois points précédents.
    await expect(svc.submitProof({ ...base, screenshotUrl: `${HOTE}/proofs/u1/a.jpg` }))
      .resolves.toBeDefined();
  });
});
