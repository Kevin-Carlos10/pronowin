
import { prisma } from '../lib/prisma';
import { journal } from '../utils/logger';

// Topics FCM — correspondent aux préférences utilisateur côté Flutter
export const FCM_TOPICS = {
  match:    'match_alerts',
  promo:    'promo_alerts',
  referral: 'referral_alerts',
  payment:  'payment_alerts',
  premium:  'premium_alerts',
  all:      'all_users',
};

/** Catégories exposées comme interrupteurs dans l'écran Paramètres du mobile. */
export const NOTIF_CATEGORIES = ['match', 'promo', 'referral', 'premium'] as const;
export type NotifCategory = (typeof NOTIF_CATEGORIES)[number];

/**
 * Modèle opt-out : une clé absente vaut « activé ». Un nouvel utilisateur a
 * `notificationPrefs` à null et reçoit donc tout, ce qui correspond aux valeurs
 * par défaut du mobile.
 */
export function isNotifEnabled(prefs: unknown, category: NotifCategory): boolean {
  if (prefs === null || typeof prefs !== 'object') return true;
  return (prefs as Record<string, unknown>)[category] !== false;
}

// ─── Segments de campagne ─────────────────────────────────────────────────────

/** Une campagne admin est du marketing : elle relève de l'interrupteur « Offres & Promotions ». */
const CAMPAIGN_CATEGORY: NotifCategory = 'promo';

/** Codes FCM signalant un jeton définitivement mort (à purger). */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

export const CAMPAIGN_SEGMENTS = [
  'all', 'premium', 'free', 'active_30', 'inactive_30', 'new_7',
] as const;

const days = (n: number) => new Date(Date.now() - n * 86400000);

/**
 * Traduit un segment de la page admin en clause Prisma.
 *
 * Deux pièges :
 *  - `subscriptionPlan` n'est jamais remis à `free` à l'expiration (seule une
 *    action admin le fait), donc « Premium » se définit par la date, pas par le
 *    drapeau — sinon on ciblerait des abonnements périmés.
 *  - l'activité se mesure sur `lastSeenAt` autant que sur `lastLoginAt` : la
 *    session survivant des semaines, un utilisateur quotidien peut n'avoir
 *    aucune connexion récente.
 */
export function segmentWhere(segment: string): Record<string, any> {
  const base = { isActive: true, deletedAt: null };
  const isPremium = {
    subscriptionPlan: 'premium' as const,
    subscriptionExpiresAt: { gt: new Date() },
  };
  const seenSince = (d: Date) => ({
    OR: [{ lastSeenAt: { gte: d } }, { lastLoginAt: { gte: d } }],
  });

  switch (segment) {
    case 'premium':     return { ...base, ...isPremium };
    case 'free':        return { ...base, NOT: isPremium };
    case 'active_30':   return { ...base, ...seenSince(days(30)) };
    case 'inactive_30': return { ...base, NOT: seenSince(days(30)) };
    case 'new_7':       return { ...base, createdAt: { gte: days(7) } };
    case 'all':         return base;
    default:
      throw new Error(
        `Segment inconnu : « ${segment} ». Attendu : ${CAMPAIGN_SEGMENTS.join(', ')}.`);
  }
}

let admin: any = null;
async function getAdmin() {
  if (admin) return admin;
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.FIREBASE_PRIVATE_KEY) {
    journal.warn('[FCM] Firebase non configuré — mode console');
    return null;
  }
  try {
    const fa = await import('firebase-admin');
    if (!fa.default.apps.length) {
      fa.default.initializeApp({
        credential: fa.default.credential.cert({
          projectId:   process.env.FIREBASE_PROJECT_ID,
          privateKey:  process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        }),
      });
    }
    admin = fa.default;
    journal.info('[FCM] firebase-admin initialisé ✅');
    return admin;
  } catch (e: any) {
    journal.error('[FCM] Erreur init:', e.message);
    return null;
  }
}

/**
 * Firebase absent : que répondre à l'appelant ?
 *
 * En développement, l'envoi est simulé et affiché dans la console — c'est son
 * rôle. En production, la simulation répondait `success: true` : le panneau
 * annonçait « notification envoyée à 1 240 personnes » quand aucune n'était
 * partie, et une clé Firebase perdue ne se voyait nulle part (constat I12 de
 * l'audit du 24 septembre 2026). Ce n'est plus un succès.
 */
function sansFirebase(): { success: false; error: string } | null {
  if (process.env.NODE_ENV !== 'production') return null;
  journal.error('[FCM] Firebase non configuré en production : notification NON envoyée.');
  return { success: false, error: 'firebase_non_configure' };
}

/** Au-delà, les appareils d'un compte vus le moins récemment sont oubliés. */
export const APPAREILS_PAR_COMPTE = 10;

export class NotificationService {

  /**
   * Rattache l'appareil au compte qui y est connecté.
   *
   * Le jeton est unique : l'enregistrer le retire au compte qui l'avait. Un
   * téléphone repris par un autre compte cesse donc de recevoir les
   * notifications du précédent (constat I12).
   */
  async registerToken(userId: string, jeton: string, plateforme: string) {
    await prisma.appareilNotification.upsert({
      where:  { jeton },
      create: { userId, jeton, plateforme },
      update: { userId, plateforme, vuLe: new Date() },
    });
    // Un jeton qui n'est jamais signalé mort par Firebase — appareil perdu,
    // application jamais rouverte — resterait sinon indéfiniment.
    const anciens = await prisma.appareilNotification.findMany({
      where: { userId }, orderBy: { vuLe: 'desc' }, skip: APPAREILS_PAR_COMPTE, select: { id: true },
    });
    if (anciens.length > 0) {
      await prisma.appareilNotification.deleteMany({ where: { id: { in: anciens.map(a => a.id) } } });
    }
    journal.info(`[FCM] Appareil enregistré — user ${userId}`);
    return { success: true };
  }

  /**
   * Détache un appareil du compte à la déconnexion — ou tous, quand la
   * déconnexion ferme toutes les sessions du compte.
   */
  async oublierAppareils(userId: string, jeton?: string) {
    await prisma.appareilNotification.deleteMany({ where: jeton ? { userId, jeton } : { userId } });
  }

  // ─── Historique notifications ────────────────────────────────────────────

  /** Récupérer les notifications d'un utilisateur */
  async getNotifications(userId: string, limit = 50) {
    return prisma.notification.findMany({
      where:   { userId },
      orderBy: { createdAt: 'desc' },
      take:    limit,
    });
  }

  /** Marquer une notification comme lue */
  async markRead(userId: string, notifId: string) {
    return prisma.notification.updateMany({
      where: { id: notifId, userId },
      data:  { isRead: true },
    });
  }

  /** Marquer toutes les notifications comme lues */
  async markAllRead(userId: string) {
    return prisma.notification.updateMany({
      where: { userId, isRead: false },
      data:  { isRead: true },
    });
  }

  /** Sauvegarder une notification en base (pour l'historique) */
  private async _saveNotification(userId: string, payload: {
    title: string; body: string; type?: string; deepLink?: string;
  }) {
    try {
      await prisma.notification.create({
        data: {
          userId,
          title:    payload.title,
          body:     payload.body,
          type:     payload.type ?? 'system',
          deepLink: payload.deepLink ?? null,
        },
      });
    } catch (_) { /* non bloquant */ }
  }

  /**
   * Envoyer à un utilisateur via son token (ciblé).
   *
   * `category` permet de respecter les interrupteurs de l'écran Paramètres.
   * Les topics FCM ne couvraient que les envois de masse : une notification
   * personnelle part par token, donc se désabonner du topic « referral_alerts »
   * ne la coupait pas — l'interrupteur ne servait à rien.
   *
   * Une notification refusée est quand même enregistrée en base : couper la
   * push ne doit pas effacer la trace dans la liste in-app.
   */
  async sendToUser(userId: string, payload: {
    title: string; body: string; data?: Record<string, string>;
  }, category?: NotifCategory) {
    const user = await prisma.user.findUnique({
      where:  { id: userId },
      select: { notificationPrefs: true, appareils: { select: { jeton: true } } },
    });
    // Toujours sauvegarder en base pour l'historique
    await this._saveNotification(userId, {
      title:    payload.title,
      body:     payload.body,
      type:     payload.data?.['type'],
      deepLink: payload.data?.['deep_link'],
    });
    if (category && !isNotifEnabled(user?.notificationPrefs, category)) {
      journal.info(`[FCM] user ${userId} a coupé « ${category} » — push non envoyée`);
      return { success: false, reason: 'muted' };
    }
    if (!user?.appareils.length) {
      journal.info(`[FCM] Pas de token pour user ${userId} — notif sauvegardée en base`);
      return { success: false, reason: 'no_token' };
    }
    return this._envoyerAuxAppareils(user.appareils.map(a => a.jeton), payload);
  }

  /** Envoyer à un topic FCM (tous les abonnés à ce type de notif) */
  async sendToTopic(topic: string, payload: {
    title: string; body: string; data?: Record<string, string>;
  }) {
    const fa = await getAdmin();
    if (!fa) {
      const refus = sansFirebase();
      if (refus) return refus;
      journal.info(`\n📢 [FCM Topic "${topic}"] ${payload.title}\n   ${payload.body}\n`);
      return { success: true, simulated: true };
    }
    try {
      // `send({ topic })` et non `sendToTopic()`.
      //
      // L'ancienne API n'accepte qu'un `MessagingPayload` : `notification` et
      // `data`, rien d'autre. Les blocs `android` et `apns` ci-dessous la font
      // échouer avec « Messaging payload contains an invalid "android"
      // property » — et comme l'erreur est attrapée puis journalisée, l'appelant
      // reçoit `{ success: false }` sans que rien ne remonte à l'écran.
      //
      // Relevé en production : 109 échecs, zéro succès. Aucune notification par
      // sujet n'était jamais partie depuis la mise en service — donc ni les
      // rappels avant match, ni les résultats, qui passent tous par ici.
      const r = await fa.messaging().send({
        topic,
        notification: { title: payload.title, body: payload.body },
        data:         payload.data ?? {},
        android: {
          priority: 'high',
          notification: { channelId: 'pronowin_high', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' },
        },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      });
      journal.info(`[FCM] Topic "${topic}" ✅`);
      return { success: true, result: r };
    } catch (e: any) {
      journal.error('[FCM] Erreur topic:', e.message);
      return { success: false, error: e.message };
    }
  }

  /**
   * Tous les appareils d'un compte. Réussi dès qu'un appareil a reçu ; les
   * jetons que Firebase déclare morts sont oubliés.
   */
  private async _envoyerAuxAppareils(jetons: string[], payload: {
    title: string; body: string; data?: Record<string, string>;
  }) {
    const fa = await getAdmin();
    if (!fa) {
      const refus = sansFirebase();
      if (refus) return refus;
      journal.info(`\n📱 [FCM ${jetons.length} appareil(s)] ${payload.title}\n   ${payload.body}\n`);
      return { success: true, simulated: true };
    }
    try {
      const r = await fa.messaging().sendEachForMulticast({
        tokens:       jetons,
        notification: { title: payload.title, body: payload.body },
        data:         payload.data ?? {},
        android: {
          priority: 'high',
          notification: { channelId: 'pronowin_high', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' },
        },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      });
      const morts = jetons.filter((_, k: number) =>
        !r.responses[k]?.success && DEAD_TOKEN_CODES.has(r.responses[k]?.error?.code));
      if (morts.length > 0) {
        await prisma.appareilNotification.deleteMany({ where: { jeton: { in: morts } } });
        journal.warn(`[FCM] ${morts.length} appareil(s) au jeton invalide oublié(s)`);
      }
      if (r.successCount === 0) {
        return { success: false, error: r.responses.find((x: any) => x.error)?.error?.message ?? 'echec' };
      }
      journal.info(`[FCM] ✅ ${r.successCount}/${jetons.length} appareil(s)`);
      return { success: true, envoyes: r.successCount, echecs: r.failureCount };
    } catch (e: any) {
      return { success: false, error: e.message };
    }
  }

  // ─── Campagnes par segment (page « Notifications » de l'admin) ────────────

  /**
   * Nombre de destinataires réellement joignables pour un segment.
   *
   * L'admin affichait une estimation issue de `/admin/users/stats` parce que
   * cet endpoint n'existait pas — le chiffre ignorait donc les comptes sans
   * token FCM et ceux ayant coupé la catégorie.
   */
  async previewSegment(segment: string) {
    // Cible unique : ce n'est pas un segment, il n'y a rien à compter.
    if (segment === 'user') return { segment, total: 1, count: 1 };
    const matching = await prisma.user.count({ where: segmentWhere(segment) });
    const reachable = await this._reachableUsers(segment);
    return { segment, total: matching, count: reachable.length };
  }

  /**
   * Envoi d'une campagne à un segment.
   *
   * Par token et non par topic : un topic FCM est un canal, il ne sait pas
   * exprimer « uniquement les Premium » ni « inactifs depuis 30 jours ». C'est
   * aussi ce qui permet de respecter l'interrupteur « Offres & Promotions ».
   */
  async sendToSegment(segment: string, payload: {
    title: string; body: string; deepLink?: string; imageUrl?: string;
  }) {
    const users = await this._reachableUsers(segment);
    if (users.length === 0) return { segment, sent: 0, failed: 0, pruned: 0 };

    // Archivage in-app en une requête plutôt qu'une par destinataire.
    await prisma.notification.createMany({
      data: users.map(u => ({
        userId:   u.id,
        title:    payload.title,
        body:     payload.body,
        type:     CAMPAIGN_CATEGORY,
        deepLink: payload.deepLink ?? null,
      })),
    });

    const fa = await getAdmin();
    if (!fa) {
      if (sansFirebase()) {
        // Les destinataires sont déjà inscrits dans leur historique : ils
        // liront le message dans l'application. Le compte rendu dit ce qui
        // s'est réellement passé côté push.
        return { segment, sent: 0, failed: users.length, pruned: 0, error: 'firebase_non_configure' };
      }
      journal.info(`\n📢 [FCM Segment "${segment}" — ${users.length} destinataires] ${payload.title}\n   ${payload.body}\n`);
      return { segment, sent: users.length, failed: 0, pruned: 0, simulated: true };
    }

    // Un compte peut avoir plusieurs appareils : on envoie par jeton, mais le
    // compte rendu compte des personnes — une personne est atteinte dès qu'un
    // de ses appareils a reçu.
    const envois = users.flatMap(u => u.appareils.map(a => ({ userId: u.id, jeton: a.jeton })));
    const atteints = new Set<string>();
    const dead: string[] = [];

    // FCM plafonne le multicast à 500 jetons par appel.
    for (let i = 0; i < envois.length; i += 500) {
      const lot    = envois.slice(i, i + 500);
      const tokens = lot.map(e => e.jeton);
      try {
        const r = await fa.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: payload.title,
            body:  payload.body,
            ...(payload.imageUrl ? { imageUrl: payload.imageUrl } : {}),
          },
          data: {
            type: CAMPAIGN_CATEGORY,
            ...(payload.deepLink ? { deep_link: payload.deepLink } : {}),
          },
          android: {
            priority: 'high',
            notification: { channelId: 'pronowin_high', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' },
          },
          apns: { payload: { aps: { sound: 'default', badge: 1 } } },
        });
        r.responses.forEach((resp: any, k: number) => {
          if (resp.success) atteints.add(lot[k].userId);
          else if (DEAD_TOKEN_CODES.has(resp.error?.code)) dead.push(tokens[k]);
        });
      } catch (e: any) {
        journal.error('[FCM] Erreur lot segment:', e.message);
      }
    }
    const sent = atteints.size;
    const failed = users.length - sent;

    // Sans ce nettoyage, les jetons morts s'accumulent et le compteur
    // d'audience surestime de plus en plus la portée réelle.
    if (dead.length > 0) {
      await prisma.appareilNotification.deleteMany({ where: { jeton: { in: dead } } });
      journal.warn(`[FCM] ${dead.length} token(s) invalide(s) purgé(s)`);
    }

    journal.info(`[FCM] Segment "${segment}" — ${sent} envoyée(s), ${failed} échec(s)`);
    return { segment, sent, failed, pruned: dead.length };
  }

  /**
   * Destinataires d'un segment ayant un token ET n'ayant pas coupé la
   * catégorie. Le filtre sur les préférences se fait en mémoire : la colonne
   * est un Json et le modèle est opt-out (clé absente = activé), ce qu'une
   * clause Prisma sur `path` exprime mal.
   */
  /**
   * Campagne adressée à un seul compte, désigné par son pseudo ou son numéro.
   *
   * L'interface propose ce mode depuis toujours — « le moyen de tester un
   * message avant de l'envoyer à tous » — mais il n'a jamais fonctionné :
   * `segment: 'user'` n'existe pas dans `segmentWhere`, qui levait
   * « Segment inconnu ». Ce n'est d'ailleurs pas un segment mais une cible
   * unique, d'où une méthode distincte plutôt qu'une septième branche.
   *
   * Les échecs sont explicites : un « 0 envoyé » silencieux laisserait croire
   * à un problème de serveur alors que le pseudo est simplement mal orthographié.
   */
  async sendToHandle(handle: string, payload: {
    title: string; body: string; deepLink?: string; imageUrl?: string;
  }) {
    const recherche = handle.trim();
    if (!recherche) throw new Error('Indiquez le pseudo ou le numéro du destinataire.');

    const user = await prisma.user.findFirst({
      where: {
        deletedAt: null,
        OR: [
          { pseudo:      { equals: recherche, mode: 'insensitive' } },
          { phoneNumber: recherche },
          { email:       { equals: recherche, mode: 'insensitive' } },
        ],
      },
      select: { id: true, pseudo: true, notificationPrefs: true, _count: { select: { appareils: true } } },
    });

    if (!user) throw new Error(`Aucun compte ne correspond à « ${recherche} ».`);

    if (!isNotifEnabled(user.notificationPrefs, CAMPAIGN_CATEGORY)) {
      throw new Error(
        `${user.pseudo} a désactivé les notifications « Offres & Promotions ». ` +
        'Le message est enregistré dans son application mais aucune push ne part.');
    }
    if (user._count.appareils === 0) {
      throw new Error(
        `${user.pseudo} n'a pas de jeton de notification : l'application n'a ` +
        'jamais été ouverte sur cet appareil, ou les notifications y sont refusées.');
    }

    const r = await this.sendToUser(user.id, {
      title: payload.title,
      body:  payload.body,
      data:  {
        type: CAMPAIGN_CATEGORY,
        ...(payload.deepLink ? { deep_link: payload.deepLink } : {}),
      },
    }, CAMPAIGN_CATEGORY);

    const envoye = (r as any)?.success !== false;
    return {
      segment: 'user',
      target:  user.pseudo,
      sent:    envoye ? 1 : 0,
      failed:  envoye ? 0 : 1,
      pruned:  0,
    };
  }

  private async _reachableUsers(segment: string) {
    const users = await prisma.user.findMany({
      where:  { ...segmentWhere(segment), appareils: { some: {} } },
      select: { id: true, notificationPrefs: true, appareils: { select: { jeton: true } } },
    });
    return users.filter(u => isNotifEnabled(u.notificationPrefs, CAMPAIGN_CATEGORY));
  }

  // ─── Notifications automatiques ───────────────────────────────────────────

  /** Notif premium → token direct (données privées) */
  async notifyPremiumActivated(userId: string, durationDays: number) {
    return this.sendToUser(userId, {
      title: 'Premium activé !',
      body:  `Accès Premium actif pour ${durationDays} jours. Profitez des pronostics VIP !`,
      data:  { deep_link: '/pronostics', type: 'system' },
    }, 'premium');
  }

  /** Notif parrainage → token direct (données privées) */
  async notifyReferralConverted(referrerId: string, pseudo: string, commission: number) {
    return this.sendToUser(referrerId, {
      title: 'Parrainage récompensé !',
      body:  `${pseudo} s'est abonné Premium ! +${commission} FCFA crédités.`,
      data:  { deep_link: '/compte', type: 'referral' },
    }, 'referral');
  }

  /** Notif match → topic global + topic par match (favoris) */
  async notifyMatchSoon(homeTeam: string, awayTeam: string, pronosticId: string, matchId?: string) {
    const payload = {
      title: 'Match dans 1 heure !',
      body:  `${homeTeam} vs ${awayTeam} — Consultez notre pronostic maintenant.`,
      data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
    };
    const sends = [this.sendToTopic(FCM_TOPICS.match, payload)];
    if (matchId) sends.push(this.sendToTopic(`match_${matchId}`, payload));
    return Promise.all(sends);
  }

  /** Notif nouveau pronostic publié → topic match (tous abonnés aux alertes matchs) */
  async notifyPronosticPublished(params: {
    homeTeam:        string;
    awayTeam:        string;
    pronosticId:     string;
    predictionLabel: string;
    isPremium:       boolean;
    matchStatus?:    string;
  }) {
    const isLive  = params.matchStatus === 'LIVE';
    // « [VIP] » reste : il dit quelque chose que le titre ne dit pas.
    // Les emojis qui l'accompagnaient, non — ils ne faisaient que decorer.
    const prefix  = params.isPremium ? '[VIP] ' : '';
    const title   = isLive
      ? `${prefix}Pronostic EN DIRECT`
      : `${prefix}Nouveau pronostic publié`;

    // Le corps ne révèle la décision que si le pronostic est gratuit.
    //
    // Cette notification part sur le topic global : tout le monde la reçoit,
    // abonné ou non. Elle contenait `predictionLabel` dans tous les cas — un
    // utilisateur gratuit lisait donc le pronostic VIP dans son fil, sans
    // ouvrir l'application, sans payer. Le titre le lui signalait même :
    // le préfixe « 👑 [VIP] » annonçait la valeur de ce qu'il obtenait pour
    // rien.
    //
    // La fonction *savait* : `isPremium` servait déjà à choisir l'emoji. La
    // même donnée décide maintenant du corps. Le rappel part toujours à tous
    // — il n'y a aucune raison de cacher l'existence d'un pronostic VIP,
    // seulement son contenu.
    const affiche = params.isPremium ? 'pronostic VIP disponible'
                                     : params.predictionLabel;
    const body    = isLive
      ? `${params.homeTeam} vs ${params.awayTeam} en cours — ${affiche}`
      : `${params.homeTeam} vs ${params.awayTeam} — ${affiche}`;
    return this.sendToTopic(FCM_TOPICS.match, {
      title, body,
      data: { deep_link: `/pronostics/${params.pronosticId}`, type: 'match' },
    });
  }

  /** Notif résultat de match → topic match */
  async notifyMatchResult(params: {
    homeTeam:    string;
    awayTeam:    string;
    homeScore:   number;
    awayScore:   number;
    result:      'WIN' | 'LOSS' | 'PUSH';
    pronosticId: string;
  }) {
    const label = params.result === 'WIN' ? 'Pronostic gagnant !'
                : params.result === 'PUSH' ? 'Pronostic remboursé'
                : 'Pronostic perdant';
    const score  = `${params.homeScore}-${params.awayScore}`;
    return this.sendToTopic(FCM_TOPICS.match, {
      title: `Résultat : ${label}`,
      body:  `${params.homeTeam} vs ${params.awayTeam} — Score final : ${score}`,
      data:  {
        deep_link: `/pronostics/${params.pronosticId}`,
        type:      'match',
      },
    });
  }
}
