import { prisma } from '../lib/prisma';
import { pourcentageConfiance } from '../utils/confiance';
import { rendementUnites } from '../utils/rendement';

/**
 * L'indice de confiance tient-il ses promesses ?
 *
 * L'analyste annonce un pourcentage sur chaque pronostic, et l'application
 * l'affiche à côté de la cote : c'est sur lui que l'abonné décide de miser,
 * et combien. Rien ne vérifiait qu'un « 75 % » gagnait à peu près trois fois
 * sur quatre. Les statistiques donnaient un taux de réussite global, qui ne
 * dit pas si les annonces sont justes : 70 % de réussite est excellent pour
 * des pronostics annoncés à 60 %, et décevant pour des pronostics annoncés à
 * 85 %.
 *
 * On compare donc, tranche par tranche et marché par marché, le pourcentage
 * annoncé en moyenne au taux de réussite réel.
 *
 * ── Ne pas conclure sur trois pronostics ─────────────────────────────────────
 *
 * Sur dix pronostics, gagner six fois au lieu de sept n'est pas un écart :
 * c'est le hasard. Chaque groupe porte l'intervalle de confiance à 95 % de
 * son taux réel (intervalle de Wilson, juste même sur de petits effectifs).
 * Le verdict ne tombe que si le pourcentage annoncé sort de cet intervalle,
 * et jamais sous ECHANTILLON_MINIMAL pronostics tranchés.
 *
 * ── Ce qui compte ────────────────────────────────────────────────────────────
 *
 * Les pronostics publiés seulement — ceux que les abonnés ont vus — et réglés.
 * Un remboursement (PUSH) n'est ni gagné ni perdu : il est compté à part, hors
 * du taux. La période porte sur la date du match.
 */

export const ECHANTILLON_MINIMAL = 10;

/** Les tranches de confiance annoncée, de dix points en dix points. */
export const TRANCHES = [
  { cle: '1-49',  min: 1,  max: 49 },
  { cle: '50-59', min: 50, max: 59 },
  { cle: '60-69', min: 60, max: 69 },
  { cle: '70-79', min: 70, max: 79 },
  { cle: '80-89', min: 80, max: 89 },
  { cle: '90-99', min: 90, max: 99 },
] as const;

export type Verdict = 'fiable' | 'trop_optimiste' | 'trop_prudent' | 'echantillon_faible';

export interface LigneReglee {
  result:          string;
  confidencePct:   number | null;
  confidenceScore: number;
  oddsRecommended: number | null;
  predictionType:  string;
  marketName:      string | null;
  isPremium:       boolean;
}

export interface Groupe {
  cle:          string;
  /** Pronostics gagnés + perdus : la base du taux. */
  tranches:     number;
  gagnes:       number;
  rembourses:   number;
  /** Taux de réussite réel, en %, ou null sans pronostic tranché. */
  tauxReel:     number | null;
  /** Pourcentage annoncé en moyenne sur les pronostics tranchés. */
  annonceMoyen: number | null;
  /** Réel − annoncé, en points. Négatif : on annonce plus qu'on ne gagne. */
  ecart:        number | null;
  /** Intervalle de confiance à 95 % du taux réel, en %. */
  intervalle:   [number, number] | null;
  verdict:      Verdict;
  coteMoyenne:  number | null;
  /** Ce que la cote moyenne donne comme chance, marge du bookmaker comprise. */
  chanceCote:   number | null;
  rendement:    ReturnType<typeof rendementUnites>;
}

/**
 * Intervalle de Wilson à 95 %, en proportions.
 *
 * L'intervalle « p ± 1,96 √(p(1−p)/n) » s'effondre sur les petits effectifs :
 * 10 gagnés sur 10 lui donnent [100 %, 100 %], une certitude tirée de dix
 * matchs. Wilson donne [72 %, 100 %].
 */
export function intervalleWilson(gagnes: number, n: number, z = 1.96): [number, number] | null {
  if (n <= 0) return null;
  const p = gagnes / n;
  const z2 = z * z;
  const centre = (p + z2 / (2 * n)) / (1 + z2 / n);
  const marge = (z / (1 + z2 / n)) * Math.sqrt(p * (1 - p) / n + z2 / (4 * n * n));
  return [Math.max(0, centre - marge), Math.min(1, centre + marge)];
}

export function verdictDe(annonce: number, gagnes: number, n: number): Verdict {
  if (n < ECHANTILLON_MINIMAL) return 'echantillon_faible';
  const [bas, haut] = intervalleWilson(gagnes, n)!;
  const a = annonce / 100;
  if (a > haut) return 'trop_optimiste';
  if (a < bas)  return 'trop_prudent';
  return 'fiable';
}

const arrondi = (v: number, d = 0) => Math.round(v * 10 ** d) / 10 ** d;

export function groupe(cle: string, lignes: LigneReglee[]): Groupe {
  const tranchees = lignes.filter((l) => l.result === 'WIN' || l.result === 'LOSS');
  const gagnes = tranchees.filter((l) => l.result === 'WIN').length;
  const n = tranchees.length;
  const annonce = n ? tranchees.reduce((s, l) => s + pourcentageConfiance(l), 0) / n : null;
  const taux = n ? (gagnes / n) * 100 : null;
  const cotes = tranchees.map((l) => l.oddsRecommended ?? 0).filter((c) => c > 1);
  const intervalle = intervalleWilson(gagnes, n);
  return {
    cle,
    tranches:     n,
    gagnes,
    rembourses:   lignes.filter((l) => l.result === 'PUSH').length,
    tauxReel:     taux === null ? null : arrondi(taux),
    annonceMoyen: annonce === null ? null : arrondi(annonce),
    ecart:        taux === null || annonce === null ? null : arrondi(taux - annonce),
    intervalle:   intervalle ? [arrondi(intervalle[0] * 100), arrondi(intervalle[1] * 100)] : null,
    verdict:      annonce === null ? 'echantillon_faible' : verdictDe(annonce, gagnes, n),
    coteMoyenne:  cotes.length ? arrondi(cotes.reduce((s, c) => s + c, 0) / cotes.length, 2) : null,
    chanceCote:   cotes.length ? arrondi(cotes.reduce((s, c) => s + 100 / c, 0) / cotes.length) : null,
    rendement:    rendementUnites(lignes),
  };
}

/** La clé de marché : le type connu, ou le marché brut pour « other ». */
export function cleMarche(l: Pick<LigneReglee, 'predictionType' | 'marketName'>): string {
  return l.predictionType === 'other' ? `other:${l.marketName ?? ''}` : l.predictionType;
}

export function analyserFiabilite(lignes: LigneReglee[]) {
  const parTranche = TRANCHES.map((t) => groupe(t.cle, lignes.filter((l) => {
    const pct = pourcentageConfiance(l);
    return pct >= t.min && pct <= t.max;
  })));

  const marches = new Map<string, LigneReglee[]>();
  for (const l of lignes) {
    const cle = cleMarche(l);
    (marches.get(cle) ?? marches.set(cle, []).get(cle)!).push(l);
  }

  return {
    global:  groupe('global', lignes),
    tranches: parTranche,
    // Le volume d'abord : un marché joué deux fois n'apprend rien.
    marches: [...marches.entries()].map(([cle, l]) => groupe(cle, l))
      .sort((a, b) => b.tranches - a.tranches || a.cle.localeCompare(b.cle)),
    formules: [
      groupe('premium', lignes.filter((l) => l.isPremium)),
      groupe('gratuit', lignes.filter((l) => !l.isPremium)),
    ],
    // Pronostics publiés avant la saisie en pourcentage : leur annonce est le
    // milieu de leur palier d'étoiles (voir utils/confiance.ts).
    reconstitues: lignes.filter((l) => l.confidencePct === null).length,
  };
}

export async function resumeFiabilite(params: { jours?: number | null } = {}) {
  const jours = params.jours && params.jours > 0 ? Math.min(params.jours, 3650) : null;
  const lignes = await prisma.pronostic.findMany({
    where: {
      isPublished: true,
      result: { in: ['WIN', 'LOSS', 'PUSH'] },
      ...(jours ? { match: { matchDate: { gte: new Date(Date.now() - jours * 86_400_000) } } } : {}),
    },
    select: {
      result: true, confidencePct: true, confidenceScore: true, oddsRecommended: true,
      predictionType: true, marketName: true, isPremium: true,
    },
  });
  return {
    jours,
    echantillonMinimal: ECHANTILLON_MINIMAL,
    ...analyserFiabilite(lignes.map((l) => ({ ...l, result: l.result! }))),
  };
}
