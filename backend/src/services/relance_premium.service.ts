import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import { filtrePremiumEchu } from '../utils/premium';
import { lireConfig, codePromoPour } from './app_config.service';
import { NotificationService } from './notification.service';

/**
 * Relancer les abonnés dont le Premium a expiré (15 novembre 2026).
 *
 * Le rappel d'avant l'échéance existait (J-7, J-3, J-1) ; après, plus rien.
 * Le 14 novembre, 12 comptes avaient un Premium échu, et rien ne leur
 * rappelait de le renouveler. Deux chemins, qui se connaissent :
 *
 * - une relance automatique, trois jours après l'échéance, une seule fois ;
 * - une relance à la main depuis l'administration (filtre « Premium
 *   expiré »), avec le code promo si on le veut. Un compte déjà relancé dans
 *   les 7 derniers jours ne l'est pas une seconde fois.
 *
 * Toutes deux relèvent de l'interrupteur « Abonnement Premium — Expiration
 * et renouvellement » : celui qui l'a coupé ne reçoit rien.
 */
export const TYPE_RELANCE_PREMIUM = 'relance_premium';

export const MESSAGE_RELANCE = {
  fr: {
    title: 'Ton Premium te manque ?',
    body:  'Ton abonnement a expiré. Renouvelle-le depuis Compte › Abonnement pour retrouver les pronostics VIP.',
  },
  en: {
    title: 'Missing Premium?',
    body:  'Your subscription has expired. Renew it from Account › Subscription to get VIP predictions back.',
  },
} as const;

/** La relance automatique, tant de jours après l'échéance. */
export const RELANCE_APRES_JOURS = 3;
/** Au-delà, l'échéance est trop ancienne pour une relance automatique. */
const RELANCE_JUSQUA_JOURS = 10;
/** Pas deux relances en moins de 7 jours, à la main ou non. */
export const RELANCE_INTERVALLE_JOURS = 7;

const JOUR = 86_400_000;
const notifSvc = new NotificationService();

const lien = { deep_link: '/compte', type: TYPE_RELANCE_PREMIUM };

/** Une fois par jour : les échéances passées de 3 à 10 jours, jamais relancées depuis. */
export async function relancerAutomatiquement(maintenant: Date = new Date()) {
  const comptes = await prisma.user.findMany({
    where: {
      isActive: true, deletedAt: null, subscriptionPlan: 'premium',
      // Une fenêtre plutôt qu'un jour : un serveur arrêté ce jour-là ne fait
      // pas manquer la relance.
      subscriptionExpiresAt: {
        lte: new Date(maintenant.getTime() - RELANCE_APRES_JOURS * JOUR),
        gt:  new Date(maintenant.getTime() - RELANCE_JUSQUA_JOURS * JOUR),
      },
    },
    select: { id: true, subscriptionExpiresAt: true },
  });

  let notified = 0;
  for (const c of comptes) {
    // Déjà relancé depuis l'échéance (automatiquement, ou à la main) : non.
    // La notification est enregistrée même quand l'interrupteur est coupé —
    // c'est ce qui rend la tâche sûre à relancer au redémarrage du serveur.
    const deja = await prisma.notification.findFirst({
      where:  { userId: c.id, type: TYPE_RELANCE_PREMIUM, createdAt: { gte: c.subscriptionExpiresAt! } },
      select: { id: true },
    });
    if (deja) continue;
    await notifSvc.sendToUser(c.id, {
      title: MESSAGE_RELANCE.fr.title, body: MESSAGE_RELANCE.fr.body,
      titleEn: MESSAGE_RELANCE.en.title, bodyEn: MESSAGE_RELANCE.en.body,
      data: lien,
    }, 'premium').catch(() => {});
    notified++;
  }
  return { notified };
}

/** Les comptes qu'une relance à la main peut viser, et ceux relancés récemment. */
function filtres(maintenant: Date) {
  const echus = { isActive: true, deletedAt: null, ...filtrePremiumEchu(maintenant) };
  const joignables = { ...echus, appareils: { some: {} } };
  const recemment = {
    type: TYPE_RELANCE_PREMIUM,
    createdAt: { gte: new Date(maintenant.getTime() - RELANCE_INTERVALLE_JOURS * JOUR) },
  };
  return { echus, joignables, recemment };
}

/** Ce que la relance à la main ferait : à afficher avant d'envoyer. */
export async function apercuRelance(maintenant: Date = new Date()) {
  const f = filtres(maintenant);
  const [expires, joignables, recemment, { valeurs }] = await Promise.all([
    prisma.user.count({ where: f.echus }),
    prisma.user.count({ where: f.joignables }),
    prisma.user.count({ where: { ...f.joignables, notifications: { some: f.recemment } } }),
    lireConfig(),
  ]);
  return {
    expires, joignables, recemment,
    a_relancer: joignables - recemment,
    code_promo: codePromoPour(valeurs) || null,
    titre: MESSAGE_RELANCE.fr.title,
    message: MESSAGE_RELANCE.fr.body,
  };
}

const TITRE_MAX = 80;
const MESSAGE_MAX = 300;

/**
 * La relance à la main. [titre] et [message] remplacent le texte par défaut
 * — qui, lui seul, a sa version anglaise ; [avecCode] ajoute le code promo
 * de la configuration.
 */
export async function relancerExpires(options: { titre?: unknown; message?: unknown; avec_code?: unknown },
    maintenant: Date = new Date()) {
  const texte = (v: unknown, max: number, nom: string): string | null => {
    if (v === undefined || v === null || (typeof v === 'string' && v.trim() === '')) return null;
    if (typeof v !== 'string' || v.trim().length > max) {
      throw new ErreurMetier(`${nom} invalide (${max} caractères au plus).`, 422);
    }
    return v.trim();
  };
  const titre = texte(options.titre, TITRE_MAX, 'Titre');
  const message = texte(options.message, MESSAGE_MAX, 'Message');
  const avecCode = options.avec_code === true || options.avec_code === 'true';

  let code = '';
  if (avecCode) {
    code = codePromoPour((await lireConfig()).valeurs);
    if (!code) throw new ErreurMetier('Aucun code promo n’est configuré (Paramètres de l’application).', 422);
  }

  const f = filtres(maintenant);
  const [cibles, recemment] = await Promise.all([
    prisma.user.findMany({ where: { ...f.joignables, notifications: { none: f.recemment } }, select: { id: true } }),
    prisma.user.count({ where: { ...f.joignables, notifications: { some: f.recemment } } }),
  ]);

  const parDefaut = (titre ?? MESSAGE_RELANCE.fr.title) === MESSAGE_RELANCE.fr.title
    && (message ?? MESSAGE_RELANCE.fr.body) === MESSAGE_RELANCE.fr.body;
  const fr = {
    title: titre ?? MESSAGE_RELANCE.fr.title,
    body:  `${message ?? MESSAGE_RELANCE.fr.body}${code ? ` Code promo : ${code}` : ''}`,
  };
  // Un texte écrit à la main n'a pas de traduction : il part tel quel.
  const en = parDefaut
    ? { titleEn: MESSAGE_RELANCE.en.title, bodyEn: `${MESSAGE_RELANCE.en.body}${code ? ` Promo code: ${code}` : ''}` }
    : {};

  const res = await Promise.allSettled(cibles.map(c =>
    notifSvc.sendToUser(c.id, { ...fr, ...en, data: lien }, 'premium')));
  const sent = res.filter(r => r.status === 'fulfilled').length;
  return { sent, failed: cibles.length - sent, skipped: recemment, total: cibles.length + recemment, avec_code: !!code };
}
