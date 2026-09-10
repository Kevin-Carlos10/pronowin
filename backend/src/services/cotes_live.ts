/**
 * Cotes en direct : ne montrer que ce qui se lit sans ambiguïté.
 *
 * Deux points d'API, deux formes, un seul analyseur — écrit pour le mauvais :
 *
 *   `/odds`      (pré-match) → { value: "Over 2.5", odd: "1.90" }
 *   `/odds/live`             → { value: "Over",     odd: "1.90", … }
 *
 * Le seuil vit ailleurs sur le flux live, et il était purement et simplement
 * perdu. L'écran affichait alors « Over 7.50 » — sept virgule cinquante étant
 * la **cote**, pas le seuil. Trois lignes Over/Under (1,5 · 2,5 · 3,5)
 * devenaient trois rangées identiques que rien ne distinguait, et un lecteur
 * pouvait prendre la cote pour le nombre de buts.
 *
 * Sur un écran qui accompagne une décision de pari, une information qui se lit
 * à l'envers est pire qu'une information absente.
 */

/** Ce que l'API peut fournir comme porteur de seuil, selon les marchés. */
const CHAMPS_LIGNE = ['handicap', 'line', 'total', 'points', 'goals'];

/**
 * Seuil d'une valeur, quel que soit l'endroit où l'API le place.
 *
 * Le nom du champ n'est pas vérifiable depuis l'environnement de
 * développement : on essaie les porteurs connus, puis le seuil éventuellement
 * inclus dans le libellé (`"Over 2.5"`), et on renonce plutôt que de deviner.
 */
export function extraireLigne(v: any): string | undefined {
  for (const champ of CHAMPS_LIGNE) {
    const brut = v?.[champ];
    if (brut === null || brut === undefined || brut === '') continue;
    const texte = String(brut).trim();
    // Un seuil est un nombre, éventuellement signé : « 2.5 », « -0.5 », « +1 ».
    if (/^[+-]?\d+(?:[.,]\d+)?$/.test(texte)) return texte.replace(',', '.');
  }

  // Repli : le libellé porte parfois le seuil, comme sur le flux pré-match.
  const libelle = String(v?.value ?? '');
  const inclus = libelle.match(/([+-]?\d+(?:[.,]\d+)?)\s*$/);
  return inclus ? inclus[1].replace(',', '.') : undefined;
}

/** Libellé dépouillé de son seuil : « Over 2.5 » → « Over ». */
export function libelleSansLigne(valeur: string): string {
  return valeur.replace(/\s*[+-]?\d+(?:[.,]\d+)?\s*$/, '').trim() || valeur.trim();
}

/**
 * Libellés qui n'ont aucun sens sans seuil.
 *
 * « Plus » de combien ? La question est dans le mot : sans le nombre, la
 * valeur ne dit rien.
 */
const EXIGENT_UNE_LIGNE = new Set([
  'over', 'under', 'plus', 'moins', 'exactly',
]);

/**
 * Un marché est-il lisible tel quel ?
 *
 * Deux cas d'ambiguïté, détectés sans dépendre du nom du marché — ces noms
 * varient d'un bookmaker à l'autre et sont en anglais :
 *
 *  1. un libellé qui exige un seuil (« Over ») et n'en a pas ;
 *  2. un même libellé répété dans le marché — c'est précisément le seuil qui
 *     distingue les répétitions, donc sans lui elles sont interchangeables.
 */
export function marcheLisible(values: LigneValeur[]): boolean {
  const vus = new Map<string, number>();
  for (const v of values) {
    const cle = libelleSansLigne(v.value).toLowerCase();
    vus.set(cle, (vus.get(cle) ?? 0) + 1);
    if (EXIGENT_UNE_LIGNE.has(cle) && !v.ligne) return false;
  }
  for (const [cle, n] of vus) {
    if (n > 1) {
      // Chaque occurrence doit porter son seuil, sinon on ne sait pas laquelle
      // est laquelle.
      const sansLigne = values.filter(
        v => libelleSansLigne(v.value).toLowerCase() === cle && !v.ligne);
      if (sansLigne.length > 0) return false;
    }
  }
  return true;
}

export interface LigneValeur { value: string; odd: number; ligne?: string }

/**
 * Nom de marché en français.
 *
 * Les intitulés arrivent en anglais — « Over/Under Line », « Asian Handicap »
 * — dans une application entièrement française. Un nom inconnu est **rendu
 * tel quel** et journalisé : mieux vaut un mot anglais qu'une traduction
 * inventée, et le journal dit lesquels ajouter.
 */
const NOMS_MARCHES: Record<string, string> = {
  'over/under line':        'Plus / Moins de buts',
  'over/under':             'Plus / Moins de buts',
  'goals over/under':       'Plus / Moins de buts',
  'match goals':            'Total de buts',
  'total':                  'Total',
  'asian handicap':         'Handicap asiatique',
  'handicap':               'Handicap',
  'match winner':           'Vainqueur du match',
  'fulltime result':        'Résultat final',
  'both teams score':       'Les deux équipes marquent',
  'both teams to score':    'Les deux équipes marquent',
  'double chance':          'Double chance',
  'correct score':          'Score exact',
  'first team to score':    'Première équipe à marquer',
  'next goal':              'Prochain but',
  'odd/even':               'Pair / Impair',
  'corners over under':     'Plus / Moins de corners',
  'cards over under':       'Plus / Moins de cartons',
  'half time result':       'Résultat à la mi-temps',
  'to qualify':             'Qualification',
  'result/total goals':     'Résultat et total de buts',
};

const inconnus = new Set<string>();

export function traduireMarche(nom: string): string {
  const cle = nom.trim().toLowerCase();
  const connu = NOMS_MARCHES[cle];
  if (connu) return connu;

  if (cle && !inconnus.has(cle)) {
    inconnus.add(cle);
    console.warn(`[CotesLive] marché non traduit : « ${nom} »`);
  }
  return nom;
}
