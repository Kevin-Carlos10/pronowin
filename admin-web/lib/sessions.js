const crypto = require('crypto');
const fs = require('fs');

/**
 * Les sessions du panneau, tenues côté serveur.
 *
 * ── Ce qu'elles remplacent ─────────────────────────────────────────────────
 *
 * Une session était un jeu de cookies : `admin_token` (le jeton d'API),
 * `admin_name`, `admin_role` (signé), `admin_perms` (signé) et `admin_sub_id`.
 * Trois défauts en découlaient, relevés par l'audit du 24 septembre 2026 :
 *
 *   - `admin_sub_id` n'était pas signé, ni même `httpOnly`, et rien ne le liait
 *     au rôle signé. Le panneau relisait à chaque requête les permissions du
 *     compte qu'il désignait : en changeant ce seul cookie, un sous-admin
 *     héritait des droits d'un collègue, écriture comprise (S7) ;
 *   - `admin_name` ne l'était pas davantage, et c'est lui qui nommait l'auteur
 *     de chaque entrée du journal ;
 *   - `admin_token` mettait dans le navigateur du sous-admin le jeton du compte
 *     de service — celui du super-administrateur. Il pouvait le lire et appeler
 *     l'API directement, sans passer par les permissions du panneau (S1).
 *
 * Signer chaque cookie aurait fermé les deux premiers, pas le troisième : un
 * jeton signé reste un jeton lisible. Le navigateur ne porte donc plus qu'un
 * identifiant aléatoire, sans signification. Qui est connecté, avec quel rôle
 * et quel jeton : tout cela vit ici, et le client ne peut plus rien en dire.
 *
 * ── Ce que le fichier contient ─────────────────────────────────────────────
 *
 * L'identifiant remis au navigateur n'est jamais écrit sur le disque : le
 * fichier n'en garde que l'empreinte SHA-256. Une copie de `sessions.json` —
 * une sauvegarde qui traîne — ne permet donc pas de rouvrir une session. Le
 * jeton d'API de l'administrateur principal y figure, lui, puisqu'il faut le
 * retrouver après un redémarrage ; il expire en 8 heures, et le fichier est
 * créé lisible par son seul propriétaire.
 *
 * Le fichier ne sert qu'à survivre à un redémarrage : la table en mémoire fait
 * foi, et un seul processus du panneau tourne. Deux instances ne partageraient
 * pas leurs sessions — c'est l'une des raisons de migrer ces données vers
 * PostgreSQL (constat D01 de l'audit).
 */
function empreinteId(id) {
  return crypto.createHash('sha256').update(String(id)).digest('hex');
}

function creerMagasinSessions({ fichier, ecrireJson, maintenant = () => Date.now() }) {
  /** empreinte de l'identifiant → session */
  const table = new Map();

  try {
    for (const s of JSON.parse(fs.readFileSync(fichier, 'utf8'))) {
      if (s && typeof s.empreinte === 'string' && s.expireLe > maintenant()) {
        table.set(s.empreinte, s);
      }
    }
  } catch { /* pas encore de fichier, ou illisible : on repart sans session */ }

  function persister() {
    const r = ecrireJson(fichier, [...table.values()], 0);
    try { fs.chmodSync(fichier, 0o600); } catch { /* système sans droits POSIX */ }
    return r;
  }

  return {
    /**
     * Ouvre une session et rend l'identifiant à poser dans le cookie.
     * C'est la seule fois où il existe en clair côté serveur.
     */
    ouvrir({ role, subId = null, nom, jeton = null, dureeMs }) {
      if (role !== 'main' && role !== 'sub') throw new Error('Rôle de session inconnu.');
      const id = crypto.randomBytes(32).toString('base64url');
      const t = maintenant();
      const session = {
        empreinte: empreinteId(id), role, subId, nom, jeton,
        ouverteLe: t, expireLe: t + dureeMs,
      };
      table.set(session.empreinte, session);
      persister();
      return { id, session };
    },

    /** La session que désigne ce cookie, ou `null` — jamais une session expirée. */
    lire(id) {
      if (typeof id !== 'string' || id.length < 20) return null;
      const cle = empreinteId(id);
      const session = table.get(cle);
      if (!session) return null;
      if (session.expireLe <= maintenant()) {
        table.delete(cle);
        persister();
        return null;
      }
      return session;
    },

    /** Ferme une session. */
    fermer(session) {
      if (session && table.delete(session.empreinte)) persister();
    },

    /**
     * Ferme toutes les sessions qui répondent au prédicat — celles d'un compte
     * désactivé, supprimé, ou dont le mot de passe vient de changer.
     * Rend le nombre de sessions fermées.
     */
    fermerSi(predicat) {
      let n = 0;
      for (const [cle, s] of table) {
        if (predicat(s)) { table.delete(cle); n++; }
      }
      if (n) persister();
      return n;
    },

    /** Nombre de sessions ouvertes, pour les contrôles. */
    taille() { return table.size; },
  };
}

module.exports = { creerMagasinSessions, empreinteId };
