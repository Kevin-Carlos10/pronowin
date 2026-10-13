import crypto from 'crypto';
import axios from 'axios';
import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { journal } from '../utils/logger';
import {
  PREMIUM_PRICE_FCFA_ANNUAL, PREMIUM_PRICE_FCFA_MONTHLY, SubscriptionService,
} from './subscription.service';

/**
 * Paiement Mobile Money par GeniusPay (13 octobre 2026).
 *
 * Jusqu'ici, l'abonné du canal direct payait par Orange Money, envoyait une
 * capture, et attendait qu'un administrateur la valide. GeniusPay héberge la
 * page de paiement (Orange Money, Moov Money…) et confirme le résultat.
 *
 * ── Ce qui fait foi ──────────────────────────────────────────────────────
 *
 * Ni l'application, ni le webhook : un retour dans l'app ne prouve rien, et
 * un webhook peut être rejoué ou mal signé. Avant d'accorder le Premium, le
 * serveur relit toujours le paiement chez GeniusPay (`GET /payments/{ref}`)
 * et vérifie la référence, le montant, la devise et l'environnement. Le
 * webhook, le retour dans l'application et le rapprochement périodique ne
 * font que déclencher cette relecture ; le premier qui confirme accorde le
 * Premium, une seule fois (`premiumAccordeLe`).
 *
 * ── Test et réel ─────────────────────────────────────────────────────────
 *
 * L'environnement vient du préfixe de la clé publique (`…_sandbox_` /
 * `…_live_`). La documentation annonce `pk_sandbox_`, le tableau de bord
 * affiche `sk_sandbox_` pour la même clé (13 octobre 2026) : seul le segment
 * d'environnement compte. En
 * test, un paiement simulé accorderait un vrai Premium : le paiement n'est
 * alors proposé qu'aux comptes de GENIUSPAY_TESTEURS. Un paiement d'un autre
 * environnement que celui des clés n'accorde jamais rien.
 */

// Le point d'entrée affiché par le tableau de bord GeniusPay (Intégrations →
// Clés API), qui diffère de celui de la documentation (pay.genius.ci).
export const URL_API_GENIUSPAY = (process.env.GENIUSPAY_API_URL ?? 'https://geniuspay.ci/api/v1/merchant')
  .replace(/\/+$/, '');
const URL_SITE = (process.env.PUBLIC_SITE_URL ?? 'https://pronowin.space').replace(/\/+$/, '');

export type EnvironnementGeniusPay = 'sandbox' | 'live';

export interface ConfigGeniusPay {
  clePublique:   string;
  cleSecrete:    string;
  secretWebhook: string;
  environnement: EnvironnementGeniusPay;
  /** Identifiants ou adresses e-mail des comptes autorisés en mode test. */
  testeurs:      string[];
}

/** La configuration, ou `null` si les clés manquent ou se contredisent. */
export function configGeniusPay(env: NodeJS.ProcessEnv = process.env): ConfigGeniusPay | null {
  const clePublique = (env.GENIUSPAY_PUBLIC_KEY ?? '').trim();
  const cleSecrete  = (env.GENIUSPAY_SECRET_KEY ?? '').trim();
  if (!clePublique || !cleSecrete) return null;
  const pub = /^[a-z]+_(sandbox|live)_/.exec(clePublique);
  const sec = /^[a-z]+_(sandbox|live)_/.exec(cleSecrete);
  if (!pub || (sec && sec[1] !== pub[1])) {
    // Une clé de test avec une clé réelle : chaque appel échouerait, ou
    // pire, le serveur croirait être en test en encaissant du réel.
    journal.error('[GeniusPay] Clés incohérentes : la clé publique doit dire sandbox ou live, et la secrète le même environnement.');
    return null;
  }
  return {
    clePublique, cleSecrete,
    secretWebhook: (env.GENIUSPAY_WEBHOOK_SECRET ?? '').trim(),
    environnement: pub[1] as EnvironnementGeniusPay,
    testeurs: (env.GENIUSPAY_TESTEURS ?? '').split(',')
      .map((t) => t.trim().toLowerCase()).filter(Boolean),
  };
}

/** Le paiement est-il proposé à ce compte ? */
export function geniusPayOuvert(
  cfg: ConfigGeniusPay | null, compte: { id: string; email?: string | null },
): boolean {
  if (!cfg) return false;
  if (cfg.environnement === 'live') return true;
  return cfg.testeurs.includes(compte.id.toLowerCase())
    || (!!compte.email && cfg.testeurs.includes(compte.email.toLowerCase()));
}

export const PLANS_GENIUSPAY: Record<string, { montant: () => number; jours: number; libelle: string }> = {
  premium_monthly: { montant: () => PREMIUM_PRICE_FCFA_MONTHLY, jours: 30,  libelle: 'PronoWin Premium — 1 mois' },
  premium_annual:  { montant: () => PREMIUM_PRICE_FCFA_ANNUAL,  jours: 365, libelle: 'PronoWin Premium — 1 an' },
};

/** Statuts après lesquels rien ne change plus chez GeniusPay. */
const TERMINAUX = new Set(['failed', 'cancelled', 'expired', 'refunded']);
const STATUTS = new Set(['pending', 'processing', 'completed', ...TERMINAUX]);

function statutDe(brut: unknown): string {
  const s = String(brut ?? '').toLowerCase();
  if (s === 'success' || s === 'succeeded' || s === 'paid') return 'completed';
  if (s === 'canceled') return 'cancelled';
  return STATUTS.has(s) ? s : 'pending';
}

/**
 * Les deux appels à GeniusPay. Un objet plutôt que des fonctions isolées :
 * les bancs les remplacent sans toucher au réseau.
 */
export const geniusPayHttp = {
  async creer(cfg: ConfigGeniusPay, corps: Record<string, unknown>): Promise<any> {
    const r = await axios.post(`${URL_API_GENIUSPAY}/payments`, corps, {
      headers: entetes(cfg), timeout: 20_000,
    });
    return r.data?.data ?? r.data;
  },
  async lire(cfg: ConfigGeniusPay, reference: string): Promise<any> {
    const r = await axios.get(`${URL_API_GENIUSPAY}/payments/${encodeURIComponent(reference)}`, {
      headers: entetes(cfg), timeout: 20_000,
    });
    return r.data?.data ?? r.data;
  },
};

function entetes(cfg: ConfigGeniusPay) {
  return {
    'X-API-Key': cfg.clePublique, 'X-API-Secret': cfg.cleSecrete,
    'Content-Type': 'application/json', Accept: 'application/json',
  };
}

// ── Ouvrir un paiement ───────────────────────────────────────────────────────

/** Au-delà, un compte qui ouvre des paiements en boucle est arrêté. */
const OUVERTURES_MAX_PAR_HEURE = 10;

/**
 * `retour` : où GeniusPay renvoie l'abonné après le paiement — la page de
 * retour qui le renvoie dans l'application, ou la page Premium du site qui
 * suit elle-même le paiement.
 */
export async function creerPaiement(
  userId: string, plan: string, opts: { retour?: 'app' | 'site' } = {},
) {
  const cfg = configGeniusPay();
  const formule = PLANS_GENIUSPAY[plan];
  if (!formule) throw new ErreurMetier('Formule inconnue.', 400);
  const compte = await prisma.user.findUnique({ where: { id: userId }, select: {
    id: true, email: true, pseudo: true, firstName: true, lastName: true,
    phoneNumber: true, countryCode: true, deletedAt: true,
  } });
  if (!compte || compte.deletedAt) throw new ErreurMetier('Compte introuvable.', 404);
  if (!cfg || !geniusPayOuvert(cfg, compte)) {
    throw new ErreurMetier('Le paiement Mobile Money automatique est momentanément indisponible.', 503);
  }
  const recents = await prisma.paiementGeniusPay.count({
    where: { userId, creeLe: { gt: new Date(Date.now() - 3_600_000) } },
  });
  if (recents >= OUVERTURES_MAX_PAR_HEURE) {
    throw new ErreurMetier('Trop de tentatives de paiement. Réessaie dans une heure.', 429);
  }

  const montant = formule.montant();
  const ligne = await prisma.paiementGeniusPay.create({ data: {
    userId, plan, montant, environnement: cfg.environnement,
  } });
  const retour = opts.retour === 'site'
    ? `${URL_SITE}/premium?p=${ligne.id}`
    : `${URL_SITE}/paiement/retour?p=${ligne.id}`;
  const nom = [compte.firstName, compte.lastName].filter(Boolean).join(' ') || compte.pseudo;

  let d: any;
  try {
    d = await geniusPayHttp.creer(cfg, {
      amount: montant, currency: 'XOF', description: formule.libelle,
      customer: {
        name: nom,
        ...(compte.email ? { email: compte.email } : {}),
        ...(compte.phoneNumber ? { phone: compte.phoneNumber } : {}),
        ...(compte.countryCode ? { country: compte.countryCode } : {}),
      },
      success_url: `${retour}&statut=succes`,
      error_url:   `${retour}&statut=echec`,
      metadata: { paiement_id: ligne.id, user_id: userId, plan },
    });
  } catch (e: any) {
    await prisma.paiementGeniusPay.update({ where: { id: ligne.id }, data: { statut: 'failed' } });
    journal.error('[GeniusPay] Création refusée', {
      statut: e?.response?.status, code: e?.response?.data?.error?.code, message: e?.message });
    throw new ErreurMetier("Le paiement n'a pas pu être ouvert. Réessaie dans un instant.", 502);
  }

  const lien = d?.checkout_url ?? d?.payment_url;
  if (!d?.reference || !lien || (d.environment && d.environment !== cfg.environnement)) {
    await prisma.paiementGeniusPay.update({ where: { id: ligne.id }, data: { statut: 'failed' } });
    journal.error('[GeniusPay] Réponse inattendue à la création', {
      reference: d?.reference, environnement: d?.environment, lien: !!lien });
    throw new ErreurMetier("Le paiement n'a pas pu être ouvert. Réessaie dans un instant.", 502);
  }
  await prisma.paiementGeniusPay.update({ where: { id: ligne.id }, data: {
    reference: String(d.reference), checkoutUrl: String(lien), statut: statutDe(d.status),
  } });
  return { id: ligne.id, reference: String(d.reference), checkout_url: String(lien), montant, plan };
}

// ── Suivre ───────────────────────────────────────────────────────────────────

/**
 * Dernière relecture de chaque paiement chez GeniusPay. L'application et la
 * page du site interrogent l'état toutes les quelques secondes : sans ce
 * frein, chacune de leurs questions deviendrait un appel à GeniusPay.
 */
const derniereRelecture = new Map<string, number>();
const INTERVALLE_RELECTURE_MS = 5_000;

/** L'état d'un paiement du compte, relu chez GeniusPay s'il est en cours. */
export async function etatPaiement(userId: string, id: string) {
  let ligne = await prisma.paiementGeniusPay.findFirst({ where: { id, userId } });
  if (!ligne) throw new ErreurMetier('Paiement introuvable.', 404);
  const enCours = !ligne.premiumAccordeLe && ['pending', 'processing'].includes(ligne.statut);
  if (enCours && Date.now() - (derniereRelecture.get(ligne.id) ?? 0) > INTERVALLE_RELECTURE_MS) {
    derniereRelecture.set(ligne.id, Date.now());
    if (derniereRelecture.size > 10_000) derniereRelecture.clear();
    const id = ligne.id;
    ligne = (await rapprocherPaiement(id).catch((e: Error) => {
      journal.error('[GeniusPay] Relecture', { id, message: e.message });
      return ligne;
    })) ?? ligne;
  }
  // La fin du Premium, pour la confirmation affichée à l'abonné.
  const expireLe = ligne.premiumAccordeLe
    ? (await prisma.user.findUnique({ where: { id: userId },
        select: { subscriptionExpiresAt: true } }))?.subscriptionExpiresAt ?? null
    : null;
  return {
    id: ligne.id, statut: ligne.statut, plan: ligne.plan, montant: ligne.montant,
    premium_active: !!ligne.premiumAccordeLe, expire_le: expireLe,
  };
}

// ── Confirmer ────────────────────────────────────────────────────────────────

class DejaAccorde extends Error {}

/**
 * Relit le paiement chez GeniusPay et en tire les conséquences : Premium
 * accordé une fois s'il est payé et conforme, statut mis à jour sinon.
 */
export async function rapprocherPaiement(id: string) {
  const ligne = await prisma.paiementGeniusPay.findUnique({ where: { id } });
  // « anomalie » attend un humain : la relire en boucle ne changerait rien.
  if (!ligne?.reference || ligne.premiumAccordeLe || TERMINAUX.has(ligne.statut)
      || ligne.statut === 'anomalie') return ligne;
  const cfg = configGeniusPay();
  if (!cfg) return ligne;

  const d = await geniusPayHttp.lire(cfg, ligne.reference);
  const statut = statutDe(d?.status);
  const details = {
    moyen:      d?.payment_method ?? d?.payment_provider ?? null,
    frais:      Number.isFinite(Number(d?.fees)) ? Math.round(Number(d.fees)) : null,
    montantNet: Number.isFinite(Number(d?.net_amount)) ? Math.round(Number(d.net_amount)) : null,
  };

  if (statut !== 'completed') {
    if (statut !== ligne.statut) {
      await prisma.paiementGeniusPay.updateMany({
        where: { id, premiumAccordeLe: null }, data: { statut, ...details } });
    }
    return prisma.paiementGeniusPay.findUnique({ where: { id } });
  }

  const ecarts = [
    String(d?.reference) !== ligne.reference && 'référence',
    Math.round(Number(d?.amount)) !== ligne.montant && 'montant',
    String(d?.currency ?? 'XOF').toUpperCase() !== 'XOF' && 'devise',
    (d?.environment ?? ligne.environnement) !== ligne.environnement && 'environnement',
    ligne.environnement !== cfg.environnement && 'environnement des clés',
  ].filter(Boolean);
  if (ecarts.length > 0) {
    // Payé, mais pas ce qui était demandé : rien n'est accordé, un humain
    // tranche (statut visible dans la base, message au journal).
    journal.error('[GeniusPay] Paiement confirmé mais non conforme', { id, ecarts });
    await prisma.paiementGeniusPay.updateMany({
      where: { id, premiumAccordeLe: null }, data: { statut: 'anomalie', ...details } });
    return prisma.paiementGeniusPay.findUnique({ where: { id } });
  }

  try {
    await new SubscriptionService().grantPremium({
      userId:        ligne.userId,
      durationDays:  PLANS_GENIUSPAY[ligne.plan]?.jours ?? 30,
      amountPaid:    ligne.montant,
      paymentMethod: 'geniuspay',
      garde: async (t) => {
        const { count } = await t.paiementGeniusPay.updateMany({
          where: { id, premiumAccordeLe: null },
          data:  { statut: 'completed', premiumAccordeLe: new Date(), ...details },
        });
        if (count === 0) throw new DejaAccorde();
      },
    });
  } catch (e) {
    if (!(e instanceof DejaAccorde)) throw e;
  }
  return prisma.paiementGeniusPay.findUnique({ where: { id } });
}

/** Les paiements ouverts depuis moins de 26 h (le lien expire après 24 h). */
export async function rapprocherPaiementsEnAttente() {
  if (!configGeniusPay()) return { examines: 0 };
  const ouverts = await prisma.paiementGeniusPay.findMany({
    where: {
      statut: { in: ['pending', 'processing'] }, reference: { not: null }, premiumAccordeLe: null,
      creeLe: { gt: new Date(Date.now() - 26 * 3_600_000) },
    },
    orderBy: { creeLe: 'asc' }, take: 50, select: { id: true },
  });
  for (const { id } of ouverts) {
    await rapprocherPaiement(id).catch((e: Error) =>
      journal.error('[GeniusPay] Rapprochement', { id, message: e.message }));
  }
  return { examines: ouverts.length };
}

// ── Webhook ──────────────────────────────────────────────────────────────────

/** Écart toléré entre l'horodatage signé et l'heure du serveur. */
const TOLERANCE_MS = 300_000;

/**
 * `X-Webhook-Signature` = HMAC-SHA256(horodatage + "." + corps, secret).
 *
 * Calculée sur le corps **tel que reçu** : le réencoder après lecture peut
 * changer un octet (espaces, échappements) et invalider une vraie signature.
 */
export function signatureValide(
  secret: string, horodatage: string | undefined, signature: string | undefined,
  corps: Buffer, maintenant = Date.now(),
): boolean {
  if (!secret || !horodatage || !signature) return false;
  const t = Number(horodatage);
  if (!Number.isFinite(t)) return false;
  if (Math.abs(maintenant - (t > 1e12 ? t : t * 1000)) > TOLERANCE_MS) return false;
  const hmac = crypto.createHmac('sha256', secret).update(`${horodatage}.`).update(corps).digest();
  const recue = signature.trim().replace(/^sha256=/i, '');
  return [hmac.toString('hex'), hmac.toString('base64')].some((attendue) =>
    attendue.length === recue.length
      && crypto.timingSafeEqual(Buffer.from(attendue), Buffer.from(recue)));
}

/**
 * Le code HTTP à renvoyer à GeniusPay, et la relecture à mener ensuite.
 *
 * GeniusPay attend une réponse en moins de 5 secondes (guide d'intégration
 * des webhooks) ; la relecture interroge son API et peut prendre plus. Le
 * contrôleur répond donc d'abord, puis attend `relecture`. Si elle échoue,
 * le rapprochement périodique reprend le paiement.
 */
export async function traiterWebhook(
  entetes: Record<string, string | string[] | undefined>, corps: Buffer,
): Promise<{ code: number; relecture?: Promise<unknown> }> {
  const cfg = configGeniusPay();
  if (!cfg?.secretWebhook) return { code: 503 };
  const lire = (nom: string) => {
    const v = entetes[nom];
    return Array.isArray(v) ? v[0] : v;
  };
  if (!signatureValide(cfg.secretWebhook, lire('x-webhook-timestamp'), lire('x-webhook-signature'), corps)) {
    journal.warn('[GeniusPay] Webhook à la signature invalide, ignoré');
    return { code: 401 };
  }
  let evenement: any;
  try { evenement = JSON.parse(corps.toString('utf8')); } catch { return { code: 400 }; }

  const reference = evenement?.data?.reference;
  if (!reference) return { code: 200 }; // webhook.test, cashout… : rien à rapprocher
  const ligne = await prisma.paiementGeniusPay.findUnique({
    where: { reference: String(reference) }, select: { id: true } });
  if (!ligne) return { code: 200 };
  // Le contenu du webhook ne sert qu'à savoir *quoi* relire.
  return { code: 200, relecture: rapprocherPaiement(ligne.id) };
}
