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

/**
 * Le niveau réellement accordé sur une section : le plus élevé, pas le premier.
 *
 * Les cases du formulaire cascadent — cocher « Supprimer » coche « Écrire » et
 * « Lire », et les trois partent au serveur. Un compte à qui on accorde tout
 * sur les pronostics est donc enregistré ainsi :
 *
 *     ["pronostics:read", "pronostics:write", "pronostics:delete"]
 *
 * Trois implémentations de cette lecture existaient — `getPermLevel` dans
 * server.js pour l'autorisation, `_getLevel` dans _perm_table.ejs pour le
 * rendu, `getLevelFromArray` dans sub_admins.ejs pour la fenêtre d'édition — et
 * toutes les trois renvoyaient le **premier** niveau rencontré. Sur le tableau
 * ci-dessus, « read ». Conséquences, mesurées :
 *
 *   - l'autorisation traitait ce compte comme un lecteur. `requirePerm(...,
 *     'write')` répondait 403 sur une permission accordée : le système de
 *     permissions granulaires ne fonctionnait au-delà de la lecture pour aucun
 *     compte enregistré depuis l'interface ;
 *   - la fenêtre d'édition n'affichait qu'une case cochée sur trois. On cochait
 *     « Écrire », on enregistrait, le panneau annonçait « Permissions mises à
 *     jour » — ce qui était vrai — et en réouvrant, seule « Lire » était
 *     cochée. Vu de l'utilisateur, l'enregistrement était ignoré ;
 *   - et comme le formulaire repart de ce que la fenêtre affiche, chaque
 *     enregistrement rabaissait silencieusement le compte au niveau affiché.
 *
 * La règle vit ici, et ses trois appelants passent par elle. La rétrocompat de
 * l'ancien format — une clé nue sans niveau — reste traitée comme « write ».
 */
function niveauAccorde(perms, key) {
  let meilleur = null;
  for (const p of perms || []) {
    if (typeof p !== 'string') continue;
    const [k, l] = p.split(':');
    if (k !== key) continue;
    if (l === undefined) { // ancien format : "users" valait write
      if (PERM_LEVELS.indexOf('write') > PERM_LEVELS.indexOf(meilleur)) meilleur = 'write';
      continue;
    }
    if (!PERM_LEVELS.includes(l)) continue;
    if (PERM_LEVELS.indexOf(l) > PERM_LEVELS.indexOf(meilleur)) meilleur = l;
  }
  return meilleur;
}

/** `granted` suffit-il pour `required` ? Ordre : read < write < delete. */
function niveauSuffisant(granted, required) {
  if (!granted) return false;
  return PERM_LEVELS.indexOf(granted) >= PERM_LEVELS.indexOf(required);
}

module.exports = { PERM_LEVELS, PERMISSIONS, niveauAccorde, niveauSuffisant };
