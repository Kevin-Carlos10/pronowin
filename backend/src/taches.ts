import { prisma } from './lib/prisma';
import logger from './utils/logger';
import { PronosticsService } from './services/pronostics.service';
import { signalerAchatsEnRetard, SEUIL_ATTENTE_HEURES, INTERVALLE_CONTROLE_MS } from './services/alerte_achats.service';
import { SubscriptionService } from './services/subscription.service';
import { FileNotificationsIap } from './services/iap_notifications.service';
import { suivre } from './services/etat_taches';
import { executerProgrammationsEchues } from './services/programmations.service';
import { rapprocherPaiementsEnAttente } from './services/geniuspay.service';
import { envoyerBilanHebdo } from './services/bilan_hebdo.service';
import { publierResumes } from './services/resumes_match.service';

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

    // Sync intelligente (rythme adaptatif, 18 octobre 2026) : 15 s quand un
    // match suivi est en direct, 60 s pour le reste du direct mondial, 2 min
    // sans direct — voir `delaiSynchronisation`. Des matchs
    // (Amériques, Asie...) sont live en dehors de la plage 5h-23h UTC qu'on
    // excluait avant ; avec la marge de quota dégagée par le throttle du
    // filet de sécurité, plus besoin de ce blackout.
    const runSync = async () => {
      await suivre('synchronisation_scores', () => pronoSvc.syncMatchScores()).catch((err: Error) =>
        logger.error('[ScoreSync] Erreur', { message: err.message }));
    };

    const scheduleLiveSync = () => delaiSynchronisation();

    // Boucle adaptative : re-planifie selon présence de matchs LIVE. Un seul
    // minuteur à la fois : le garder dans la liste l'allongerait sans fin.
    const adaptiveSync = async () => {
      await runSync();
      const delay = await scheduleLiveSync();
      if (!arrete) prochaineSync = setTimeout(adaptiveSync, delay);
    };

    prochaineSync = setTimeout(adaptiveSync, 30_000);
    logger.info('Score sync actif — 15 s si un match suivi est en direct, 60 s sinon, 2 min sans direct (24h/24)');

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

    // Résumés des matchs pronostiqués terminés, pour les actualités de
    // l'accueil (resumes_match.service.ts) : un appel au fournisseur par match.
    const runResumes = () => {
      suivre('resumes_match', () => publierResumes(), ({ publies }) => `${publies} publié(s)`)
        .catch((err: Error) => logger.error('[Résumés] Erreur', { message: err.message }));
    };
    programmer(setTimeout(runResumes, 3 * 60_000));
    programmer(setInterval(runResumes, 10 * 60_000));
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

  // ─── PUBLICATIONS ET NOTIFICATIONS PROGRAMMÉES ────────────────────────────
  // Hors du bloc football, pour la même raison que l'alerte ci-dessus : une
  // notification programmée ne dépend pas de la clé du fournisseur.
  programmer(setInterval(() => {
    suivre('programmations', () => executerProgrammationsEchues(),
      ({ executees }) => `${executees} exécutée(s)`).catch((err: Error) =>
      logger.error('[Programmations] Erreur', { message: err.message }));
  }, 60_000));

  // ─── PAIEMENTS GENIUSPAY ──────────────────────────────────────────────────
  // Filet du webhook : un paiement confirmé chez GeniusPay dont aucune
  // notification n'est arrivée (et que l'abonné n'a pas rouvert dans l'app)
  // est retrouvé ici. Hors du bloc football, comme les alertes ci-dessus.
  programmer(setInterval(() => {
    suivre('rapprochement_geniuspay', () => rapprocherPaiementsEnAttente(),
      ({ examines }) => `${examines} examiné(s)`).catch((err: Error) =>
      logger.error('[GeniusPay] Rapprochement', { message: err.message }));
  }, 5 * 60_000));

  // ─── BILAN DE LA SEMAINE ──────────────────────────────────────────────────
  // Le lundi, aux comptes gratuits (bilan_hebdo.service.ts). Vérifié toutes
  // les heures : l'historique des notifications dit s'il est déjà parti.
  const runBilanHebdo = () => {
    suivre('bilan_hebdo', () => envoyerBilanHebdo(),
      (r) => r.envoye ? `${r.destinataires} destinataire(s)` : (r.raison ?? '')).catch((err: Error) =>
      logger.error('[BilanHebdo] Erreur', { message: err.message }));
  };
  programmer(setTimeout(runBilanHebdo, 5 * 60_000));
  programmer(setInterval(runBilanHebdo, 60 * 60_000));

  return () => {
    arrete = true;
    if (prochaineSync) clearTimeout(prochaineSync);
    minuteurs.forEach(clearTimeout);
  };
}

/**
 * Délai avant la prochaine synchronisation des scores.
 *
 * - 15 s : un match en direct que nos utilisateurs regardent — pronostic
 *   publié, ou mis en favori. API-Football rafraîchit son direct toutes les
 *   15 s environ : plus vite ne servirait à rien.
 * - 60 s : du direct ailleurs dans le monde, que personne ne suit ici.
 * - 2 min : aucun match en direct.
 *
 * Jusqu'au 18 octobre, tout direct imposait 30 s, 24 h sur 24 (il y a
 * toujours un match en cours quelque part) : 2 880 appels par jour pour le
 * seul direct, et le même retard pour un match suivi que pour un match de
 * division régionale.
 */
export async function delaiSynchronisation(): Promise<number> {
  try {
    const suivi = await prisma.match.count({ where: {
      status: 'LIVE',
      OR: [{ hasPublishedPronostic: true }, { favoritedBy: { some: {} } }],
    } });
    if (suivi > 0) return 15_000;
    const enDirect = await prisma.match.count({ where: { status: 'LIVE' } });
    return enDirect > 0 ? 60_000 : 2 * 60_000;
  } catch {
    // Base injoignable : rythme intermédiaire, sans emballer le quota.
    return 60_000;
  }
}
