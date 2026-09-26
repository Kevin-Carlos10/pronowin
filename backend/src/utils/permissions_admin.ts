import { ActeurAdmin } from './delegation_admin';

/**
 * Ce qu'un sous-administrateur a le droit de demander à cette API.
 *
 * ── Pourquoi l'API le vérifie elle-même ────────────────────────────────────
 *
 * Les permissions des sous-administrateurs vivaient dans le seul panneau
 * (`requirePerm`). Elles voyageaient dans la délégation signée, mais aucune
 * route ne les lisait : l'API s'en remettait entièrement au panneau. Une faille
 * du panneau devenait donc une faille de l'API — c'est ce qu'a montré la
 * substitution d'identité par le cookie `admin_sub_id` (audit du 24 septembre
 * 2026, constats S7 et S8).
 *
 * Chaque route d'administration est rattachée ici à la section et au niveau
 * que le panneau exige pour l'écran qui l'appelle. Le catalogue des sections
 * est celui du panneau (`admin-web/lib/permissions.js`).
 *
 * ── Fermeture par défaut ───────────────────────────────────────────────────
 *
 * Une route d'administration absente de cette table est refusée à tout
 * sous-administrateur. Ajouter une route sans la déclarer ici la réserve donc
 * à l'administrateur principal, au lieu de l'ouvrir à tous. Le banc
 * `permissions_admin.test.ts` recense les routes déclarées dans `routes/` et
 * échoue si l'une d'elles n'est pas classée.
 */

export type Niveau = 'read' | 'write' | 'delete';

/** Ce que demande une route. */
export type Exigence =
  /** Réservée à l'administrateur principal. */
  | { acces: 'principal' }
  /** Toute session du panneau — tableau de bord, compteurs anodins. */
  | { acces: 'toute_session' }
  /** Une des sections, au niveau donné. */
  | { acces: 'section'; sections: string[]; niveau: Niveau };

type Regle = [methode: RegExp, chemin: RegExp, exigence: Exigence];

const LIRE  = /^GET$/;
const ECRIRE = /^(POST|PUT|PATCH)$/;
const SUPPR = /^DELETE$/;
const TOUT  = /^(GET|POST|PUT|PATCH|DELETE)$/;

const section = (sections: string | string[], niveau: Niveau): Exigence =>
  ({ acces: 'section', sections: Array.isArray(sections) ? sections : [sections], niveau });

/**
 * Chemins relatifs à `/api/v1`, sans chaîne de requête. L'ordre compte : la
 * première règle qui correspond s'applique.
 */
const REGLES: Regle[] = [
  // ── Tableau de bord : lu par toute session ──
  [LIRE,   /^\/admin\/stats\/online$/,                          { acces: 'toute_session' }],
  [LIRE,   /^\/pronostics\/admin\/stats$/,                      { acces: 'toute_session' }],

  // ── Journal : toute session écrit ses propres actions ; l'auteur vient de
  //    la délégation, pas du corps. La vérification est réservée au principal.
  [ECRIRE, /^\/admin\/journal$/,                              { acces: 'toute_session' }],
  [LIRE,   /^\/admin\/journal\/verification$/,                { acces: 'principal' }],

  // ── Réservé à l'administrateur principal ──
  [TOUT,   /^\/admin\/(app-config|promo-stats|profile\/password|sante)$/, { acces: 'principal' }],
  [TOUT,   /^\/admin\/payment-methods(\/[^/]+)?$/,              { acces: 'principal' }],

  // ── Statistiques ──
  [LIRE,   /^\/admin\/stats\/[a-z-]+$/,                         section('statistiques', 'read')],

  // ── Utilisateurs ──
  [LIRE,   /^\/admin\/users(\/online|\/stats|\/export\/csv|\/[^/]+)?$/, section('users', 'read')],
  [ECRIRE, /^\/admin\/users\/bulk\/(suspend|notify)$/,          section('users', 'write')],
  [ECRIRE, /^\/admin\/users\/[^/]+\/(suspend|premium|notify|pseudo)$/, section('users', 'write')],
  [SUPPR,  /^\/admin\/users\/[^/]+\/premium$/,                  section('users', 'write')],

  // ── Versements (parrainage) ──
  [LIRE,   /^\/payments\/admin\/(pending|methods)$/,            section('transactions', 'read')],
  [ECRIRE, /^\/payments\/admin\/[^/]+$/,                        section('transactions', 'write')],

  // ── Historique des versements ──
  // La recherche globale du panneau le lit au titre de l'une ou l'autre section.
  [LIRE,   /^\/admin\/history(\/stats|\/export\/csv)?$/,        section(['historique', 'transactions'], 'read')],
  [ECRIRE, /^\/admin\/history\/[^/]+$/,                         section('historique', 'write')],

  // ── Abonnements (preuves Premium) ──
  [LIRE,   /^\/subscriptions\/admin\/proofs$/,                  section('abonnements', 'read')],
  [ECRIRE, /^\/subscriptions\/admin\/proofs\/[^/]+$/,           section('abonnements', 'write')],

  // ── Bankroll ──
  [LIRE,   /^\/bankroll\/admin\/(list|stats|[^/]+)$/,           section('bankroll', 'read')],

  // ── Pronostics ──
  [LIRE,   /^\/pronostics\/admin\/(leagues|upcoming)$/,         section('pronostics', 'read')],
  [LIRE,   /^\/pronostics\/admin\/match\/[^/]+(\/odds|\/prediction)?$/, section('pronostics', 'read')],
  // Relevé des scores affichés dans la liste : un POST, mais une lecture.
  [ECRIRE, /^\/pronostics\/admin\/scores$/,                     section('pronostics', 'read')],
  [ECRIRE, /^\/pronostics\/admin\/(leagues-bulk|leagues\/[^/]+|pronostic|sync-scores)$/, section('pronostics', 'write')],
  [ECRIRE, /^\/pronostics\/admin\/pronostic\/[^/]+\/(publish|result|set-daily)$/, section('pronostics', 'write')],
  [ECRIRE, /^\/comments\/[^/]+\/expert$/,                       section('pronostics', 'write')],

  // ── Tutoriels ──
  [LIRE,   /^\/admin\/tutorials(\/stats|\/categories|\/levels|\/[^/]+)?$/, section('tutoriels', 'read')],
  [ECRIRE, /^\/admin\/tutorials(\/seed|\/[^/]+|\/[^/]+\/premium)?$/, section('tutoriels', 'write')],
  [SUPPR,  /^\/admin\/tutorials\/[^/]+$/,                       section('tutoriels', 'delete')],

  // ── Notifications ──
  [LIRE,   /^\/admin\/notifications\/preview$/,                 section('notifications', 'read')],
  [ECRIRE, /^\/admin\/notifications\/send$/,                    section('notifications', 'write')],
  [ECRIRE, /^\/notifications\/admin\/(send-user\/[^/]+|send-topic)$/, section('notifications', 'write')],
];

/** L'exigence d'une route, ou `null` si elle n'est pas déclarée. */
export function exigenceDe(methode: string, chemin: string): Exigence | null {
  const m = methode.toUpperCase();
  for (const [meth, motif, exigence] of REGLES) {
    if (meth.test(m) && motif.test(chemin)) return exigence;
  }
  return null;
}

const ORDRE: Record<Niveau, number> = { read: 1, write: 2, delete: 3 };

/**
 * Le niveau accordé sur une section : le plus élevé des entrées qui la
 * concernent. Une clé nue (`"users"`) vaut « write » — la règle de
 * rétrocompatibilité du panneau.
 */
export function niveauAccorde(perms: string[], cle: string): Niveau | null {
  let meilleur: Niveau | null = null;
  for (const p of perms) {
    if (typeof p !== 'string') continue;
    const [k, n] = p.split(':');
    if (k !== cle) continue;
    const niveau: Niveau | null = n === undefined ? 'write'
      : (n === 'read' || n === 'write' || n === 'delete') ? n : null;
    if (niveau && (!meilleur || ORDRE[niveau] > ORDRE[meilleur])) meilleur = niveau;
  }
  return meilleur;
}

export type Verdict = { ok: true } | { ok: false; raison: string };

/**
 * L'acteur peut-il faire cette requête ?
 *
 * [chemin] est relatif à `/api/v1`, sans chaîne de requête.
 */
export function acteurAutorise(acteur: ActeurAdmin, methode: string, chemin: string): Verdict {
  if (acteur.role === 'main') return { ok: true };

  const exigence = exigenceDe(methode, chemin);
  if (!exigence) return { ok: false, raison: 'route non déclarée pour les sous-administrateurs' };
  if (exigence.acces === 'toute_session') return { ok: true };
  if (exigence.acces === 'principal') return { ok: false, raison: 'réservé à l\'administrateur principal' };

  for (const cle of exigence.sections) {
    const accorde = niveauAccorde(acteur.perms, cle);
    if (accorde && ORDRE[accorde] >= ORDRE[exigence.niveau]) return { ok: true };
  }
  return {
    ok: false,
    raison: `permission « ${exigence.sections.join(' » ou « ')} » (${exigence.niveau}) requise`,
  };
}

/** `/api/v1/admin/users?page=2` → `/admin/users`. */
export function cheminRelatif(urlOriginale: string): string {
  const sansRequete = urlOriginale.split('?')[0];
  return sansRequete.replace(/^\/api\/v1(?=\/)/, '').replace(/\/+$/, '') || '/';
}
