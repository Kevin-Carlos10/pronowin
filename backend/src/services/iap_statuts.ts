/**
 * Les statuts d'un achat store qui donnent accès au Premium, tant que
 * l'échéance n'est pas passée.
 *
 * `canceled` en fait partie. Google l'emploie pour un abonnement dont le
 * renouvellement est coupé mais qui court jusqu'à son terme : l'abonné a payé
 * la période en cours. La liste s'arrêtait à `active` et `grace_period`, et
 * résilier depuis Google Play retirait le Premium le jour même — l'abonné
 * perdait les jours qu'il venait de payer. Apple ne change pas de statut dans
 * ce cas : il garde `active` et coupe seulement le renouvellement.
 *
 * Module à part : `iap.service` importe `subscription.service`, qui en a
 * besoin aussi ; l'importer depuis `iap.service` aurait fermé une boucle.
 */
export const STATUTS_AVEC_ACCES = ['active', 'grace_period', 'canceled'];
