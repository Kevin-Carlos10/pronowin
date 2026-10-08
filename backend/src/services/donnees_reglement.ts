/**
 * Les données d'un match terminé dont ont besoin les marchés 1xBet de la
 * phase 2 (buts et leur minute, penalties, cartons, corners), et le
 * règlement de ces pronostics.
 *
 * Un seul appel au fournisseur par match (`/fixtures?id=` renvoie ensemble
 * les événements et les statistiques), gardé dix minutes : la boucle de
 * synchronisation repasse sur les pronostics non réglés à chaque tour, et
 * ne doit pas réinterroger le fournisseur à chaque fois.
 *
 * Deux précautions avant de régler :
 *  - attendre 2 h 15 après le coup d'envoi : à la fin du match, les
 *    statistiques (corners, cartons) reçoivent encore des corrections ;
 *  - s'arrêter trois jours après : un match dont les données ne permettent
 *    pas de trancher reste au panneau, sans appel au fournisseur sans fin.
 */
import { apiFootballService } from './api_football.service';
import { _resolvePronosticResult, type ScoreLine } from './settlement';
import { journal } from '../utils/logger';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const marches = require('../marches/complementaires') as {
  besoinDeDonnees(nom: string | null): 'evenements' | 'statistiques' | null;
  regler(nom: string, valeur: string, ft: ScoreLine, fh: ScoreLine | null, donnees?: DonneesMatch | null): 'WIN' | 'LOSS' | null;
};

export interface EvenementMatch {
  minute: number; extra: number | null; equipe: 'Home' | 'Away'; type: string; detail: string;
}
export interface StatsEquipe { corners: number | null; jaunes: number | null; rouges: number | null }
export interface DonneesMatch {
  prolongation: boolean;
  evenements: EvenementMatch[];
  stats: { Home: StatsEquipe; Away: StatsEquipe } | null;
}

export const ATTENTE_APRES_COUP_ENVOI = 135 * 60_000;
export const ABANDON_APRES_COUP_ENVOI = 3 * 24 * 60 * 60_000;

/** La fiche brute du fournisseur, ramenée à ce que les marchés lisent. */
export function normaliserDonnees(f: any): DonneesMatch | null {
  const statut = f?.fixture?.status?.short;
  const home = f?.teams?.home?.id, away = f?.teams?.away?.id;
  if (!['FT', 'AET', 'PEN'].includes(statut) || !home || !away) return null;
  const equipe = (id: number): 'Home' | 'Away' | null => id === home ? 'Home' : id === away ? 'Away' : null;

  const evenements: EvenementMatch[] = [];
  for (const e of f.events ?? []) {
    const camp = equipe(e?.team?.id);
    if (!camp || typeof e?.time?.elapsed !== 'number') continue;
    evenements.push({ minute: e.time.elapsed, extra: e.time.extra ?? null, equipe: camp, type: e.type ?? '', detail: e.detail ?? '' });
  }

  const lignes = (camp: 'Home' | 'Away'): StatsEquipe | null => {
    const bloc = (f.statistics ?? []).find((s: any) => equipe(s?.team?.id) === camp);
    if (!bloc || !Array.isArray(bloc.statistics) || bloc.statistics.length === 0) return null;
    const valeur = (type: string) => {
      const v = bloc.statistics.find((x: any) => x?.type === type)?.value;
      return typeof v === 'number' ? v : v == null ? null : Number(v) || 0;
    };
    return { corners: valeur('Corner Kicks'), jaunes: valeur('Yellow Cards'), rouges: valeur('Red Cards') };
  };
  const sh = lignes('Home'), sa = lignes('Away');

  return {
    prolongation: statut === 'AET' || statut === 'PEN',
    evenements,
    stats: sh && sa ? { Home: sh, Away: sa } : null,
  };
}

const memoire = new Map<number, { at: number; donnees: DonneesMatch | null }>();

export async function donneesDeReglement(
  fixtureId: number,
  lireFiche: (id: number) => Promise<any> = (id) => apiFootballService.getFixtureById(id),
  maintenant = Date.now(),
): Promise<DonneesMatch | null> {
  const connu = memoire.get(fixtureId);
  if (connu && maintenant - connu.at < 10 * 60_000) return connu.donnees;
  const donnees = normaliserDonnees(await lireFiche(fixtureId).catch(() => null));
  memoire.set(fixtureId, { at: maintenant, donnees });
  if (memoire.size > 500) memoire.delete(memoire.keys().next().value as number);
  return donnees;
}

/**
 * Le verdict d'un pronostic d'un match terminé : celui du score seul quand il
 * suffit, sinon — marchés de la phase 2 — avec les données du match.
 */
export async function resoudrePronostic(
  prono: { predictionType: string; marketName: string | null; marketValue: string | null },
  match: { source?: string | null; externalId?: number | null; matchDate?: Date | null },
  ft: ScoreLine,
  fh: ScoreLine | null,
  options: { maintenant?: number; lireFiche?: (id: number) => Promise<any> } = {},
): Promise<'WIN' | 'LOSS' | 'PUSH' | null> {
  const simple = _resolvePronosticResult(prono, ft, fh);
  if (simple || prono.predictionType !== 'other' || !prono.marketName || !prono.marketValue) return simple;
  if (!marches.besoinDeDonnees(prono.marketName)) return null;

  const maintenant = options.maintenant ?? Date.now();
  const coupEnvoi = match.matchDate ? new Date(match.matchDate).getTime() : NaN;
  if (match.source !== 'API_FOOTBALL' || !match.externalId || !Number.isFinite(coupEnvoi)) return null;
  if (maintenant - coupEnvoi < ATTENTE_APRES_COUP_ENVOI) return null;
  if (maintenant - coupEnvoi > ABANDON_APRES_COUP_ENVOI) return null;

  const donnees = await donneesDeReglement(match.externalId, options.lireFiche, maintenant);
  const verdict = marches.regler(prono.marketName, prono.marketValue, ft, fh, donnees);
  const cle = `${match.externalId}|${prono.marketName}|${prono.marketValue}`;
  if (!verdict && !signales.has(cle)) {
    // Une fois par pronostic : la boucle repasse à chaque tour.
    signales.add(cle);
    journal.info(`[Règlement] match ${match.externalId}, ${prono.marketName} « ${prono.marketValue} » : données insuffisantes pour l'instant`);
  }
  return verdict;
}

const signales = new Set<string>();
