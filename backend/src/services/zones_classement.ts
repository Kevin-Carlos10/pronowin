/**
 * Zones de qualification et de relégation d'un classement.
 *
 * Un classement sans ses zones ne dit pas ce qui se joue. « 7ᵉ avec 3 points »
 * ne signifie rien tant qu'on ignore si la 7ᵉ place qualifie pour l'Europe ou
 * frôle la relégation — et c'est précisément l'information qu'un parieur
 * cherche : une équipe qui joue son maintien ne dispute pas le même match
 * qu'une équipe déjà sauvée.
 *
 * API-Football porte cette information dans `description`, en anglais et sous
 * une forme libre : « Promotion - Champions League (Group Stage) »,
 * « Relegation - LaLiga2 ». Elle n'était pas récupérée.
 */

/** Nature de la zone — décide de la couleur, indépendamment du libellé exact. */
export type NatureZone =
  | 'c1'          // Ligue des champions
  | 'c3'          // Ligue Europa
  | 'c4'          // Ligue Conférence
  | 'barrage'     // Barrages, promotion ou maintien
  | 'promotion'   // Montée directe
  | 'relegation'; // Descente

export interface Zone {
  libelle: string;
  nature:  NatureZone;
}

/**
 * Motifs reconnus, du plus spécifique au plus général.
 *
 * L'ordre compte : « Europa Conference League » contient « Europa », et serait
 * classé en C3 si la règle C3 passait d'abord.
 */
const MOTIFS: Array<[RegExp, Zone]> = [
  [/conference/i,                 { libelle: 'Ligue Conférence',        nature: 'c4' }],
  [/champions\s*league/i,         { libelle: 'Ligue des champions',     nature: 'c1' }],
  [/europa\s*league/i,            { libelle: 'Ligue Europa',            nature: 'c3' }],
  [/relegation\s*play|play.?off.*relegation/i,
                                  { libelle: 'Barrage de relégation',   nature: 'barrage' }],
  [/relegation|descent/i,         { libelle: 'Relégation',              nature: 'relegation' }],
  [/promotion\s*play|play.?off/i, { libelle: 'Barrage de promotion',    nature: 'barrage' }],
  [/promotion/i,                  { libelle: 'Promotion',               nature: 'promotion' }],
];

const inconnues = new Set<string>();

/**
 * Traduit la description d'une ligne de classement.
 *
 * Une description non reconnue rend `null` plutôt qu'un libellé approximatif :
 * mieux vaut une ligne sans zone qu'une ligne rangée dans la mauvaise. Le
 * journal dit lesquelles ajouter.
 */
export function zoneDepuisDescription(description: unknown): Zone | null {
  if (typeof description !== 'string') return null;
  const texte = description.trim();
  if (!texte) return null;

  for (const [motif, zone] of MOTIFS) {
    if (motif.test(texte)) return zone;
  }

  if (!inconnues.has(texte)) {
    inconnues.add(texte);
    console.warn(`[Classement] zone non reconnue : « ${texte} »`);
  }
  return null;
}
