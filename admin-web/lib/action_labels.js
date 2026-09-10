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
  pronostic_daily_set:       { label: 'Prono gratuit du jour',   icon: 'star', cat: 'pronostic' },
  scores_synced:             { label: 'Scores resynchronisés',  icon: 'refresh', cat: 'pronostic' },
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
/**
 * Catégories, avec leur libellé d'affichage.
 *
 * `audit.ejs` en tenait une liste de 7 en dur, sur les 9 réellement produites :
 * les entrées « news » et « notification » n'apparaissaient nulle part dans la
 * répartition, qui totalisait donc moins que le nombre d'entrées annoncé. Les
 * icônes y étaient de surcroît des emojis injectés dans `href="#ic-…"`, une
 * référence de sprite qui n'existe pas — elles ne s'affichaient pas.
 */
const CATEGORIES = {
  auth:         { label: 'Auth',          icon: 'key',       color: 'var(--info)' },
  finance:      { label: 'Finance',       icon: 'money',     color: 'var(--success)' },
  user:         { label: 'Utilisateurs',  icon: 'users',     color: '#A78BFA' },
  abonnement:   { label: 'Abonnements',   icon: 'crown',     color: 'var(--warning)' },
  pronostic:    { label: 'Pronostics',    icon: 'ball',      color: 'var(--primary)' },
  tutoriel:     { label: 'Tutoriels',     icon: 'book',      color: '#14B8A6' },
  admin:        { label: 'Admins',        icon: 'lock',      color: 'var(--error)' },
  news:         { label: 'Actualités',    icon: 'news',      color: '#38BDF8' },
  notification: { label: 'Notifications', icon: 'megaphone', color: '#F472B6' },
  autre:        { label: 'Autre',         icon: 'dot',       color: 'var(--text-dim)' },
};

module.exports = { ACTION_LABELS, CATEGORIES };
