import { prisma } from '../lib/prisma';
import { STATUTS_AVEC_ACCES } from './iap_statuts';
import { IapService, type IapStoreName } from './iap.service';

/**
 * Les achats App Store et Google Play, vus depuis le panneau.
 *
 * Le serveur enregistrait chaque transaction (`IapPurchase`) et chaque
 * notification des stores (`IapNotification`), mais aucun écran ne les
 * montrait : une vente Apple ne se voyait que dans App Store Connect, sans
 * lien avec le compte PronoWin qui en profitait, et un abonnement payé mais
 * pas activé ne se découvrait que par la réclamation de son acheteur.
 *
 * ── Un abonnement, pas une transaction ──────────────────────────────────────
 *
 * Chaque renouvellement crée une transaction ; les lignes sont regroupées par
 * `originalTransactionId`, l'identifiant de l'abonnement chez le store. Une
 * ligne de l'écran est un abonnement : sa première souscription, sa dernière
 * échéance, son nombre de paiements.
 */

export type EtatAbonnementStore =
  | 'actif' | 'resilie' | 'impaye' | 'expire' | 'rembourse';

export interface AbonnementStore {
  id:              string;   // l'IapPurchase le plus récent de la chaîne
  store:           'apple' | 'google';
  formule:         'mensuel' | 'annuel' | 'autre';
  produit:         string;
  etat:            EtatAbonnementStore;
  test:            boolean;
  /** false : l'abonné a coupé le renouvellement ; null : le store ne l'a pas dit. */
  renouvellementAuto: boolean | null;
  premierAchat:    string;
  derniereMaj:     string;
  echeance:        string;
  paiements:       number;
  montant:         string | null;
  transaction:     string;
  compte: {
    id:        string;
    pseudo:    string;
    email:     string | null;
    premium:   boolean;
    supprime:  boolean;
  };
  /** Payé et en cours chez le store, mais le compte n'est pas Premium. */
  anomalie:        boolean;
}

const JOUR = 86_400_000;

function formuleDe(produit: string): AbonnementStore['formule'] {
  if (produit.endsWith('.monthly')) return 'mensuel';
  if (produit.endsWith('.annual'))  return 'annuel';
  return 'autre';
}

/** Ce que le store a dit du renouvellement automatique, quand il l'a dit. */
export function renouvellementDe(store: string, payload: any): boolean | null {
  if (store === 'apple') {
    const v = payload?.renewal?.autoRenewStatus;
    return v === 1 ? true : v === 0 ? false : null;
  }
  const v = payload?.lineItems?.[0]?.autoRenewingPlan?.autoRenewEnabled;
  return typeof v === 'boolean' ? v : null;
}

/** Le prix payé, quand le store le donne (Apple : millièmes d'unité). */
export function montantDe(store: string, payload: any): string | null {
  const t = payload?.transaction;
  if (store === 'apple' && typeof t?.price === 'number' && typeof t?.currency === 'string') {
    return `${(t.price / 1000).toFixed(2)} ${t.currency}`;
  }
  return null;
}

export function etatDe(statut: string, echeance: Date, renouvellement: boolean | null, maintenant = new Date()): EtatAbonnementStore {
  if (statut === 'revoked' || statut === 'refunded') return 'rembourse';
  if (statut === 'billing_retry' || statut === 'on_hold') return 'impaye';
  const enCours = echeance.getTime() > maintenant.getTime()
    && STATUTS_AVEC_ACCES.includes(statut);
  if (!enCours) return 'expire';
  // Google dit « canceled » pour un abonnement résilié qui court jusqu'à son
  // terme ; Apple le dit par le renouvellement coupé.
  if (statut === 'canceled' || renouvellement === false) return 'resilie';
  return 'actif';
}

export async function resumeAchatsStore(params: {
  store?: string; etat?: string; tests?: boolean; recherche?: string; page?: number;
} = {}) {
  const maintenant = new Date();
  const lignes = await prisma.iapPurchase.findMany({
    orderBy: { createdAt: 'desc' },
    take: 5000,
    include: { user: { select: {
      id: true, pseudo: true, email: true, subscriptionPlan: true,
      subscriptionExpiresAt: true, deletedAt: true,
    } } },
  });

  const chaines = new Map<string, typeof lignes>();
  for (const l of lignes) {
    const cle = `${l.store}:${l.originalTransactionId}`;
    (chaines.get(cle) ?? chaines.set(cle, []).get(cle)!).push(l);
  }

  const abonnements: AbonnementStore[] = [];
  let renouvellements30j = 0;
  for (const chaine of chaines.values()) {
    chaine.sort((a, b) => b.expiresAt.getTime() - a.expiresAt.getTime());
    const dernier = chaine[0];
    const premier = chaine.reduce((m, l) => (l.createdAt < m.createdAt ? l : m), chaine[0]);
    const renouvellement = renouvellementDe(dernier.store, dernier.payload);
    const etat = etatDe(dernier.status, dernier.expiresAt, renouvellement, maintenant);
    const test = dernier.environment === 'Sandbox';
    const u = dernier.user;
    const premium = u.subscriptionPlan === 'premium'
      && (!u.subscriptionExpiresAt || u.subscriptionExpiresAt > maintenant);

    if (!test) {
      renouvellements30j += chaine.filter((l) =>
        l.id !== premier.id && maintenant.getTime() - l.createdAt.getTime() < 30 * JOUR).length;
    }

    abonnements.push({
      id: dernier.id,
      store: dernier.store as 'apple' | 'google',
      formule: formuleDe(dernier.productId),
      produit: dernier.productId,
      etat, test,
      renouvellementAuto: renouvellement,
      premierAchat: premier.createdAt.toISOString(),
      derniereMaj: dernier.updatedAt.toISOString(),
      echeance: dernier.expiresAt.toISOString(),
      paiements: chaine.length,
      montant: montantDe(dernier.store, dernier.payload),
      transaction: dernier.transactionId,
      compte: {
        id: u.id, pseudo: u.pseudo, email: u.email,
        premium, supprime: u.deletedAt !== null,
      },
      anomalie: (etat === 'actif' || etat === 'resilie') && !premium && u.deletedAt === null,
    });
  }

  abonnements.sort((a, b) =>
    Number(b.anomalie) - Number(a.anomalie) || b.derniereMaj.localeCompare(a.derniereMaj));

  const reels = abonnements.filter((a) => !a.test);
  const enCours = (a: AbonnementStore) => a.etat === 'actif' || a.etat === 'resilie';
  const stats = {
    actifs:        { apple: reels.filter((a) => enCours(a) && a.store === 'apple').length,
                     google: reels.filter((a) => enCours(a) && a.store === 'google').length },
    nouveaux30j:   reels.filter((a) => maintenant.getTime() - Date.parse(a.premierAchat) < 30 * JOUR).length,
    renouvellements30j,
    resilies:      reels.filter((a) => a.etat === 'resilie').length,
    impayes:       reels.filter((a) => a.etat === 'impaye').length,
    rembourses:    reels.filter((a) => a.etat === 'rembourse').length,
    expires30j:    reels.filter((a) => a.etat === 'expire'
                     && maintenant.getTime() - Date.parse(a.echeance) < 30 * JOUR).length,
    anomalies:     abonnements.filter((a) => a.anomalie).length,
    tests:         abonnements.length - reels.length,
  };

  const q = (params.recherche ?? '').trim().toLowerCase();
  const filtres = abonnements.filter((a) =>
    (params.tests || !a.test)
    && (!params.store || a.store === params.store)
    && (!params.etat || (params.etat === 'anomalie' ? a.anomalie : a.etat === params.etat))
    && (!q || a.compte.pseudo.toLowerCase().includes(q)
           || (a.compte.email ?? '').toLowerCase().includes(q)
           || a.transaction.toLowerCase().includes(q)));

  const parPage = 50;
  const page = Math.max(1, params.page ?? 1);

  const [enEchec, notifications] = await Promise.all([
    prisma.iapNotification.count({ where: { statut: { in: ['echec', 'abandonnee'] } } }),
    prisma.iapNotification.findMany({
      orderBy: { recueLe: 'desc' }, take: 15,
      select: { id: true, store: true, statut: true, tentatives: true, recueLe: true,
                traiteeLe: true, derniereErreur: true, charge: true },
    }),
  ]);

  return {
    stats: { ...stats, notificationsEnEchec: enEchec },
    total: filtres.length,
    page, parPage,
    abonnements: filtres.slice((page - 1) * parPage, page * parPage),
    notifications: notifications.map((n) => ({
      id: n.id, store: n.store, statut: n.statut, tentatives: n.tentatives,
      recueLe: n.recueLe.toISOString(), traiteeLe: n.traiteeLe?.toISOString() ?? null,
      erreur: n.derniereErreur,
      type: typeDeNotification(n.store, n.charge),
    })),
  };
}

/**
 * Redemande au store l'état d'un abonnement et le reporte sur le compte.
 *
 * Le remède aux anomalies : un achat payé dont la vérification n'a pas abouti
 * au moment de l'achat. `null` si l'achat n'existe pas.
 */
export async function reverifierAchatStore(id: string) {
  const achat = await prisma.iapPurchase.findUnique({ where: { id } });
  if (!achat) return null;
  return new IapService().verifyAndRecord({
    userId:  achat.userId,
    store:   achat.store as IapStoreName,
    // Apple se consulte par numéro de transaction, Google par jeton d'achat.
    receipt: achat.store === 'apple' ? achat.transactionId : achat.originalTransactionId,
  });
}

/**
 * Le type d'événement, lisible : « DID_RENEW », « RENEWED »…
 *
 * La charge est gardée telle que le store l'a envoyée : Apple, un JWS signé
 * (`signedPayload`) ; Google, un message Pub/Sub dont `data` est du JSON en
 * base64. On ne lit ici qu'un type d'événement — la signature a été vérifiée
 * au traitement, et rien de ce qui suit n'en dépend.
 */
export function typeDeNotification(store: string, charge: any): string {
  try {
    if (store === 'apple') {
      const p = JSON.parse(Buffer.from(String(charge?.signedPayload ?? '').split('.')[1] ?? '', 'base64url').toString());
      return [p?.notificationType, p?.subtype].filter(Boolean).join(' · ') || 'inconnu';
    }
    const brut = charge?.message?.data;
    charge = brut ? JSON.parse(Buffer.from(String(brut), 'base64').toString()) : charge;
  } catch {
    return 'illisible';
  }
  const t = charge?.subscriptionNotification?.notificationType;
  const noms: Record<number, string> = {
    1: 'RECOVERED', 2: 'RENEWED', 3: 'CANCELED', 4: 'PURCHASED', 5: 'ON_HOLD', 6: 'IN_GRACE_PERIOD',
    7: 'RESTARTED', 10: 'PAUSED', 12: 'REVOKED', 13: 'EXPIRED',
  };
  return typeof t === 'number' ? (noms[t] ?? `type ${t}`) : (charge?.testNotification ? 'TEST' : 'inconnu');
}
