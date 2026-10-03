/**
 * Forme canonique d'un identifiant de sous-admin.
 *
 * La création enregistrait `username.trim().toLowerCase()`, mais la connexion
 * et le contrôle de doublon comparaient la saisie brute. Trois conséquences,
 * toutes observées en production le 7 septembre 2026 :
 *
 *   - un compte créé sous « Lonfo_lookman » ne pouvait se connecter qu'en
 *     tapant « lonfo_lookman ». Tapé comme il avait été créé, il tombait dans
 *     la branche « admin principal », qui répondait « Identifiants
 *     incorrects. » — pour un compte existant, actif, au bon mot de passe ;
 *
 *   - le contrôle de doublon comparait « Lonfo_Lookman » à « lonfo_lookman » :
 *     différent, donc accepté. Deux comptes se sont retrouvés sur le même
 *     identifiant, et la connexion en attribue un au hasard du mot de passe ;
 *
 *   - le message d'erreur désignait le mot de passe alors que la faute était
 *     sur la casse de l'identifiant. On cherche donc à côté.
 *
 * La règle vit ici, et non dans chacun de ses trois appelants : c'est
 * exactement la divergence qui a produit la panne. Un identifiant ne dépend ni
 * de la casse ni des espaces de bord — personne ne retient qu'il a mis une
 * majuscule en le créant.
 *
 * Volontairement limité à `trim` + `toLowerCase` : c'est la transformation que
 * la création appliquait déjà, donc les comptes existants restent joignables.
 * Y ajouter autre chose (retirer les accents, les tirets) rendrait
 * introuvables des comptes déjà enregistrés.
 */
function normaliserIdentifiant(v) { return String(v ?? '').trim().toLowerCase(); }

module.exports = { normaliserIdentifiant };
