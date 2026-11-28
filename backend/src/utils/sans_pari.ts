/**
 * Version iPhone sans pari, côté serveur.
 *
 * L'app iPhone écarte elle-même les tutoriels des catégories Value Bet,
 * Bankroll, Martingale et Trading (`sansPariProvider`, refus d'Apple du
 * 11 octobre 2026). Ce filtre ne voyait pas les autres : « Psychologie du
 * parieur », classé en Psychologie, s'affichait sur iPhone avec une vignette
 * « Top 5 biais cognitifs dans les paris sportifs » (vidéo de l'utilisateur
 * du 17 octobre 2026), alors que la réponse à Apple affirme qu'il n'y a plus
 * de tutoriel de pari.
 *
 * Fait ici plutôt que dans l'app : le serveur s'applique immédiatement, y
 * compris au build en cours d'examen, sans attendre une nouvelle version.
 */

/** Catégories de tutoriels qui enseignent à parier (même liste que l'app). */
export const CATEGORIES_TUTORIELS_PARI = new Set(['valuebet', 'bankroll', 'martingale', 'trading']);

/**
 * Mots qui signalent un contenu de pari. Large exprès : sur iPhone, mieux
 * vaut masquer un tutoriel de trop qu'en montrer un de pari.
 */
const MOTS_PARI =
  /(^|[^\p{L}])(pari|paris|parier|parieurs?|parieuses?|mises?|miser|bankroll|cotes?|bookmakers?|bets?|betting|bettors?|wagers?|gambl\w*|value ?bets?|martingales?|1xbet)(?=$|[^\p{L}])/iu;

export interface TutorielLisible {
  category?: string | null;
  title?: string | null;
  description?: string | null;
  title_en?: string | null;
  description_en?: string | null;
}

/** Vrai si le tutoriel parle de pari, par sa catégorie ou ses textes. */
export function tutorielDePari(t: TutorielLisible): boolean {
  if (CATEGORIES_TUTORIELS_PARI.has((t.category ?? '').toLowerCase())) return true;
  return [t.title, t.description, t.title_en, t.description_en]
    .some(texte => !!texte && MOTS_PARI.test(texte));
}

/** Vrai si la requête vient de l'app iPhone (en-tête `X-App-Plateforme`). */
export function requeteIphone(entetes: Record<string, unknown> | undefined): boolean {
  const v = entetes?.['x-app-plateforme'];
  const brut = typeof v === 'string' ? v : Array.isArray(v) && typeof v[0] === 'string' ? v[0] : '';
  return brut.trim().toLowerCase() === 'ios';
}
