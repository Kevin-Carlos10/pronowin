
import { prisma } from '../lib/prisma';

// Topics FCM — correspondent aux préférences utilisateur côté Flutter
export const FCM_TOPICS = {
  match:    'match_alerts',
  promo:    'promo_alerts',
  referral: 'referral_alerts',
  payment:  'payment_alerts',
  premium:  'premium_alerts',
  all:      'all_users',
};

let admin: any = null;
async function getAdmin() {
  if (admin) return admin;
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.FIREBASE_PRIVATE_KEY) {
    console.warn('[FCM] Firebase non configuré — mode console');
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
    console.log('[FCM] firebase-admin initialisé ✅');
    return admin;
  } catch (e: any) {
    console.error('[FCM] Erreur init:', e.message);
    return null;
  }
}

export class NotificationService {

  async registerToken(userId: string, fcmToken: string, platform: string) {
    await prisma.user.update({ where: { id: userId }, data: { fcmToken } });
    console.log(`[FCM] Token enregistré — user ${userId}`);
    return { success: true };
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

  /** Envoyer à un utilisateur via son token (ciblé) */
  async sendToUser(userId: string, payload: {
    title: string; body: string; data?: Record<string, string>;
  }) {
    const user = await prisma.user.findUnique({
      where: { id: userId }, select: { fcmToken: true },
    });
    // Toujours sauvegarder en base pour l'historique
    await this._saveNotification(userId, {
      title:    payload.title,
      body:     payload.body,
      type:     payload.data?.['type'],
      deepLink: payload.data?.['deep_link'],
    });
    if (!user?.fcmToken) {
      console.log(`[FCM] Pas de token pour user ${userId} — notif sauvegardée en base`);
      return { success: false, reason: 'no_token' };
    }
    return this._sendToToken(user.fcmToken, payload);
  }

  /** Envoyer à un topic FCM (tous les abonnés à ce type de notif) */
  async sendToTopic(topic: string, payload: {
    title: string; body: string; data?: Record<string, string>;
  }) {
    const fa = await getAdmin();
    if (!fa) {
      console.log(`\n📢 [FCM Topic "${topic}"] ${payload.title}\n   ${payload.body}\n`);
      return { success: true, simulated: true };
    }
    try {
      const r = await fa.messaging().sendToTopic(topic, {
        notification: { title: payload.title, body: payload.body },
        data:         payload.data ?? {},
        android: {
          priority: 'high',
          notification: { channelId: 'pronowin_high', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' },
        },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      });
      console.log(`[FCM] Topic "${topic}" ✅`);
      return { success: true, result: r };
    } catch (e: any) {
      console.error('[FCM] Erreur topic:', e.message);
      return { success: false, error: e.message };
    }
  }

  private async _sendToToken(fcmToken: string, payload: {
    title: string; body: string; data?: Record<string, string>;
  }) {
    const fa = await getAdmin();
    if (!fa) {
      console.log(`\n📱 [FCM] ${payload.title}\n   ${payload.body}\n`);
      return { success: true, simulated: true };
    }
    try {
      const messageId = await fa.messaging().send({
        token:        fcmToken,
        notification: { title: payload.title, body: payload.body },
        data:         payload.data ?? {},
        android: {
          priority: 'high',
          notification: { channelId: 'pronowin_high', sound: 'default', clickAction: 'FLUTTER_NOTIFICATION_CLICK' },
        },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      });
      console.log(`[FCM] ✅ Token — messageId: ${messageId}`);
      return { success: true, messageId };
    } catch (e: any) {
      if (e.code === 'messaging/registration-token-not-registered') {
        await prisma.user.updateMany({ where: { fcmToken }, data: { fcmToken: null } });
        console.warn('[FCM] Token invalide supprimé');
      }
      return { success: false, error: e.message };
    }
  }

  // ─── Notifications automatiques ───────────────────────────────────────────

  /** Notif paiement → token direct (données privées) */
  async notifyPaymentSuccess(userId: string, amount: number, type: 'deposit' | 'withdrawal') {
    return this.sendToUser(userId, {
      title: type === 'deposit' ? '✅ Dépôt confirmé !' : '✅ Retrait effectué !',
      body:  `${amount.toLocaleString()} FCFA ${type === 'deposit' ? 'crédité' : 'envoyé'} avec succès.`,
      data:  { deep_link: '/depot-retrait', type: 'payment' },
    });
  }

  /** Notif premium → token direct (données privées) */
  async notifyPremiumActivated(userId: string, durationDays: number) {
    return this.sendToUser(userId, {
      title: '🎉 Premium activé !',
      body:  `Accès Premium actif pour ${durationDays} jours. Profitez des pronostics VIP !`,
      data:  { deep_link: '/pronostics', type: 'system' },
    });
  }

  /** Notif parrainage → token direct (données privées) */
  async notifyReferralConverted(referrerId: string, pseudo: string, commission: number) {
    return this.sendToUser(referrerId, {
      title: '💰 Parrainage récompensé !',
      body:  `${pseudo} s'est abonné Premium ! +${commission} FCFA crédités.`,
      data:  { deep_link: '/compte', type: 'referral' },
    });
  }

  /** Notif match → topic global + topic par match (favoris) */
  async notifyMatchSoon(homeTeam: string, awayTeam: string, pronosticId: string, matchId?: string) {
    const payload = {
      title: '⚽ Match dans 1 heure !',
      body:  `${homeTeam} vs ${awayTeam} — Consultez notre pronostic maintenant.`,
      data:  { deep_link: `/pronostics/${pronosticId}`, type: 'match' },
    };
    const sends = [this.sendToTopic(FCM_TOPICS.match, payload)];
    if (matchId) sends.push(this.sendToTopic(`match_${matchId}`, payload));
    return Promise.all(sends);
  }

  /** Notif promo → topic (tous ceux qui ont activé les promos) */
  async notifyPromo(title: string, body: string) {
    return this.sendToTopic(FCM_TOPICS.promo, { title, body, data: { type: 'promo' } });
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
    const prefix  = params.isPremium ? '👑 [VIP] ' : (isLive ? '🔴 ' : '⚽ ');
    const title   = isLive
      ? `${prefix}Pronostic EN DIRECT`
      : `${prefix}Nouveau pronostic publié`;
    const body    = isLive
      ? `${params.homeTeam} vs ${params.awayTeam} en cours — ${params.predictionLabel}`
      : `${params.homeTeam} vs ${params.awayTeam} — ${params.predictionLabel}`;
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
    result:      'WIN' | 'LOSS';
    pronosticId: string;
  }) {
    const won    = params.result === 'WIN';
    const emoji  = won ? '✅' : '❌';
    const score  = `${params.homeScore}-${params.awayScore}`;
    return this.sendToTopic(FCM_TOPICS.match, {
      title: `${emoji} Résultat : ${won ? 'Pronostic gagnant !' : 'Pronostic perdant'}`,
      body:  `${params.homeTeam} vs ${params.awayTeam} — Score final : ${score}`,
      data:  {
        deep_link: `/pronostics/${params.pronosticId}`,
        type:      'match',
      },
    });
  }
}
