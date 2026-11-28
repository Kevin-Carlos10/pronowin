/**
 * La pagination d'une liste, bornée.
 *
 * Les contrôleurs lisaient `parseInt(req.query.per_page)` tel quel : une page
 * de 5 000 000 lignes chargeait toute la table en mémoire, une page `abc`
 * donnait `NaN` et une erreur 500, une page `0` ou négative un `skip`
 * négatif que Prisma refuse (constat A03 de l'audit du 24 septembre 2026).
 */
export const TAILLE_PAGE_MAX = 100;

export function lirePagination(
  query: Record<string, unknown>,
  { defaut = 20, max = TAILLE_PAGE_MAX }: { defaut?: number; max?: number } = {},
): { page: number; perPage: number } {
  const entier = (v: unknown) => {
    const n = parseInt(String(v ?? ''), 10);
    return Number.isFinite(n) ? n : null;
  };
  const page    = Math.max(1, entier(query.page) ?? 1);
  const demande = entier(query.per_page) ?? defaut;
  const perPage = Math.min(max, Math.max(1, demande));
  return { page, perPage };
}
