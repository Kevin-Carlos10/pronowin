import axios from 'axios';
import jwt from 'jsonwebtoken';
import { JWT } from 'google-auth-library';
import { prisma } from '../lib/prisma';
import { SubscriptionService } from './subscription.service';
import { NotificationService } from './notification.service';

const notifSvc = new NotificationService();
// Même motif que dans referral.service : instanciation différée pour ne pas
// dépendre de l'ordre de chargement des modules.
let _subSvc: SubscriptionService | null = null;
const subSvc = () => _subSvc ??= new SubscriptionService();

// ─── Catalogue produits ───────────────────────────────────────────────────────

/**
 * Identifiants tels qu'ils devront être créés dans App Store Connect et la
 * Play Console. Les deux stores doivent utiliser exactement ces chaînes.
 *
 * La durée n'est PAS ce qui fixe l'échéance — c'est la date renvoyée par le
 * store qui fait foi. Elle ne sert que de repli si le store ne renvoie rien.
 */
export const IAP_PRODUCTS: Record<string, { plan: string; fallbackDays: number }> = {
  'com.pronowin.premium.monthly': { plan: 'premium', fallbackDays: 30 },
  'com.pronowin.premium.annual':  { plan: 'premium', fallbackDays: 365 },
};

export type IapStoreName = 'apple' | 'google';

/** Forme normalisée, commune aux deux stores. */
export interface VerifiedPurchase {
  store:                 IapStoreName;
  productId:             string;
  transactionId:         string;
  originalTransactionId: string;
  expiresAt:             Date;
  status:                string;
  environment:           string;
  payload:               unknown;
}

// ─── Configuration ────────────────────────────────────────────────────────────

const APPLE = {
  keyId:    process.env.APPLE_IAP_KEY_ID    ?? '',
  issuerId: process.env.APPLE_IAP_ISSUER_ID ?? '',
  bundleId: process.env.APPLE_BUNDLE_ID     ?? 'com.pronowin.app',
  // Clé .p8 téléchargée depuis App Store Connect. Les sauts de ligne sont
  // souvent aplatis en \n littéraux quand la valeur transite par un .env.
  privateKey: (process.env.APPLE_IAP_PRIVATE_KEY ?? '').replace(/\\n/g, '\n'),
};

const GOOGLE = {
  packageName:  process.env.ANDROID_PACKAGE_NAME ?? 'com.pronowin.app',
  clientEmail:  process.env.GOOGLE_SA_CLIENT_EMAIL ?? '',
  privateKey:   (process.env.GOOGLE_SA_PRIVATE_KEY ?? '').replace(/\\n/g, '\n'),
};

/**
 * Refuser un reçu Sandbox en production : sans ce garde-fou, n'importe qui
 * disposant d'un compte de test Apple peut s'offrir un Premium gratuit.
 */
//
// `IAP_ACCEPT_SANDBOX=false` était écrasé en silence : le `||` rendait la
// valeur vraie dès que `NODE_ENV` valait autre chose que `production`, si bien
// qu'un `.env` disant explicitement « non » se comportait comme un « oui ».
// Un réglage qui ne règle rien vaut moins que pas de réglage du tout.
//
// Le repli sur `NODE_ENV` ne joue donc plus que si la variable est absente.
const ACCEPT_SANDBOX = process.env.IAP_ACCEPT_SANDBOX !== undefined
  ? process.env.IAP_ACCEPT_SANDBOX === 'true'
  : process.env.NODE_ENV !== 'production';

export class IapService {

  // ─── Apple ──────────────────────────────────────────────────────────────────

  /** JWT ES256 exigé par l'App Store Server API (valide 1 h max). */
  private _appleToken(): string {
    if (!APPLE.privateKey || !APPLE.keyId || !APPLE.issuerId) {
      throw new Error('IAP Apple non configuré (APPLE_IAP_KEY_ID / ISSUER_ID / PRIVATE_KEY).');
    }
    const now = Math.floor(Date.now() / 1000);
    return jwt.sign(
      { iss: APPLE.issuerId, iat: now, exp: now + 3000, aud: 'appstoreconnect-v1', bid: APPLE.bundleId },
      APPLE.privateKey,
      { algorithm: 'ES256', header: { alg: 'ES256', kid: APPLE.keyId, typ: 'JWT' } },
    );
  }

  /**
   * Décode la charge utile d'un JWS Apple, **sans rien vérifier**.
   *
   * Le nom le dit : c'est un décodage, pas une authentification. Deux usages,
   * tous deux légitimes parce que la confiance vient d'ailleurs :
   *
   *  * réponses de `api.storekit.itunes.apple.com`, obtenues par un canal TLS
   *    authentifié auprès d'Apple ;
   *  * notifications serveur, dont le contenu n'est **jamais** cru sur parole
   *    — il sert seulement à retrouver la transaction, puis tout est
   *    revérifié auprès de l'API d'Apple.
   */
  private _decodeJws(token: string): any {
    const part = token.split('.')[1];
    if (!part) throw new Error('JWS Apple malformé.');
    return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
  }

  /**
   * Vérifie une transaction auprès d'Apple.
   *
   * On interroge les deux environnements : un build TestFlight produit des
   * transactions Sandbox alors que l'app pointe sur l'API de production.
   */
  async verifyApple(transactionId: string): Promise<VerifiedPurchase> {
    const token = this._appleToken();
    const hosts = [
      ['Production', 'https://api.storekit.itunes.apple.com'],
      ['Sandbox',    'https://api.storekit-sandbox.itunes.apple.com'],
    ] as const;

    let lastErr: unknown = null;
    for (const [environment, host] of hosts) {
      try {
        const r = await axios.get(
          `${host}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`,
          { headers: { Authorization: `Bearer ${token}` }, timeout: 10000 },
        );

        // La réponse groupe les abonnements par groupe puis par transaction.
        const item = r.data?.data?.[0]?.lastTransactions?.[0];
        if (!item?.signedTransactionInfo) throw new Error('Transaction absente de la réponse Apple.');

        const info    = this._decodeJws(item.signedTransactionInfo);
        const renewal = item.signedRenewalInfo ? this._decodeJws(item.signedRenewalInfo) : {};

        return {
          store:                 'apple',
          productId:             info.productId,
          transactionId:         info.transactionId,
          originalTransactionId: info.originalTransactionId,
          expiresAt:             new Date(Number(info.expiresDate)),
          // status Apple : 1=actif 2=expiré 3=en défaut de paiement 4=période de grâce 5=révoqué
          status:                APPLE_STATUS[item.status] ?? 'unknown',
          environment:           info.environment ?? environment,
          payload:               { transaction: info, renewal },
        };
      } catch (e: any) {
        // 404 = transaction inconnue de cet environnement, on tente l'autre.
        if (e.response?.status !== 404) throw new Error(`Apple : ${e.response?.data?.errorMessage ?? e.message}`);
        lastErr = e;
      }
    }
    throw new Error('Transaction introuvable chez Apple (production et sandbox).');
  }

  // ─── Google ─────────────────────────────────────────────────────────────────

  private _googleClient(): JWT {
    if (!GOOGLE.clientEmail || !GOOGLE.privateKey) {
      throw new Error('IAP Google non configuré (GOOGLE_SA_CLIENT_EMAIL / GOOGLE_SA_PRIVATE_KEY).');
    }
    return new JWT({
      email:  GOOGLE.clientEmail,
      key:    GOOGLE.privateKey,
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });
  }

  /**
   * Vérifie un achat auprès de Google Play (API subscriptionsv2).
   *
   * `purchaseToken` est à la fois le jeton de la transaction et l'identifiant
   * stable de l'abonnement — Google ne distingue pas les deux comme Apple.
   */
  async verifyGoogle(purchaseToken: string): Promise<VerifiedPurchase> {
    const client = this._googleClient();
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/`
      + `${encodeURIComponent(GOOGLE.packageName)}/purchases/subscriptionsv2/tokens/`
      + `${encodeURIComponent(purchaseToken)}`;

    let data: any;
    try {
      const r = await client.request<any>({ url, timeout: 10000 });
      data = r.data;
    } catch (e: any) {
      throw new Error(`Google Play : ${e.response?.data?.error?.message ?? e.message}`);
    }

    const line = data.lineItems?.[0];
    if (!line) throw new Error('Aucun produit dans la réponse Google Play.');

    return {
      store:                 'google',
      productId:             line.productId,
      transactionId:         `${data.latestOrderId ?? purchaseToken}`,
      originalTransactionId: purchaseToken,
      expiresAt:             new Date(line.expiryTime),
      status:                GOOGLE_STATUS[data.subscriptionState] ?? 'unknown',
      // Google marque explicitement les achats de test.
      environment:           data.testPurchase ? 'Sandbox' : 'Production',
      payload:               data,
    };
  }

  // ─── Enregistrement ─────────────────────────────────────────────────────────

  /**
   * Vérifie un reçu et projette son état sur le compte.
   *
   * Idempotent : `transactionId` est unique en base, donc rejouer le même reçu
   * (restauration d'achats, relance après crash, notification serveur en
   * double) ne crédite jamais deux fois.
   */
  async verifyAndRecord(params: {
    userId: string; store: IapStoreName; receipt: string;
  }) {
    const { userId, store, receipt } = params;

    const v = store === 'apple'
      ? await this.verifyApple(receipt)
      : await this.verifyGoogle(receipt);

    if (!IAP_PRODUCTS[v.productId]) {
      throw new Error(`Produit inconnu : ${v.productId}`);
    }
    if (v.environment === 'Sandbox' && !ACCEPT_SANDBOX) {
      throw new Error('Reçu de test refusé en production.');
    }

    const existing = await prisma.iapPurchase.findUnique({
      where: { transactionId: v.transactionId },
    });

    // Déjà enregistré pour quelqu'un d'autre : un même achat ne peut pas
    // déverrouiller deux comptes (partage de reçu entre amis).
    if (existing && existing.userId !== userId) {
      throw new Error('Cet achat est déjà rattaché à un autre compte.');
    }

    await prisma.iapPurchase.upsert({
      where:  { transactionId: v.transactionId },
      update: { status: v.status, expiresAt: v.expiresAt, payload: v.payload as any },
      create: {
        userId, store: v.store, productId: v.productId,
        transactionId: v.transactionId, originalTransactionId: v.originalTransactionId,
        expiresAt: v.expiresAt, status: v.status, environment: v.environment,
        payload: v.payload as any,
      },
    });

    const active = v.status === 'active' || v.status === 'grace_period';

    // Ne recréer une ligne Subscription (et ne renotifier) que la première fois
    // qu'on voit cette transaction — sinon une restauration d'achats
    // dupliquerait l'historique et redéclencherait les commissions.
    if (active && !existing) {
      await subSvc().grantPremium({
        userId,
        expiresAt:     v.expiresAt,
        paymentMethod: `iap_${v.store}`,
        notify:        true,
      });
    } else if (active) {
      await prisma.user.update({
        where: { id: userId },
        data:  { subscriptionPlan: 'premium', subscriptionExpiresAt: v.expiresAt },
      });
    } else {
      await this._revokeIfExpired(userId);
    }

    return {
      success:    true,
      active,
      product_id: v.productId,
      expires_at: v.expiresAt.toISOString(),
      status:     v.status,
    };
  }

  /**
   * Retire le Premium si plus aucun achat IAP n'est actif.
   *
   * On ne rétrograde pas aveuglément : l'utilisateur peut avoir aussi payé par
   * Mobile Money, et cette échéance-là ne regarde pas le store.
   */
  private async _revokeIfExpired(userId: string) {
    const stillActive = await prisma.iapPurchase.findFirst({
      where: { userId, status: { in: ['active', 'grace_period'] }, expiresAt: { gt: new Date() } },
    });
    if (stillActive) return;

    const user = await prisma.user.findUnique({
      where: { id: userId }, select: { subscriptionExpiresAt: true },
    });
    if (user?.subscriptionExpiresAt && user.subscriptionExpiresAt > new Date()) return;

    await prisma.user.update({
      where: { id: userId }, data: { subscriptionPlan: 'free' },
    });
  }

  // ─── Notifications serveur ──────────────────────────────────────────────────

  /**
   * App Store Server Notifications V2.
   *
   * ⚠️ Le contenu de la notification n'est **jamais** cru sur parole.
   *
   * La version précédente vérifiait la signature du JWS avec le certificat
   * contenu **dans le JWS lui-même** (`header.x5c[0]`), sans jamais remonter
   * la chaîne jusqu'à la racine Apple. C'était circulaire : n'importe qui
   * pouvait générer une paire de clés ES256, y joindre son propre certificat
   * auto-signé, signer la charge de son choix — et `jwt.verify` acceptait.
   * L'échéance ainsi transmise était ensuite écrite telle quelle dans
   * `subscriptionExpiresAt`. Il suffisait d'un achat réel pour connaître un
   * `originalTransactionId` valide, puis d'une notification forgée pour se
   * prolonger jusqu'en 2099 — ou pour révoquer l'abonnement d'autrui.
   *
   * Le correctif ne consiste pas à valider la chaîne de certificats, mais à
   * cesser d'en dépendre : la notification sert uniquement à **retrouver**
   * l'achat, et tout le reste — produit, échéance, statut — est relu auprès de
   * l'API authentifiée d'Apple par `verifyAndRecord`. C'est déjà ce que fait
   * le chemin Google ; les deux stores sont désormais traités pareil.
   *
   * Cette approche résiste aussi au rejeu d'une notification authentique, ce
   * qu'une simple vérification de signature n'aurait pas empêché.
   */
  async handleAppleNotification(signedPayload: string) {
    const payload = this._decodeJws(signedPayload);
    const signedInfo = payload?.data?.signedTransactionInfo;
    if (!signedInfo) return { ignored: true, reason: 'payload_sans_transaction' };

    const info = this._decodeJws(signedInfo);
    const originalId = info?.originalTransactionId;
    if (!originalId) return { ignored: true, reason: 'original_transaction_absent' };

    const purchase = await prisma.iapPurchase.findFirst({
      where:   { originalTransactionId: originalId },
      orderBy: { createdAt: 'desc' },
    });
    // Notification pour un achat qu'on n'a jamais vu : le mobile n'a pas encore
    // appelé /verify. On l'ignore, il enverra le reçu à la prochaine ouverture.
    if (!purchase) return { ignored: true, reason: 'unknown_original_transaction' };

    // L'autorité, c'est Apple — pas l'expéditeur de la requête.
    const resultat = await this.verifyAndRecord({
      userId:  purchase.userId,
      store:   'apple',
      receipt: originalId,
    });

    // Prévenir l'abonné dont l'accès s'interrompt. `verifyAndRecord` révoque
    // mais ne notifie pas ; sans ce rappel, l'utilisateur découvrirait la
    // coupure en ouvrant un pronostic verrouillé.
    if (!resultat.active) {
      await notifSvc.sendToUser(purchase.userId, {
        title: 'Abonnement Premium interrompu',
        body:  'Ton accès Premium a pris fin. Tu peux le réactiver à tout moment.',
        data:  { deep_link: '/compte', type: 'premium' },
      }, 'premium').catch(() => {});
    }

    return {
      handled: true,
      type:    payload?.notificationType ?? 'inconnu',
      active:  resultat.active,
    };
  }

  /** Google Play Real-time Developer Notifications (via Pub/Sub push). */
  async handleGoogleNotification(message: { data?: string }) {
    if (!message?.data) return { ignored: true, reason: 'empty_message' };
    const decoded = JSON.parse(Buffer.from(message.data, 'base64').toString('utf8'));
    const sub = decoded.subscriptionNotification;
    if (!sub?.purchaseToken) return { ignored: true, reason: 'not_a_subscription_event' };

    const purchase = await prisma.iapPurchase.findFirst({
      where:   { originalTransactionId: sub.purchaseToken },
      orderBy: { createdAt: 'desc' },
    });
    if (!purchase) return { ignored: true, reason: 'unknown_purchase_token' };

    // On rejoue la vérification plutôt que de croire la notification sur
    // parole : elle ne porte pas la date d'expiration.
    await this.verifyAndRecord({
      userId:  purchase.userId,
      store:   'google',
      receipt: sub.purchaseToken,
    });

    return { handled: true, type: sub.notificationType };
  }

  // `_applyStoreEvent` a été supprimé avec la vérification circulaire.
  //
  // Il écrivait `subscriptionExpiresAt` directement depuis la charge reçue, et
  // décidait de la révocation d'après le seul `notificationType` transmis par
  // l'appelant. C'était le point d'écriture que la signature défaillante
  // laissait atteindre. Tout passe désormais par `verifyAndRecord`, qui ne
  // retient que ce qu'Apple ou Google confirment.
}

const APPLE_STATUS: Record<number, string> = {
  1: 'active', 2: 'expired', 3: 'billing_retry', 4: 'grace_period', 5: 'revoked',
};

const GOOGLE_STATUS: Record<string, string> = {
  SUBSCRIPTION_STATE_ACTIVE:           'active',
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD:  'grace_period',
  SUBSCRIPTION_STATE_CANCELED:         'canceled',
  SUBSCRIPTION_STATE_EXPIRED:          'expired',
  SUBSCRIPTION_STATE_ON_HOLD:          'on_hold',
  SUBSCRIPTION_STATE_PAUSED:           'paused',
  SUBSCRIPTION_STATE_PENDING:          'pending',
};
