import type { AxiosInstance } from 'axios';
import { enrichissementsFootball } from './enrichissements_football';

/**
 * L'évolution au classement des deux équipes d'un match, journée par journée
 * (7 novembre 2026) — le « Tracker de classement » de Sofascore.
 *
 * API-Football ne publie que le classement du jour. On le reconstitue à
 * partir des résultats de la saison (une requête `/fixtures`, gardée six
 * heures) : après chaque journée, points, différence de buts, buts marqués.
 * Les critères de départage propres à chaque championnat (face-à-face,
 * fair-play) ne sont pas appliqués : à égalité parfaite, deux équipes peuvent
 * être inversées par rapport au classement officiel. Un match reporté compte
 * dans sa journée d'origine, le jour où il est joué.
 *
 * Championnats seulement : une coupe n'a pas de « Regular Season - N ».
 */
export interface PointEvolution { journee: number; domicile: number | null; exterieur: number | null }
export interface EvolutionClassement { saison: number; equipes: number; journees: PointEvolution[] }

const TERMINES = new Set(['FT', 'AET', 'PEN']);
const TTL = 6 * 60 * 60_000;

/** « Regular Season - 12 » → 12 ; autre chose → null. */
export function numeroJournee(round: string | null | undefined): number | null {
  const m = /^Regular Season\s*-\s*(\d+)$/i.exec((round ?? '').trim());
  return m ? Number(m[1]) : null;
}

interface Ligne { id: number; nom: string; pts: number; diff: number; bp: number }

/**
 * Les positions de [dom] et [ext] après chaque journée, à partir des
 * [fixtures] de la saison. Exportée pour les tests.
 */
export function reconstituer(fixtures: any[], dom: number, ext: number): Omit<EvolutionClassement, 'saison'> | null {
  const parJournee = new Map<number, any[]>();
  const equipes = new Map<number, Ligne>();
  for (const f of fixtures) {
    const j = numeroJournee(f?.league?.round);
    if (j == null) continue;
    for (const t of [f?.teams?.home, f?.teams?.away]) {
      if (Number.isInteger(t?.id) && !equipes.has(t.id)) equipes.set(t.id, { id: t.id, nom: t.name ?? '', pts: 0, diff: 0, bp: 0 });
    }
    if (!TERMINES.has(f?.fixture?.status?.short)) continue;
    if (!parJournee.has(j)) parJournee.set(j, []);
    parJournee.get(j)!.push(f);
  }
  if (equipes.size < 2 || !equipes.has(dom) || !equipes.has(ext)) return null;

  const journees: PointEvolution[] = [];
  for (const j of [...parJournee.keys()].sort((a, b) => a - b)) {
    for (const f of parJournee.get(j)!) {
      const h = equipes.get(f.teams.home.id), a = equipes.get(f.teams.away.id);
      const gh = f.goals?.home, ga = f.goals?.away;
      if (!h || !a || typeof gh !== 'number' || typeof ga !== 'number') continue;
      h.bp += gh; a.bp += ga; h.diff += gh - ga; a.diff += ga - gh;
      if (gh > ga) h.pts += 3; else if (gh < ga) a.pts += 3; else { h.pts += 1; a.pts += 1; }
    }
    const classement = [...equipes.values()].sort((x, y) =>
      y.pts - x.pts || y.diff - x.diff || y.bp - x.bp || x.nom.localeCompare(y.nom));
    const rang = (id: number) => classement.findIndex(l => l.id === id) + 1 || null;
    journees.push({ journee: j, domicile: rang(dom), exterieur: rang(ext) });
  }
  return { equipes: equipes.size, journees };
}

export class EvolutionClassementFootball {
  constructor(private client: AxiosInstance, private fixture: (id: number) => Promise<any | null>) {}

  /** `null` : coupe, match inconnu, saison sans journée jouée ou fournisseur indisponible. */
  async get(fixtureId: number): Promise<EvolutionClassement | null> {
    try {
      const f = await this.fixture(fixtureId);
      const league = f?.league?.id, season = f?.league?.season;
      const dom = f?.teams?.home?.id, ext = f?.teams?.away?.id;
      if (!league || !season || !dom || !ext || numeroJournee(f?.league?.round) == null) return null;
      const rows = await enrichissementsFootball(this.client).get('/fixtures', { league, season }, TTL);
      const r = reconstituer(rows, dom, ext);
      return r && r.journees.length > 0 ? { saison: season, ...r } : null;
    } catch {
      return null;
    }
  }
}
