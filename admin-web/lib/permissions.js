/**
 * Catalogue des permissions granulaires — source unique.
 *
 * Niveaux : 'read' < 'write' < 'delete'
 * Stockage : tableau de chaînes "clé:niveau", ex. ["users:write","transactions:read"]
 * Rétrocompat : ancienne clé simple "users" → traitée comme "users:write"
 *
 * Extrait de server.js parce que le banc d'essai des vues en gardait sa propre
 * copie — une seule entrée, sans `icon`. Il rendait donc « 42/42 vues OK » en
 * n'exerçant qu'un libellé sur dix : renommer les neuf autres passait sans
 * qu'une seule assertion ne s'en aperçoive. Une liste de permissions n'est pas
 * un détail cosmétique ; les deux copies devaient être la même.
 */

const PERM_LEVELS = ['read', 'write', 'delete'];

const PERMISSIONS = [
  {
    key: 'statistiques', label: 'Statistiques', icon: 'chart', desc: 'Graphiques et KPIs',
    levels: { read: 'Voir les stats', write: null, delete: null },
  },
  {
    key: 'users', label: 'Utilisateurs', icon: 'users', desc: 'Gérer les comptes',
    levels: { read: 'Voir les comptes', write: 'Suspendre / accorder Premium', delete: 'Supprimer des comptes' },
  },
  {
    key: 'pronostics', label: 'Pronostics', icon: 'ball', desc: 'Créer et publier',
    levels: { read: 'Voir les pronostics', write: 'Créer / publier', delete: 'Supprimer' },
  },
  {
    key: 'transactions', label: 'Versements', icon: 'card', desc: 'Verser les gains de parrainage',
    levels: { read: 'Voir les versements', write: 'Approuver / rejeter', delete: null },
  },
  {
    key: 'historique', label: 'Historique', icon: 'clipboard', desc: 'Historique des versements',
    levels: { read: 'Voir l\'historique', write: 'Modifier le statut', delete: null },
  },
  {
    key: 'abonnements', label: 'Abonnements', icon: 'crown', desc: 'Valider les preuves Premium',
    levels: { read: 'Voir les preuves', write: 'Approuver / rejeter', delete: null },
  },
  {
    key: 'bankroll', label: 'Bankroll', icon: 'target', desc: 'Suivi des budgets et paris utilisateurs',
    levels: { read: 'Voir les bankrolls', write: null, delete: null },
  },
  {
    key: 'tutoriels', label: 'Tutoriels', icon: 'book', desc: 'Créer et gérer',
    levels: { read: 'Voir les tutoriels', write: 'Créer / modifier', delete: 'Supprimer' },
  },
  {
    key: 'notifications', label: 'Notifications', icon: 'megaphone', desc: 'Notifications push',
    levels: { read: 'Voir l\'historique', write: 'Envoyer des notifications', delete: null },
  },
  {
    key: 'actualites', label: 'Actualités', icon: 'news', desc: 'Créer et publier des articles',
    levels: { read: 'Voir les articles', write: 'Créer / modifier / publier', delete: 'Supprimer' },
  },
];

module.exports = { PERM_LEVELS, PERMISSIONS };
