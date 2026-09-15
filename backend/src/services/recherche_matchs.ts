import { Prisma } from '@prisma/client';

/**
 * Chercher un match, c'est interroger l'ensemble — pas ce qu'on a sous la main.
 *
 * ── Ce que faisait la recherche ────────────────────────────────────────────
 *
 * L'écran filtrait la liste **déjà chargée** dans le provider : vingt matchs,
 * ceux de la page courante et des filtres courants. Il ne demandait ni les
 * pages suivantes, ni le serveur avec le terme saisi.
 *
 * Une équipe qui existe mais dont la page n'avait pas encore été téléchargée
 * était donc annoncée absente. Le résultat dépendait de l'endroit d'où l'on
 * venait et du nombre de fois qu'on avait fait défiler la liste — un compte
 * qui venait d'ouvrir l'application ne trouvait presque rien.
 *
 * ── Ce que cette recherche couvre ──────────────────────────────────────────
 *
 * Les deux équipes, leurs noms complets quand l'API les fournit, et la
 * compétition. Pas le libellé du pronostic : il est en français, court, et
 * chercher « over » y ramènerait tous les matchs de la journée.
 *
 * La comparaison est insensible à la casse et aux espaces de bord. Elle n'est
 * pas insensible aux accents : Postgres le ferait avec `unaccent`, une
 * extension qui n'est pas installée sur cette base. « Genclerbirligi » ne
 * trouvera donc pas « Gençlerbirliği ». C'est une limite connue, pas un oubli.
 */

/** En deçà, on ne cherche pas : deux lettres ramènent la moitié du catalogue. */
export const RECHERCHE_MIN = 2;

/** Au-delà, la saisie n'est plus un terme de recherche. */
export const RECHERCHE_MAX = 60;

/**
 * Le fragment `where` d'une recherche, ou `{}` s'il n'y a rien à chercher.
 *
 * Rendre `{}` plutôt que de lever : un terme trop court n'est pas une erreur,
 * c'est quelqu'un en train de taper.
 */
export function construireRecherche(
  terme: string | null | undefined,
): Prisma.MatchWhereInput {
  const t = (terme ?? '').trim();
  if (t.length < RECHERCHE_MIN || t.length > RECHERCHE_MAX) return {};

  const contient = { contains: t, mode: 'insensitive' as const };

  return {
    OR: [
      { homeTeam:     contient },
      { awayTeam:     contient },
      { homeTeamFull: contient },
      { awayTeamFull: contient },
      { league:       contient },
    ],
  };
}
