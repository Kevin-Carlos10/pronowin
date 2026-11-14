import type { AxiosInstance } from 'axios';
import { enrichissementsFootball } from './enrichissements_football';

/**
 * La forme récente des deux équipes d'un match : leurs cinq derniers matchs
 * terminés, toutes compétitions confondues — ce que Sofascore et 1xBet
 * montrent sur la fiche d'un match (« Matchs récents »), et que la fiche de
 * PronoWin réduisait à un total de points (8 octobre 2026).
 *
 * Le résultat se lit sur le vainqueur désigné par le fournisseur, pas sur le
 * score : un match gagné aux tirs au but est une victoire, même à 1-1.
 */
export interface MatchRecent {
  date: string;
  competition: string | null;
  adversaire: string;
  adversaireLogo: string | null;
  /** L'équipe jouait-elle à domicile ? */
  domicile: boolean;
  butsPour: number;
  butsContre: number;
  issue: 'V' | 'N' | 'D';
}

/**
 * Les « Séries » d'une équipe, sur ses derniers matchs terminés (dix au plus),
 * toutes compétitions confondues — ce que Sofascore affiche sous ce nom
 * (7 novembre 2026). Les séries « en cours » partent du match le plus récent ;
 * les autres sont des comptes sur [sur] matchs.
 */
export interface Series {
  /** Nombre de matchs lus (dix au plus). */
  sur: number;
  /** Séries en cours, du plus récent au plus ancien. */
  victoires: number;
  sansDefaite: number;
  sansVictoire: number;
  defaites: number;
  /** A marqué à chaque match, à la suite. */
  marque: number;
  /** N'a pas encaissé, à la suite. */
  sansEncaisser: number;
  /** Comptes sur les [sur] matchs. */
  plusDe25Buts: number;
  lesDeuxMarquent: number;
  cleanSheets: number;
  nAPasMarque: number;
}

export interface FormeRecente {
  home: MatchRecent[]; away: MatchRecent[];
  series?: { home: Series; away: Series };
}

/** [matchs] du plus récent au plus ancien. */
export function seriesDe(matchs: MatchRecent[]): Series {
  const enCours = (ok: (m: MatchRecent) => boolean) => {
    let n = 0;
    for (const m of matchs) { if (!ok(m)) break; n++; }
    return n;
  };
  const compte = (ok: (m: MatchRecent) => boolean) => matchs.filter(ok).length;
  return {
    sur: matchs.length,
    victoires: enCours(m => m.issue === 'V'),
    sansDefaite: enCours(m => m.issue !== 'D'),
    sansVictoire: enCours(m => m.issue !== 'V'),
    defaites: enCours(m => m.issue === 'D'),
    marque: enCours(m => m.butsPour > 0),
    sansEncaisser: enCours(m => m.butsContre === 0),
    plusDe25Buts: compte(m => m.butsPour + m.butsContre >= 3),
    lesDeuxMarquent: compte(m => m.butsPour > 0 && m.butsContre > 0),
    cleanSheets: compte(m => m.butsContre === 0),
    nAPasMarque: compte(m => m.butsPour === 0),
  };
}

const TERMINES = ['FT', 'AET', 'PEN'];
const TTL = 3 * 60 * 60_000;

/** Un match du fournisseur, vu du côté de l'équipe `equipe`. */
export function matchRecent(f: any, equipe: number): MatchRecent | null {
  const domicile = f?.teams?.home?.id === equipe;
  if (!domicile && f?.teams?.away?.id !== equipe) return null;
  const nous = domicile ? f.teams.home : f.teams.away;
  const eux = domicile ? f.teams.away : f.teams.home;
  const pour = domicile ? f.goals?.home : f.goals?.away;
  const contre = domicile ? f.goals?.away : f.goals?.home;
  if (typeof pour !== 'number' || typeof contre !== 'number') return null;
  const issue = nous?.winner === true ? 'V' : eux?.winner === true ? 'D'
    : pour > contre ? 'V' : pour < contre ? 'D' : 'N';
  return {
    date: f.fixture?.date ?? '',
    competition: f.league?.name ?? null,
    adversaire: eux?.name ?? '',
    adversaireLogo: eux?.logo ?? null,
    domicile,
    butsPour: pour,
    butsContre: contre,
    issue,
  };
}

export class FormeRecenteFootball {
  constructor(private client: AxiosInstance, private fixture: (id: number) => Promise<any | null>) {}

  /** `null` : match inconnu du fournisseur, ou données momentanément indisponibles. */
  async get(fixtureId: number): Promise<FormeRecente | null> {
    try {
      const f = await this.fixture(fixtureId);
      const home = f?.teams?.home?.id, away = f?.teams?.away?.id;
      if (!home || !away) return null;
      const api = enrichissementsFootball(this.client);
      const lire = async (equipe: number) => {
        // Dix derniers, pour en garder cinq terminés : un match reporté ou
        // annulé figure aussi dans la liste.
        const rows = await api.get('/fixtures', { team: equipe, last: 10 }, TTL);
        return rows
          .filter(r => TERMINES.includes(r.fixture?.status?.short) && r.fixture?.id !== fixtureId)
          .sort((a, b) => (b.fixture?.timestamp ?? 0) - (a.fixture?.timestamp ?? 0))
          .map(r => matchRecent(r, equipe))
          .filter((m): m is MatchRecent => m !== null);
      };
      // Les séries se lisent sur les dix ; la forme n'en montre que cinq.
      const [h, a] = await Promise.all([lire(home), lire(away)]);
      return { home: h.slice(0, 5), away: a.slice(0, 5), series: { home: seriesDe(h), away: seriesDe(a) } };
    } catch {
      return null;
    }
  }
}
