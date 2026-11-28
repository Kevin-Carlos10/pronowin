const { AsyncLocalStorage } = require('node:async_hooks');
const crypto = require('crypto');

/**
 * Qui agit, sur toute la durée d'une requête.
 *
 * ── Pourquoi un stockage de contexte ───────────────────────────────────────
 *
 * Le panneau appelle l'API du backend depuis soixante-trois endroits, tous
 * écrits `api(req.cookies.admin_token)`. Pour que chaque appel dise **qui**
 * agit, il fallait soit passer la requête aux soixante-trois, soit la rendre
 * disponible là où l'appel se fabrique.
 *
 * `AsyncLocalStorage` fait exactement cela : la valeur posée au début de la
 * requête reste lisible dans toute la chaîne asynchrone qui en découle, sans
 * qu'aucun appelant n'ait à la transporter. Aucun des soixante-trois n'a
 * changé.
 *
 * ── Ce que la délégation établit ───────────────────────────────────────────
 *
 * Tous les sous-administrateurs partagent le jeton du compte de service pour
 * joindre l'API : vu du backend, ils sont une seule personne. Ce jeton est
 * dans leur navigateur — ils peuvent le lire et appeler l'API **directement**,
 * sans passer par ce panneau, donc sans passer par `requirePerm`.
 *
 * La délégation est signée ici, côté serveur. Elle ne transite jamais par le
 * navigateur : un sous-administrateur ne peut ni la lire ni la fabriquer. Un
 * appel portant le jeton de service sans délégation n'est donc pas venu d'ici,
 * et le backend le refuse s'il écrit.
 */
const contexte = new AsyncLocalStorage();

/** Exécute [suite] en attachant [acteur] à la requête en cours. */
function executerAvecActeur(acteur, suite) {
  contexte.run({ acteur }, suite);
}

/** L'acteur de la requête en cours, ou `null` hors requête. */
function acteurCourant() {
  return contexte.getStore()?.acteur ?? null;
}

/**
 * Signe une délégation pour [acteur].
 *
 * Le format est celui que `backend/src/utils/delegation_admin.ts` relit :
 * charge en base64url, point, HMAC-SHA256 en hexadécimal. Les deux fichiers
 * doivent rester d'accord — un banc de chaque côté le vérifie sur la même
 * chaîne.
 */
function signerDelegation(acteur, secret, maintenant = Date.now()) {
  const charge = Buffer
    .from(JSON.stringify({ ...acteur, t: maintenant }))
    .toString('base64url');
  const sig = crypto.createHmac('sha256', secret).update(charge).digest('hex');
  return `${charge}.${sig}`;
}

/** Nom de l'en-tête, à tenir identique des deux côtés. */
const ENTETE_DELEGATION = 'X-Admin-Acteur';

module.exports = {
  executerAvecActeur,
  acteurCourant,
  signerDelegation,
  ENTETE_DELEGATION,
};
