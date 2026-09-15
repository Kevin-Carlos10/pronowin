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
