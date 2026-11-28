import crypto from 'crypto';

/**
 * Qui agit, vraiment, derrière un appel du panneau d'administration.
 *
 * ── Le problème ────────────────────────────────────────────────────────────
 *
 * Les sous-administrateurs n'existent pas dans cette base. Ils vivent dans les
 * fichiers du panneau, et pour joindre cette API le panneau leur donne à tous
 * le **même** jeton : celui du compte de service. Vu d'ici, dix personnes
 * différentes sont un seul administrateur.
 *
 * Deux conséquences. Le journal attribue chaque action au compte de service,
 * donc à personne. Et surtout, ce jeton est posé dans le navigateur du
 * sous-administrateur : il peut le lire et appeler cette API **directement**,
 * sans passer par le panneau — donc sans passer par les permissions que le
 * panneau applique. Une restriction de menu ne protège pas une API.
 *
 * ── Ce que la délégation établit ───────────────────────────────────────────
 *
 * Le panneau signe, à chaque appel, qui agit et avec quels droits. La
 * signature se fait **côté serveur du panneau** : elle ne transite jamais par
 * le navigateur, et un sous-administrateur ne peut donc ni la lire ni la
 * fabriquer.
 *
 * Une requête portant le jeton de service **sans** délégation valable n'a donc
 * pas traversé le panneau. C'est exactement la manœuvre qu'on ferme.
 *
 * ── Et les permissions ─────────────────────────────────────────────────────
 *
 * Longtemps, cette API ne relisait pas les permissions : elle établissait que
 * l'appel était passé par le panneau, où `requirePerm` les applique. C'était
 * une garantie transitive — une faille du panneau devenait une faille de
 * l'API. Les permissions portées par la délégation sont désormais appliquées
 * route par route (`permissions_admin.ts`), et la délégation est exigée sur
 * toute requête, lecture comprise.
 */
export interface ActeurAdmin {
  /** Identifiant du sous-administrateur, ou `main` pour le principal. */
  id:    string;
  nom:   string;
  role:  'main' | 'sub';
  perms: string[];
}

/** Au-delà, une délégation est périmée. */
export const DELEGATION_VALIDITE_MS = 60 * 1000;

export const ENTETE_DELEGATION = 'x-admin-acteur';

/** Signe une délégation. Le panneau en est le seul émetteur. */
export function signerDelegation(
  acteur: ActeurAdmin,
  secret: string,
  maintenant: number = Date.now(),
): string {
  const charge = Buffer
    .from(JSON.stringify({ ...acteur, t: maintenant }))
    .toString('base64url');
  const sig = crypto.createHmac('sha256', secret).update(charge).digest('hex');
  return `${charge}.${sig}`;
}

export type EchecDelegation =
  | 'absente'      // aucun en-tête
  | 'malformee'    // pas deux parties, ou charge illisible
  | 'signature'    // signature fausse
  | 'perimee'      // trop vieille, ou datée dans le futur
  | 'incomplete';  // champs manquants

export type LectureDelegation =
  | { ok: true;  acteur: ActeurAdmin }
  | { ok: false; cause: EchecDelegation };

/**
 * Relit une délégation.
 *
 * La fraîcheur compte autant que la signature : sans elle, une délégation
 * capturée une fois vaudrait pour toujours.
 */
export function lireDelegation(
  entete: string | undefined,
  secret: string,
  maintenant: number = Date.now(),
): LectureDelegation {
  if (!entete) return { ok: false, cause: 'absente' };

  const [charge, sig] = entete.split('.');
  if (!charge || !sig) return { ok: false, cause: 'malformee' };

  const attendue = crypto.createHmac('sha256', secret).update(charge).digest('hex');
  // Comparaison à temps constant : `!==` sur deux chaînes hexadécimales
  // s'arrête au premier caractère différent, ce qui se mesure.
  const a = Buffer.from(sig, 'hex');
  const b = Buffer.from(attendue, 'hex');
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, cause: 'signature' };
  }

  let donnees: any;
  try {
    donnees = JSON.parse(Buffer.from(charge, 'base64url').toString());
  } catch {
    return { ok: false, cause: 'malformee' };
  }

  const age = maintenant - Number(donnees?.t ?? 0);
  // Une date future signale une horloge décalée ou une charge bricolée ; on
  // tolère une seconde d'écart et pas davantage.
  if (!Number.isFinite(age) || age > DELEGATION_VALIDITE_MS || age < -1000) {
    return { ok: false, cause: 'perimee' };
  }

  if (typeof donnees.id !== 'string' || typeof donnees.nom !== 'string'
      || (donnees.role !== 'main' && donnees.role !== 'sub')
      || !Array.isArray(donnees.perms)) {
    return { ok: false, cause: 'incomplete' };
  }

  return {
    ok: true,
    acteur: {
      id: donnees.id, nom: donnees.nom,
      role: donnees.role, perms: donnees.perms,
    },
  };
}

/** Les méthodes qui changent quelque chose, et exigent donc une délégation. */
export function estMutation(methode: string): boolean {
  return ['POST', 'PUT', 'PATCH', 'DELETE'].includes(methode.toUpperCase());
}
