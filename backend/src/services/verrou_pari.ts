/**
 * Jusqu'à quand un pari peut-il être enregistré dans la bankroll ?
 *
 * ── Ce qui n'était vérifié nulle part ──────────────────────────────────────
 *
 * `placeBet` contrôlait le solde, le montant et les doublons. Pas le match.
 * On pouvait donc enregistrer une mise sur un pronostic **déjà réglé**, dont
 * le résultat est public — et rien ne distinguait ensuite cette ligne d'un
 * pari posé avant le coup d'envoi.
 *
 * Ce n'est pas qu'une faille d'API. L'écran masquait le bouton « Miser » sur
 * `status == 'finished'` seulement : pendant un match **en direct**, avec un
 * score déjà affiché, le bouton restait là. Le parcours normal de
 * l'application permettait de miser en connaissant une partie du résultat.
 *
 * ── Pourquoi cela compte au-delà d'un compte ──────────────────────────────
 *
 * La bankroll n'est pas un pari réel chez un bookmaker : c'est le suivi que
 * PronoWin tient. Mais ce suivi alimente les statistiques de l'utilisateur, et
 * surtout le **classement public**. Un historique où l'on peut ajouter après
 * coup les paris gagnants rend le classement invérifiable — et le classement
 * est l'argument qui donne du crédit au reste.
 *
 * ── La date fait autorité, pas seulement le statut ────────────────────────
 *
 * `status` est tenu à jour par une synchronisation périodique (30 s en direct,
 * 2 min sinon). Entre le coup d'envoi et la synchronisation suivante, un match
 * commencé porte encore `SCHEDULED`. Se fier au seul statut laisserait donc
 * une fenêtre ouverte à chaque match. L'heure de coup d'envoi, elle, est celle
 * que l'application affiche partout : c'est elle qui ferme la saisie.
 */

/** Pourquoi un pari est refusé. Aucun refus n'est silencieux. */
export type RefusPari =
  | 'resultat_connu'
  | 'match_commence'
  | 'match_reporte';

/** Statuts qui signifient que le match n'est plus à venir. */
const PLUS_A_VENIR = new Set(['live', 'finished', 'suspended']);

/** Ce qu'on dit à l'utilisateur pour chaque refus. */
export const MESSAGE_REFUS: Record<RefusPari, string> = {
  resultat_connu:
    'Ce pronostic est déjà réglé : son résultat est connu.',
  match_commence:
    'Le match a commencé : les mises ne sont plus enregistrées.',
  match_reporte:
    'Ce match est reporté. Les mises rouvriront quand une nouvelle date sera connue.',
};

/**
 * Le pari peut-il encore être enregistré ? `null` si oui, le motif sinon.
 *
 * @param resultat    résultat du pronostic (`WIN` / `LOSS` / `PUSH`), `null` tant
 *                    qu'il n'est pas réglé
 * @param statutMatch statut du match, dans la casse où il arrive
 * @param dateMatch   heure du coup d'envoi
 * @param maintenant  injectable pour les bancs
 */
export function refusDePari(params: {
  resultat:     string | null | undefined;
  statutMatch:  string | null | undefined;
  dateMatch:    Date | null | undefined;
  maintenant?:  Date;
}): RefusPari | null {
  const { resultat, statutMatch, dateMatch } = params;
  const maintenant = params.maintenant ?? new Date();

  // Un pronostic réglé n'a plus rien d'incertain, quel que soit l'état du match.
  if (resultat != null && resultat !== '') return 'resultat_connu';

  const statut = (statutMatch ?? '').toLowerCase();
  if (statut === 'postponed') return 'match_reporte';
  if (PLUS_A_VENIR.has(statut)) return 'match_commence';

  // Le statut peut être en retard d'une synchronisation ; l'heure, non.
  if (dateMatch != null && dateMatch.getTime() <= maintenant.getTime()) {
    return 'match_commence';
  }

  return null;
}
