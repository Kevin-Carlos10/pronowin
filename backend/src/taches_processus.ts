import 'dotenv/config';

import { prisma } from './lib/prisma';
import logger from './utils/logger';
import { demarrerTaches } from './taches';
import { publierEtat } from './services/etat_taches';

/**
 * Le processus des tâches planifiées : `pronowin-taches` (constat P1).
 *
 * L'API peut alors tourner en plusieurs exemplaires sans que chaque tâche
 * s'exécute autant de fois. Il n'en faut qu'un : pm2 le relance s'il tombe,
 * et la page Santé du panneau signale un processus muet depuis dix minutes.
 * L'API, elle, ne lance plus les tâches (TACHES_SEPAREES=1).
 */
publierEtat();
const arreterTaches = demarrerTaches();
logger.info('[Tâches] processus pronowin-taches démarré');

let arretEnCours = false;
function arreter(signal: string) {
  if (arretEnCours) return;
  arretEnCours = true;
  logger.info(`[Tâches] ${signal} reçu — arrêt`);
  arreterTaches();
  const limite = setTimeout(() => process.exit(0), 8000);
  limite.unref();
  prisma.$disconnect().finally(() => process.exit(0));
}
process.on('SIGTERM', () => arreter('SIGTERM'));
process.on('SIGINT',  () => arreter('SIGINT'));
