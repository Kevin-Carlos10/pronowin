import { prisma } from './lib/prisma';
import logger from './utils/logger';
import { PronosticsService } from './services/pronostics.service';
import { signalerAchatsEnRetard, SEUIL_ATTENTE_HEURES, INTERVALLE_CONTROLE_MS } from './services/alerte_achats.service';
import { SubscriptionService } from './services/subscription.service';
import { FileNotificationsIap } from './services/iap_notifications.service';
import { suivre } from './services/etat_taches';

/**
 * Les tâches planifiées, hors du serveur HTTP (constat P1 de l'audit du
 * 24 septembre 2026).
 *
 * Elles tournaient dans le processus de l'API. Le jour où l'API tourne en deux
 * exemplaires, chaque tâche s'exécute deux fois — rappels d'expiration et
 * notifications doublés — sans que rien ne le signale. Elles vivent désormais
 * ici, et deux processus peuvent les lancer : l'API tant qu'aucun processus
 * dédié n'existe, ou `pronowin-taches` (taches_processus.ts) quand
 * TACHES_SEPAREES=1. Jamais les deux.
 */

export { tachesDansLApi } from './services/etat_taches';

/**
 * Programme toutes les tâches. Renvoie de quoi les arrêter : à l'arrêt du
 * processus, aucune ne doit repartir pendant que la base se ferme.
 */
export function demarrerTaches(): () => void {
  const minuteurs: NodeJS.Timeout[] = [];
  let prochaineSync: NodeJS.Timeout | null = null;
  let arrete = false;
  const programmer = (t: NodeJS.Timeout) => { minuteurs.push(t); return t; };

  // ─── SYNC AUTOMATIQUE DES SCORES ──────────────────────────────────────────
  // Lance une 1ère sync au démarrage, puis selon les matchs en direct.
  // Ne tourne que si la clé API est configurée.
  if (process.env.API_FOOTBALL_KEY) {
    const pronoSvc = new PronosticsService();

    // Sync intelligente : 30s si matchs LIVE, 2min sinon — 24h/24. Des matchs
    // (Amériques, Asie...) sont live en dehors de la plage 5h-23h UTC qu'on
    // excluait avant ; avec la marge de quota dégagée par le throttle du
    // filet de sécurité, plus besoin de ce blackout.
    const runSync = async () => {
      await suivre('synchronisation_scores', () => pronoSvc.syncMatchScores()).catch((err: Error) =>
        logger.error('[ScoreSync] Erreur', { message: err.message }));
    };

    const scheduleLiveSync = async () => {
      const liveCount = await prisma.match.count({ where: { status: 'LIVE' } }).catch(() => 0);
      return liveCount > 0 ? 30_000 : 2 * 60 * 1000;
    };

    // Boucle adaptative : re-planifie selon présence de matchs LIVE. Un seul
    // minuteur à la fois : le garder dans la liste l'allongerait sans fin.
    const adaptiveSync = async () => {
      await runSync();
      const delay = await scheduleLiveSync();
      if (!arrete) prochaineSync = setTimeout(adaptiveSync, delay);
    };

    prochaineSync = setTimeout(adaptiveSync, 30_000);
    logger.info('Score sync actif — 30s si LIVE, 2min sinon (24h/24)');

    const runMatchSoon = () => {
      const hour = new Date().getUTCHours();
      if (hour < 5 || hour > 23) return;
      pronoSvc.checkMatchesSoon().then(({ notified }) => {
        if (notified > 0) logger.info(`[MatchSoon] ${notified} notification(s) envoyée(s)`);
      }).catch(err => logger.error('[MatchSoon] Erreur', { message: err.message }));
    };
    programmer(setTimeout(runMatchSoon, 60_000));
    programmer(setInterval(runMatchSoon, 15 * 60 * 1000));
    logger.info('Notif "match bientôt" actif — toutes les 15 min');
  } else {
    // Le message nommait FOOTBALL_DATA_API_KEY, alors que la variable lue est
    // API_FOOTBALL_KEY : il envoyait chercher la mauvaise (constat I7).
    logger.warn('API_FOOTBALL_KEY manquante — synchronisation des scores désactivée');
  }

  // ─── RAPPEL D'EXPIRATION PREMIUM ──────────────────────────────────────────
  // Sorti du bloc ci-dessus, pour la même raison que l'alerte d'achats plus
  // bas : il ne concerne pas le football, et il se taisait le jour où la clé
  // football manquait (constat I13). L'interrupteur « Abonnement Premium »
  // des Paramètres annonçait cette notification. Une fois par jour :
  // l'idempotence des paliers suppose exactement une exécution quotidienne.
  const subSvc = new SubscriptionService();
  const runExpiryReminder = () => {
    suivre('rappel_expiration', () => subSvc.notifyExpiringSubscriptions(),
      ({ notified }) => `${notified} rappel(s)`).then(({ notified }) => {
      if (notified > 0) logger.info(`[PremiumExpiry] ${notified} rappel(s) envoyé(s)`);
    }).catch(err => logger.error('[PremiumExpiry] Erreur', { message: err.message }));
  };
  programmer(setTimeout(runExpiryReminder, 120_000));
  programmer(setInterval(runExpiryReminder, 24 * 60 * 60 * 1000));
  logger.info('Rappel expiration Premium actif — 1×/jour (J-7, J-3, J-1)');

  // ─── NOTIFICATIONS DES STORES ─────────────────────────────────────────────
  // Le webhook inscrit l'événement puis acquitte ; le traitement a lieu ici,
  // et se refait avec un délai croissant tant qu'il échoue (constat I10).
  const fileIap = new FileNotificationsIap();
  programmer(setInterval(() => {
    suivre('file_notifications_store', () => fileIap.traiterEnAttente(),
      (n) => `${n} examinée(s)`).catch((err: Error) =>
      logger.error('[IAP] File de notifications', { message: err.message }));
  }, 60_000));

  // ─── ACHATS NON ACTIVÉS ───────────────────────────────────────────────────
  // Délibérément hors du bloc football : celui-ci ne tourne que si la clé
  // API football est posée. Une alerte de paiement rangée dedans deviendrait
  // muette le jour où cette clé changerait — et personne ne s'en apercevrait,
  // puisque le propre d'une alerte silencieuse est de ne rien dire.
  const runAchatsEnRetard = () => {
    suivre('alerte_achats', () => signalerAchatsEnRetard(),
      ({ enRetard }) => `${enRetard} en retard`)
      .then(({ enRetard, alerteEnvoyee }) => {
        if (enRetard > 0) {
          logger.warn(
            `[AchatsEnRetard] ${enRetard} en attente — alerte ${alerteEnvoyee ? 'envoyée' : 'NON envoyée'}`,
          );
        }
      })
      .catch((err: Error) =>
        logger.error('[AchatsEnRetard] Erreur', { message: err.message }));
  };
  programmer(setTimeout(runAchatsEnRetard, 180_000));
  programmer(setInterval(runAchatsEnRetard, INTERVALLE_CONTROLE_MS));
  logger.info(
    `Alerte achats non activés — contrôle toutes les ${SEUIL_ATTENTE_HEURES} h`,
  );

  return () => {
    arrete = true;
    if (prochaineSync) clearTimeout(prochaineSync);
    minuteurs.forEach(clearTimeout);
  };
}
