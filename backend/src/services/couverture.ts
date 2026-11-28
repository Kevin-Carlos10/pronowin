/**
 * Couverture d'une mise (26 novembre 2026) — le calcul, sans base ni réseau.
 *
 * L'abonné a misé chez son bookmaker sur une sélection (« Plus de 2,5 buts »
 * à 2,00). Les cotes bougent : un but tôt, et « Moins de 2,5 » monte à 4,00.
 * Miser alors sur l'évènement inverse garantit un gain quel que soit le
 * résultat. Ce module dit :
 *
 * - quelle est la sélection d'un pronostic, et son inverse exact — seulement
 *   pour les marchés à deux issues complémentaires : résultat ↔ double chance
 *   opposée, Plus ↔ Moins de N buts, les deux équipes marquent oui ↔ non,
 *   « remboursé si match nul » d'une équipe ↔ de l'autre ; ailleurs (score
 *   exact, handicap, quart de ligne…), rien : une couverture imparfaite
 *   promettrait un gain qu'elle ne tient pas ;
 * - la cote de l'inverse dans les marchés reçus, au format avant-match
 *   (« Over 2.5 ») comme au format en direct (« Over » et la ligne à part) ;
 * - combien miser dessus, et ce qui est alors garanti.
 *
 * Deux façons de couvrir (27 novembre 2026) :
 * - gain égal : mise × cote ÷ cote inverse — les deux issues rapportent la
 *   même chose ;
 * - mise remboursée : mise ÷ (cote inverse − 1) — si l'inverse passe, on
 *   récupère sa mise ; si la sélection passe, on garde l'essentiel du gain.
 *
 * Sur une ligne entière (Plus de 2) ou un « remboursé si match nul », les deux
 * mises peuvent être remboursées ensemble (2 buts tout juste, match nul) : ni
 * gain ni perte. `remboursable` le signale, pour que l'écran le dise.
 */

export type Issue = 'Home' | 'Draw' | 'Away';
export type Paire = 'HomeDraw' | 'HomeAway' | 'DrawAway';

export type Selection =
  | { marche: 'resultat'; issue: Issue }
  | { marche: 'double_chance'; paire: Paire }
  | { marche: 'buts'; plus: boolean; ligne: number }
  | { marche: 'btts'; oui: boolean }
  /** Remboursé si match nul (« Home/Away » avant le match, « Draw No Bet » en direct). */
  | { marche: 'nul_rembourse'; issue: 'Home' | 'Away' };

export type Strategie = 'gain_egal' | 'mise_remboursee';
export const STRATEGIES: readonly Strategie[] = ['gain_egal', 'mise_remboursee'];

/** Les deux mises peuvent-elles être remboursées ensemble ? */
export function remboursable(s: Selection): boolean {
  return s.marche === 'nul_rembourse' || (s.marche === 'buts' && Number.isInteger(s.ligne));
}

/** Un marché, quelle que soit sa provenance (avant-match ou direct). */
export interface MarcheCote {
  nom: string;
  valeurs: { valeur: string; cote: number; ligne?: string }[];
}

// ─── La sélection d'un pronostic ─────────────────────────────────────────────

/**
 * Une ligne de buts couvrable : demi (2,5) ou entière (2). Pas un quart
 * (2,25) : la mise y est coupée en deux, l'inverse n'est plus exact.
 */
const LIGNE_COUVRABLE = (n: number) => Number.isFinite(n) && n >= 0 && Math.abs(n * 2 - Math.round(n * 2)) < 1e-9;

/**
 * La sélection d'un pronostic, d'après son marché tel que le panneau
 * l'enregistre (`marketName` / `marketValue`, en anglais de l'API), ou à
 * défaut son type. Nulle pour un marché qu'on ne sait pas couvrir.
 */
export function selectionDuPronostic(p: {
  predictionType?: string | null; marketName?: string | null; marketValue?: string | null;
}): Selection | null {
  const nom = (p.marketName ?? '').trim();
  const valeur = (p.marketValue ?? '').trim();
  if (nom && valeur) {
    switch (nom) {
      case 'Match Winner':
        return ['Home', 'Draw', 'Away'].includes(valeur) ? { marche: 'resultat', issue: valeur as Issue } : null;
      case 'Double Chance': {
        const paire = paireDe(valeur);
        return paire ? { marche: 'double_chance', paire } : null;
      }
      case 'Goals Over/Under': {
        const m = valeur.match(/^(Over|Under)\s+(\d+(?:\.\d+)?)$/);
        const ligne = m ? parseFloat(m[2]) : NaN;
        return m && LIGNE_COUVRABLE(ligne) ? { marche: 'buts', plus: m[1] === 'Over', ligne } : null;
      }
      case 'Both Teams Score':
        return valeur === 'Yes' || valeur === 'No' ? { marche: 'btts', oui: valeur === 'Yes' } : null;
      case 'Home/Away':
      case 'Draw No Bet':
        return valeur === 'Home' || valeur === 'Away' ? { marche: 'nul_rembourse', issue: valeur } : null;
      default:
        return null;
    }
  }
  switch ((p.predictionType ?? '').toLowerCase()) {
    case 'win1':    return { marche: 'resultat', issue: 'Home' };
    case 'draw':    return { marche: 'resultat', issue: 'Draw' };
    case 'win2':    return { marche: 'resultat', issue: 'Away' };
    case 'btts':    return { marche: 'btts', oui: true };
    case 'over25':  return { marche: 'buts', plus: true, ligne: 2.5 };
    case 'under25': return { marche: 'buts', plus: false, ligne: 2.5 };
    case 'over35':  return { marche: 'buts', plus: true, ligne: 3.5 };
    case 'under35': return { marche: 'buts', plus: false, ligne: 3.5 };
    default:        return null;
  }
}

/** L'issue complémentaire : exactement l'une des deux se produit. */
export function selectionInverse(s: Selection): Selection {
  switch (s.marche) {
    case 'resultat':
      return { marche: 'double_chance', paire: s.issue === 'Home' ? 'DrawAway' : s.issue === 'Away' ? 'HomeDraw' : 'HomeAway' };
    case 'double_chance':
      return { marche: 'resultat', issue: s.paire === 'HomeDraw' ? 'Away' : s.paire === 'DrawAway' ? 'Home' : 'Draw' };
    case 'buts':
      return { marche: 'buts', plus: !s.plus, ligne: s.ligne };
    case 'btts':
      return { marche: 'btts', oui: !s.oui };
    case 'nul_rembourse':
      return { marche: 'nul_rembourse', issue: s.issue === 'Home' ? 'Away' : 'Home' };
  }
}

// ─── La cote d'une sélection dans les marchés reçus ──────────────────────────

const NOMS: Record<Selection['marche'], string[]> = {
  resultat:      ['match winner', 'fulltime result', 'full time result', '1x2', 'match result'],
  double_chance: ['double chance'],
  buts:          ['goals over/under', 'over/under line', 'over/under', 'match goals', 'total goals'],
  btts:          ['both teams score', 'both teams to score'],
  nul_rembourse: ['home/away', 'draw no bet'],
};

function issueDe(v: string): Issue | null {
  const x = v.trim().toLowerCase();
  if (x === 'home' || x === '1') return 'Home';
  if (x === 'draw' || x === 'x') return 'Draw';
  if (x === 'away' || x === '2') return 'Away';
  return null;
}

function paireDe(v: string): Paire | null {
  const x = v.trim().toLowerCase().replace(/\s+/g, '');
  if (['home/draw', '1x', '1/x', 'homedraw'].includes(x)) return 'HomeDraw';
  if (['home/away', '12', '1/2', 'homeaway'].includes(x)) return 'HomeAway';
  if (['draw/away', 'x2', 'x/2', 'drawaway'].includes(x)) return 'DrawAway';
  return null;
}

function correspond(s: Selection, v: { valeur: string; ligne?: string }): boolean {
  switch (s.marche) {
    case 'resultat':      return issueDe(v.valeur) === s.issue;
    case 'double_chance': return paireDe(v.valeur) === s.paire;
    case 'btts':          return v.valeur.trim().toLowerCase() === (s.oui ? 'yes' : 'no');
    case 'nul_rembourse': return issueDe(v.valeur) === s.issue;
    case 'buts': {
      // « Over 2.5 » (avant-match) ou « Over » et la ligne à part (direct).
      const m = v.valeur.trim().match(/^(over|under)\s*(\d+(?:\.\d+)?)?$/i);
      if (!m || (m[1].toLowerCase() === 'over') !== s.plus) return false;
      const ligne = parseFloat(m[2] ?? v.ligne ?? '');
      return Number.isFinite(ligne) && Math.abs(ligne - s.ligne) < 1e-9;
    }
  }
}

/** La cote de [s] dans [marches], ou nulle si aucun marché ne la propose. */
export function coteDe(marches: MarcheCote[], s: Selection): number | null {
  const noms = NOMS[s.marche];
  for (const m of marches) {
    if (!noms.includes(m.nom.trim().toLowerCase())) continue;
    const v = m.valeurs.find(x => correspond(s, x));
    if (v && Number.isFinite(v.cote) && v.cote > 1) return v.cote;
  }
  return null;
}

// ─── Le calcul ───────────────────────────────────────────────────────────────

export interface Couverture {
  /** Ce qu'il faut miser sur l'inverse, à l'unité de la devise. */
  miseCouverture: number;
  /** Gagné quoi qu'il arrive, les deux mises payées. */
  gainGaranti:    number;
  /** Ce que rapportait la mise d'origine si elle passait. */
  gainPotentiel:  number;
  /** gainGaranti ÷ gainPotentiel. */
  part:           number;
  /** Le résultat net des deux mises si la sélection passe… */
  siSelection:    number;
  /** … et si c'est l'inverse. */
  siInverse:      number;
}

/**
 * [pas] : l'unité de la devise (1 pour le franc CFA, 0,01 pour l'euro). Le
 * gain garanti tient compte de l'arrondi de la mise de couverture : au plus
 * proche pour le gain égal, au-dessus pour la mise remboursée (qui ne doit
 * jamais laisser une perte).
 *
 * Le seuil de l'alerte se lit toujours sur le gain égal : c'est lui qui dit
 * ce que la couverture garantit au mieux.
 */
export function calculerCouverture(
  mise: number, cote: number, coteInverse: number, pas = 1, strategie: Strategie = 'gain_egal',
): Couverture | null {
  if (!(mise > 0 && cote > 1 && coteInverse > 1 && pas > 0)) return null;
  const brut = strategie === 'mise_remboursee' ? mise / (coteInverse - 1) : mise * cote / coteInverse;
  const miseCouverture = (strategie === 'mise_remboursee' ? Math.ceil(brut / pas - 1e-9) : Math.round(brut / pas)) * pas;
  const arrondir = (n: number) => Math.round(n / pas) * pas;
  const siSelection = arrondir(mise * cote - mise - miseCouverture);
  const siInverse = arrondir(miseCouverture * coteInverse - mise - miseCouverture);
  const gainGaranti = Math.min(siSelection, siInverse);
  const gainPotentiel = arrondir(mise * (cote - 1));
  return {
    miseCouverture: arrondir(miseCouverture), gainGaranti, gainPotentiel,
    part: gainPotentiel > 0 ? gainGaranti / gainPotentiel : 0,
    siSelection, siInverse,
  };
}

/** Les seuils proposés dans les réglages, en pourcentage du gain potentiel. */
export const SEUILS_COUVERTURE = [30, 50, 70] as const;
export const SEUIL_COUVERTURE_DEFAUT = 50;

/** Le seuil choisi par l'abonné (préférences de notification), ou 50 %. */
export function seuilDe(prefs: unknown): number {
  const v = prefs && typeof prefs === 'object' ? (prefs as Record<string, unknown>).seuil_couverture : undefined;
  return typeof v === 'number' && (SEUILS_COUVERTURE as readonly number[]).includes(v) ? v : SEUIL_COUVERTURE_DEFAUT;
}

/** La couverture atteint-elle le seuil ? Un gain garanti nul ou négatif, jamais. */
export function seuilAtteint(c: Couverture, seuilPourcent: number): boolean {
  return c.gainGaranti > 0 && c.gainGaranti >= (seuilPourcent / 100) * c.gainPotentiel - 1e-9;
}

// ─── Les libellés ────────────────────────────────────────────────────────────

const fmtLigne = (n: number, langue: 'fr' | 'en') => (langue === 'fr' ? String(n).replace('.', ',') : String(n));

/** Le nom d'une sélection, avec les équipes du match. */
export function libelleSelection(s: Selection, domicile: string, exterieur: string, langue: 'fr' | 'en'): string {
  const fr = langue === 'fr';
  switch (s.marche) {
    case 'resultat':
      return s.issue === 'Draw' ? (fr ? 'Match nul' : 'Draw')
        : fr ? `Victoire ${s.issue === 'Home' ? domicile : exterieur}` : `${s.issue === 'Home' ? domicile : exterieur} to win`;
    case 'double_chance':
      return s.paire === 'HomeDraw' ? (fr ? `${domicile} ou nul` : `${domicile} or draw`)
        : s.paire === 'DrawAway' ? (fr ? `Nul ou ${exterieur}` : `Draw or ${exterieur}`)
        : (fr ? `${domicile} ou ${exterieur}` : `${domicile} or ${exterieur}`);
    case 'buts':
      return fr ? `${s.plus ? 'Plus' : 'Moins'} de ${fmtLigne(s.ligne, 'fr')} buts`
        : `${s.plus ? 'Over' : 'Under'} ${fmtLigne(s.ligne, 'en')} goals`;
    case 'btts':
      return fr ? `Les deux équipes marquent : ${s.oui ? 'oui' : 'non'}`
        : `Both teams to score: ${s.oui ? 'yes' : 'no'}`;
    case 'nul_rembourse': {
      const equipe = s.issue === 'Home' ? domicile : exterieur;
      return fr ? `${equipe}, remboursé si match nul` : `${equipe}, draw no bet`;
    }
  }
}

/**
 * Quand les deux mises sont remboursées ensemble, en une phrase ; nul pour
 * une sélection qui ne l'est jamais.
 */
export function noteRemboursement(s: Selection, langue: 'fr' | 'en'): string | null {
  const fr = langue === 'fr';
  if (s.marche === 'nul_rembourse') {
    return fr ? 'Si le match finit nul, les deux mises sont remboursées : ni gain ni perte.'
      : 'If the match ends in a draw, both stakes are refunded: no gain, no loss.';
  }
  if (s.marche === 'buts' && Number.isInteger(s.ligne)) {
    const n = s.ligne;
    return fr ? `S'il y a exactement ${n} but${n > 1 ? 's' : ''}, les deux mises sont remboursées : ni gain ni perte.`
      : `If there are exactly ${n} goal${n === 1 ? '' : 's'}, both stakes are refunded: no gain, no loss.`;
  }
  return null;
}

/**
 * Le résultat de la mise sur l'inverse, d'après celui de la sélection
 * couverte : l'une passe exactement quand l'autre perd, et elles sont
 * remboursées ensemble.
 */
export function resultatInverse(r: 'WIN' | 'LOSS' | 'PUSH' | null): 'WIN' | 'LOSS' | 'PUSH' | null {
  return r === 'WIN' ? 'LOSS' : r === 'LOSS' ? 'WIN' : r;
}
