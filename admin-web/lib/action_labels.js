/**
 * Catalogue des actions journalisées — libellé, icône, catégorie.
 *
 * Il vivait dans `server.js`, et `sub_admins.ejs` en tenait une copie réduite à
 * 9 entrées avec des emojis : « logout » et 33 autres actions s'affichaient en
 * anglais brut dans l'activité récente. Le banc d'essai, lui, en avait une
 * troisième version à 3 entrées, donc il ne pouvait pas voir le problème.
 *
 * Une seule source, requise partout : c'est le seul moyen d'empêcher la dérive.
 */
const ACTION_LABELS = {
  login:                     { label: 'Connexion',               icon: 'key', cat: 'auth' },
  logout:                    { label: 'Déconnexion',             icon: 'logout', cat: 'auth' },
  login_failed:              { label: 'Tentative échouée',       icon: 'alert', cat: 'auth' },
  notification_sent:         { label: 'Notification envoyée',    icon: 'megaphone', cat: 'notification' },
  transaction_approved:      { label: 'Versement approuvé',    icon: 'check', cat: 'finance' },
  transaction_rejected:      { label: 'Versement rejeté',      icon: 'x', cat: 'finance' },
  history_updated:           { label: 'Transaction modifiée',    icon: 'clipboard', cat: 'finance' },
  proof_approved:            { label: 'Preuve Premium approuvée',icon: 'crown', cat: 'abonnement' },
  proof_rejected:            { label: 'Preuve Premium rejetée',  icon: 'ban', cat: 'abonnement' },
  user_suspended:            { label: 'Compte suspendu',         icon: 'dot', cat: 'user' },
  user_activated:            { label: 'Compte réactivé',         icon: 'dot', cat: 'user' },
  user_premium_added:        { label: 'Premium accordé',         icon: 'star', cat: 'user' },
  user_premium_revoked:      { label: 'Premium révoqué',         icon: 'x', cat: 'user' },
  user_notified:             { label: 'Notification envoyée',    icon: 'megaphone', cat: 'user' },
  user_pseudo_changed:       { label: 'Pseudo modifié',          icon: 'edit', cat: 'user' },
  pronostic_published:       { label: 'Pronostic publié',        icon: 'ball', cat: 'pronostic' },
  tutorial_created:          { label: 'Tutoriel créé',           icon: 'book', cat: 'tutoriel' },
  tutorial_updated:          { label: 'Tutoriel modifié',        icon: 'edit', cat: 'tutoriel' },
  tutorial_deleted:          { label: 'Tutoriel supprimé',       icon: 'trash', cat: 'tutoriel' },
  tutorial_premium_toggled:  { label: 'Tutoriel Premium togglé', icon: 'crown', cat: 'tutoriel' },
  sub_admin_created:         { label: 'Sous-admin créé',         icon: 'user', cat: 'admin' },
  sub_admin_deleted:         { label: 'Sous-admin supprimé',     icon: 'trash', cat: 'admin' },
  sub_admin_toggled:         { label: 'Sous-admin activé/désactivé', icon: 'refresh', cat: 'admin' },
  sub_admin_perms_updated:   { label: 'Permissions modifiées',   icon: 'lock', cat: 'admin' },
  sub_admin_pwd_changed:     { label: 'Mot de passe sous-admin', icon: 'key', cat: 'admin' },
  settings_changed:          { label: 'Paramètres modifiés',     icon: 'settings', cat: 'admin' },
  user_banned:               { label: 'Utilisateur banni',        icon: 'ban', cat: 'user' },
  user_unbanned:             { label: 'Utilisateur débanni',      icon: 'check', cat: 'user' },
  pronostic_result_override: { label: 'Résultat corrigé',         icon: 'edit', cat: 'pronostic' },
  pronostic_result_force:    { label: 'Résultat forcé (WIN/LOSS)',icon: 'zap', cat: 'pronostic' },
  news_created:              { label: 'Actualité créée',          icon: 'news', cat: 'news' },
  news_updated:              { label: 'Actualité modifiée',       icon: 'edit', cat: 'news' },
  news_published:            { label: 'Actualité publiée',        icon: 'dot', cat: 'news' },
  news_unpublished:          { label: 'Actualité dépubliée',      icon: 'dot', cat: 'news' },
  news_pinned:               { label: 'Actualité épinglée',       icon: 'pin', cat: 'news' },
  news_unpinned:             { label: 'Actualité désépinglée',    icon: 'pin', cat: 'news' },
  news_deleted:              { label: 'Actualité supprimée',      icon: 'trash', cat: 'news' },
  user_bulk_suspended:       { label: 'Comptes suspendus (lot)',  icon: 'dot', cat: 'user' },
  user_bulk_activated:       { label: 'Comptes réactivés (lot)',  icon: 'dot', cat: 'user' },
  user_bulk_notified:        { label: 'Notification groupée',      icon: 'megaphone', cat: 'user' },
  bankroll_exported:         { label: 'Export bankrolls',        icon: 'target', cat: 'finance' },
  league_visibility_toggle:  { label: 'Ligue affichée/masquée',   icon: 'trophy', cat: 'pronostic' },
  league_visibility_bulk:    { label: 'Ligues modifiées en lot',  icon: 'trophy', cat: 'pronostic' },
};
module.exports = { ACTION_LABELS };
