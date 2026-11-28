/**
 * Début estimé de chaque mi-temps, quand API-Football ne le date pas.
 *
 * Le chrono à la seconde de la fiche de match (demande de l'utilisateur du
 * 17 octobre 2026) part du début de la mi-temps. API-Football le publie dans
 * `fixture.periods`, mais pas pour toutes les compétitions : le 17 octobre,
 * trois matchs en direct sur trois le laissaient vide.
 *
 * On l'estime donc à partir des relevés, toutes les 30 s pendant un direct.
 * La minute publiée (`status.elapsed`) est la minute en cours, comptée à
 * partir de 1 : « 39 » de 38:00 à 38:59. Chaque relevé (instant t, minute E)
 * borne le début de la mi-temps :
 *
 *     (E − 1 − base)·60 s ≤ t − début < (E − base)·60 s
 *
 * avec base = 0 en première mi-temps et 45 en seconde. Un relevé seul situe le
 * début à une minute près ; les suivants, pris à d'autres secondes de la
 * minute, resserrent l'intervalle. On sert son milieu.
 *
 * Le chrono obtenu suit les données d'API-Football, avec leur léger retard
 * sur le terrain — le même que celui du score.
 */

interface Bornes {
  /** Début au plus tôt (exclu), en ms. */
  min: number;
  /** Début au plus tard (inclus), en ms. */
  max: number;
  /** Dernier relevé, pour la purge. */
  vu: number;
}

const bornes = new Map<string, Bornes>();
const cle = (fixtureId: number, miTemps: 1 | 2) => `${fixtureId}:${miTemps}`;
/** Au-delà, une entrée appartient à un match fini depuis longtemps. */
const DUREE_DE_VIE_MS = 4 * 60 * 60_000;

/**
 * Note un relevé de rencontre (réponse brute d'API-Football).
 *
 * @param observeLe instant de la réception de la réponse, en ms
 */
export function observerRencontre(f: any, observeLe = Date.now()): void {
  const id = f?.fixture?.id;
  const phase = f?.fixture?.status?.short;
  const minute = f?.fixture?.status?.elapsed;
  if (!Number.isSafeInteger(id) || !Number.isInteger(minute)) return;
  const miTemps = phase === '1H' ? 1 : phase === '2H' ? 2 : 0;
  if (!miTemps) return;
  const base = miTemps === 1 ? 0 : 45;
  const fin  = miTemps === 1 ? 45 : 90;
  // Temps additionnel : la minute publiée reste à 45 ou 90, elle ne dit plus
  // où en est le chrono. Aucune contrainte à en tirer.
  if (minute <= base || minute >= fin || Number.isInteger(f?.fixture?.status?.extra)) return;

  const min = observeLe - (minute - base) * 60_000;
  const max = observeLe - (minute - 1 - base) * 60_000;
  const k = cle(id, miTemps);
  const avant = bornes.get(k);
  if (avant) {
    const nmin = Math.max(avant.min, min);
    const nmax = Math.min(avant.max, max);
    // Intervalles disjoints : la source a corrigé sa minute (ou repris après
    // une interruption). Le relevé le plus récent fait foi.
    bornes.set(k, nmin < nmax ? { min: nmin, max: nmax, vu: observeLe } : { min, max, vu: observeLe });
  } else {
    bornes.set(k, { min, max, vu: observeLe });
  }

  for (const [c, b] of bornes) if (observeLe - b.vu > DUREE_DE_VIE_MS) bornes.delete(c);
}

/** Note chaque rencontre d'une réponse brute d'API-Football. */
export function observerRencontres(fixtures: unknown, observeLe = Date.now()): void {
  if (Array.isArray(fixtures)) for (const f of fixtures) observerRencontre(f, observeLe);
}

/** Début estimé de la mi-temps, en secondes Unix, ou null sans relevé. */
export function debutEstime(fixtureId: number, miTemps: 1 | 2): number | null {
  const b = bornes.get(cle(fixtureId, miTemps));
  return b ? Math.round((b.min + b.max) / 2 / 1000) : null;
}

/** Largeur de l'intervalle, en secondes (précision de l'estimation). */
export function precisionEstimation(fixtureId: number, miTemps: 1 | 2): number | null {
  const b = bornes.get(cle(fixtureId, miTemps));
  return b ? Math.round((b.max - b.min) / 1000) : null;
}

/** Pour les tests. */
export function _oublierEstimations(): void { bornes.clear(); }
