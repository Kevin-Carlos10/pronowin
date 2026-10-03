/**
 * Environnement minimal des bancs.
 *
 * `admin.middleware.ts` refuse de se charger sans `ADMIN_DELEGATION_SECRET` :
 * ce secret établit qui agit derrière le jeton du compte de service, et un
 * serveur qui démarrerait sans ne pourrait attribuer aucune action
 * d'administration. Ce refus est délibéré — mais il s'applique aussi à toute
 * suite de tests qui importe une route protégée, même indirectement.
 *
 * `pronostics_cache.test.ts` en a fait la démonstration : il importe
 * `pronostics.routes.ts`, qui importe le middleware. Le processus s'arrêtait
 * avant le premier test, et Jest ne rapportait qu'un « worker encountered
 * child process exceptions » — un message qui ne dit rien de la cause.
 *
 * La valeur posée ici n'est évidemment pas celle de production : elle sert à
 * ce que les bancs éprouvent la configuration qu'on exige, plutôt qu'une
 * absence de configuration.
 */
process.env.ADMIN_DELEGATION_SECRET ??= 'delegation-de-banc';

/**
 * Un pool de connexions à la mesure des bancs.
 *
 * Jest lance un processus par cœur moins un — 21 sur un poste de 22 —, et
 * chacun ouvre son client Prisma, dont le pool vaut par défaut deux
 * connexions par cœur plus une : 45. Soit jusqu'à 945 connexions pour une
 * base qui en accepte 100. Les bancs qui écrivent en base se prenaient alors
 * les connexions les uns des autres, et échouaient au hasard — « Unable to
 * start a transaction in the given time », ou un délai de Jest dépassé —
 * sans que le code en cause y soit pour rien. Trois par processus : 63 au
 * plus, sous la limite, avec la marge des connexions déjà ouvertes.
 *
 * Et un délai de connexion de 20 s au lieu de 5 : au démarrage, les 21
 * processus ouvrent leurs connexions ensemble, et certaines attendaient plus
 * de 5 s leur tour — « Can't reach database server » alors que la base
 * tournait.
 */
// Seulement DATABASE_URL : charger tout le fichier .env ici rendrait le
// stockage S3 configuré pour chaque banc, y compris ceux qui éprouvent son
// absence.
const fs = require('fs');
const path = require('path');
const fichierEnv = path.join(__dirname, '.env');
const url = process.env.DATABASE_URL
  ?? (fs.existsSync(fichierEnv) ? require('dotenv').parse(fs.readFileSync(fichierEnv)).DATABASE_URL : undefined);
if (url && !/[?&]connection_limit=/.test(url)) {
  process.env.DATABASE_URL = url + (url.includes('?') ? '&' : '?') + 'connection_limit=3&connect_timeout=20';
}
