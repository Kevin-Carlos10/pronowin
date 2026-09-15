import axios from 'axios';

import { IapService, identifiantTransactionApple } from '../services/iap.service';

jest.mock('axios');
jest.mock('../lib/prisma', () => ({ prisma: {} }));

/**
 * Ce que le mobile envoie, et ce qu'Apple attend.
 *
 * Les deux stores n'envoient pas la même nature de valeur, et le code faisait
 * comme si. Sur Android, `serverVerificationData` **est** le `purchaseToken` —
 * exactement ce que l'API Google attend. Sur iOS, le même champ porte le reçu
 * App Store encodé en base64 (StoreKit 1), ou la représentation JWS de la
 * transaction (StoreKit 2). Ni l'un ni l'autre n'est un identifiant de
 * transaction, et c'est un identifiant qu'Apple attend dans le chemin de
 * `/inApps/v1/subscriptions/{transactionId}`.
 *
 * Le mobile envoyait donc le reçu entier. Apple répondait 404, le backend
 * tentait l'autre environnement, obtenait 404 aussi, et concluait
 * « Transaction introuvable chez Apple ». Aucun achat iOS n'aurait pu être
 * validé — et le message n'aurait désigné ni la cause ni le responsable,
 * pendant que l'acheteur était débité.
 *
 * Ce banc fige les trois formes possibles et ce qu'on en fait.
 */

/** Fabrique un JWS Apple : en-tête, charge, signature (non vérifiée ici). */
function jws(charge: Record<string, unknown>): string {
  const b64 = (o: unknown) =>
    Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b64({ alg: 'ES256' })}.${b64(charge)}.signature-non-verifiee`;
}

describe('l\'identifiant de transaction Apple', () => {
  it('accepte un identifiant tel quel', () => {
    // Ce que le mobile envoie désormais : `purchaseID`.
    expect(identifiantTransactionApple('2000000912345678'))
      .toBe('2000000912345678');
  });

  it('tolère les espaces autour', () => {
    expect(identifiantTransactionApple('  2000000912345678 \n'))
      .toBe('2000000912345678');
  });

  it('extrait l\'identifiant d\'un JWS StoreKit 2', () => {
    // Pour que passer à StoreKit 2 un jour ne casse pas la validation.
    expect(identifiantTransactionApple(jws({
      transactionId: '2000000987654321',
      originalTransactionId: '2000000111111111',
      productId: 'com.pronowin.premium.monthly',
    }))).toBe('2000000987654321');
  });

  it('retombe sur l\'identifiant d\'origine si la transaction manque', () => {
    expect(identifiantTransactionApple(jws({
      originalTransactionId: '2000000111111111',
    }))).toBe('2000000111111111');
  });

  it('refuse un reçu StoreKit 1 en nommant la cause', () => {
    // C'est exactement ce que le mobile envoyait. Le message doit dire ce
    // qu'on attendait — « Transaction introuvable » envoyait chercher du côté
    // d'Apple un défaut qui était chez nous.
    const recuStoreKit1 = Buffer.from('a'.repeat(3000)).toString('base64');

    expect(() => identifiantTransactionApple(recuStoreKit1))
      .toThrow(/identifiant de transaction/i);
  });

  it('refuse un JWS sans identifiant', () => {
    expect(() => identifiantTransactionApple(jws({ productId: 'x' })))
      .toThrow(/identifiant de transaction/i);
  });

  it('refuse une valeur vide', () => {
    expect(() => identifiantTransactionApple('   ')).toThrow(/vide/i);
  });
});

/**
 * La fonction ci-dessus ne sert à rien si `verifyApple` ne l'appelle pas.
 *
 * C'est le genre de garde qu'on retire par inadvertance en refactorant : le
 * banc des formes resterait vert pendant que la requête repartirait avec le
 * reçu entier dans l'URL. On regarde donc l'adresse réellement appelée.
 */
describe('l\'adresse interrogée chez Apple', () => {
  const service = new IapService();

  /** Réponse minimale d'Apple, avec le JWS de transaction attendu. */
  const reponseApple = (transactionId: string) => {
    const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const info = b64({
      transactionId,
      originalTransactionId: transactionId,
      productId: 'com.pronowin.premium.monthly',
      expiresDate: Date.now() + 30 * 86_400_000,
      environment: 'Production',
    });
    return { data: { data: [{ lastTransactions: [{
      status: 1, signedTransactionInfo: `entete.${info}.signature`,
    }] }] } };
  };

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(service as any, '_appleToken').mockReturnValue('jeton-de-banc');
  });

  it('porte l\'identifiant extrait, jamais le reçu envoyé', async () => {
    const recuStoreKit1 = Buffer.from('x'.repeat(2000)).toString('base64');
    (axios.get as jest.Mock).mockResolvedValue(reponseApple('2000000912345678'));

    // Un reçu StoreKit 1 n'est pas exploitable : l'appel doit être refusé
    // AVANT toute requête, et non parti avec le reçu dans le chemin.
    await expect(service.verifyApple(recuStoreKit1)).rejects
      .toThrow(/identifiant de transaction/i);
    expect(axios.get).not.toHaveBeenCalled();
  });

  it('interroge Apple avec l\'identifiant quand il est exploitable', async () => {
    (axios.get as jest.Mock).mockResolvedValue(reponseApple('2000000912345678'));

    const v = await service.verifyApple('2000000912345678');

    expect(v.transactionId).toBe('2000000912345678');
    const url = (axios.get as jest.Mock).mock.calls[0][0] as string;
    expect(url).toContain('/inApps/v1/subscriptions/2000000912345678');
  });
});
