/**
 * Combien de codes on accepte d'envoyer à une même adresse, et à quel rythme.
 *
 * ── Ce que cette règle remplace ────────────────────────────────────────────
 *
 * Rien. Le chemin d'envoi n'avait aucun quota :
 *
 *  - `otpLim` (trois demandes par dix minutes) était branché sur
 *    `/auth/send-otp` et **pas** sur `/auth/send-email-otp`. Un commentaire,
 *    juste au-dessus du branchement, affirmait pourtant que « le code par
 *    e-mail […] passe déjà par `otpLim` côté envoi ». C'est très exactement
 *    pourquoi personne ne l'a questionné ;
 *  - `_checkOtpBrute` était bien appelé à l'envoi, mais son compteur n'est
 *    incrémenté que par `_recordOtpFailure`, à la **vérification**. Demander
 *    cent codes ne fait donc monter aucun compteur.
 *
 * Or chaque envoi invalide le précédent. Marteler cette route pour l'adresse
 * de quelqu'un d'autre lui envoie cent courriels, coûte cent envois, et
 * surtout **l'empêche de se connecter** : le code qu'il vient de recevoir est
 * périmé avant qu'il ait fini de le taper.
 *
 * ── Pourquoi une fonction pure ─────────────────────────────────────────────
 *
 * Le compteur en mémoire du contrôleur ne survit ni à un redémarrage ni à une
 * seconde instance. Le quota se lit donc dans la base, où les codes sont déjà
 * enregistrés avec leur date. Cette fonction ne connaît que des dates : elle
 * s'éprouve sans base, et c'est la règle — pas le stockage — qui compte ici.
 */

/** Envois acceptés sur la fenêtre, pour une même adresse. */
export const OTP_ENVOIS_MAX = 3;

/** Largeur de la fenêtre glissante. */
export const OTP_FENETRE_MS = 10 * 60 * 1000;

export interface DecisionEnvoi {
  autorise: boolean;
  /** Minutes à attendre avant le prochain envoi possible. 0 si autorisé. */
  attendreMinutes: number;
}

/**
 * Peut-on envoyer un code de plus ?
 *
 * [envoisRecents] sont les dates des envois déjà faits à cette adresse ; les
 * dates hors fenêtre sont ignorées, l'appelant n'a donc pas à filtrer.
 */
export function decisionEnvoiOtp(
  envoisRecents: Date[],
  maintenant: Date = new Date(),
): DecisionEnvoi {
  const debutFenetre = maintenant.getTime() - OTP_FENETRE_MS;

  const comptes = envoisRecents
    .filter((d) => d.getTime() > debutFenetre)
    .sort((a, b) => a.getTime() - b.getTime());

  if (comptes.length < OTP_ENVOIS_MAX) {
    return { autorise: true, attendreMinutes: 0 };
  }

  // C'est le plus ancien des envois comptés qui sortira de la fenêtre en
  // premier : c'est lui qui date la réouverture.
  const libreA = comptes[0].getTime() + OTP_FENETRE_MS;
  const reste  = libreA - maintenant.getTime();

  // Au moins une minute : annoncer « réessayez dans 0 minute » invite à
  // réessayer tout de suite, pour rien.
  return { autorise: false, attendreMinutes: Math.max(1, Math.ceil(reste / 60000)) };
}

/**
 * Quota d'envoi dépassé.
 *
 * Porte son propre code HTTP : sans cela, le contrôleur rendait 500 pour toute
 * erreur d'envoi, et un quota atteint se présentait à l'utilisateur comme une
 * panne du serveur.
 */
export class QuotaOtpDepasse extends Error {
  readonly statut = 429;

  constructor(attendreMinutes: number) {
    super(
      `Trop de codes demandés pour cette adresse. `
      + `Réessayez dans ${attendreMinutes} minute${attendreMinutes > 1 ? 's' : ''}.`,
    );
    this.name = 'QuotaOtpDepasse';
  }
}
