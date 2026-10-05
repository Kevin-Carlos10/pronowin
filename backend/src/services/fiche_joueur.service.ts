import type { AxiosInstance } from 'axios';
import { traduireAbsence, estSuspension } from './traduction_absences';
import { journal } from '../utils/logger';

/**
 * La fiche d'un joueur : profil, statistiques de la saison, absences et
 * transferts — quatre routes d'API-Football que l'application ne lisait pas.
 *
 * Elle s'ouvre depuis les compositions, les notes, les blessures et les
 * palmarès : là où un nom de joueur s'affichait sans rien derrière.
 *
 * ── Quota ─────────────────────────────────────────────────────────────────
 *
 * Trois requêtes par joueur (profil et statistiques, absences, transferts),
 * gardées douze heures. Une fiche ouverte mille fois dans la journée en coûte
 * trois. Le cache est borné : au-delà, les fiches les plus anciennes partent.
 */

export interface StatsCompetition {
  team:        string;
  teamLogo:    string | null;
  league:      string;
  leagueLogo:  string | null;
  /** Poste tel que l'API le donne : Goalkeeper, Defender, Midfielder, Attacker. */
  position:    string | null;
  appearances: number;
  lineups:     number;
  minutes:     number;
  /** Note moyenne sur la saison, deux décimales ; null sans note. */
  rating:      number | null;
  goals:       number;
  assists:     number;
  yellowCards: number;
  redCards:    number;
  shots:       number;
  shotsOn:     number;
  keyPasses:   number;
  /** Précision des passes, en pourcentage ; null quand l'API ne la donne pas. */
  passAccuracy: number | null;
  dribblesSuccess: number;
  duelsWon:    number;
  penaltiesScored: number;
  /** Gardiens : buts encaissés et arrêts. */
  conceded:    number;
  saves:       number;
}

export interface AbsenceJoueur {
  motif:      string;
  suspension: boolean;
  debut:      string | null;
  fin:        string | null;
}

export interface TransfertJoueur {
  date:     string | null;
  /** « Prêt », « Libre », « Transfert » ou le montant publié. */
  type:     string;
  depuis:   string;
  depuisLogo: string | null;
  vers:     string;
  versLogo: string | null;
}

export interface FicheJoueur {
  id:          number;
  name:        string;
  firstname:   string | null;
  lastname:    string | null;
  age:         number | null;
  birthDate:   string | null;
  birthPlace:  string | null;
  nationality: string | null;
  height:      string | null;
  weight:      string | null;
  photo:       string | null;
  injured:     boolean;
  season:      number;
  /** Par compétition, la plus jouée d'abord. */
  stats:       StatsCompetition[];
  /** Les plus récentes d'abord, cinq au plus. */
  absences:    AbsenceJoueur[];
  transferts:  TransfertJoueur[];
}

const FICHE_TTL = 12 * 60 * 60 * 1000;
const FICHES_MAX = 2000;
const fichesCache = new Map<string, { data: FicheJoueur | 'introuvable'; ts: number }>();

/** La saison d'API-Football : l'année où elle commence (juillet). */
export function saisonParDefaut(maintenant = new Date()): number {
  return maintenant.getMonth() >= 6 ? maintenant.getFullYear() : maintenant.getFullYear() - 1;
}

const nombre = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

export function traduireTypeTransfert(type: unknown): string {
  const t = typeof type === 'string' ? type.trim() : '';
  if (!t || /^n\/?a$/i.test(t) || /^transfer$/i.test(t)) return 'Transfert';
  if (/^loan$/i.test(t)) return 'Prêt';
  if (/^back from loan$/i.test(t)) return 'Retour de prêt';
  if (/^free( transfer)?$/i.test(t)) return 'Libre';
  return t; // un montant (« € 25M ») se lit tel quel
}

export function versStats(s: any): StatsCompetition {
  const note = parseFloat(s?.games?.rating);
  const precision = parseFloat(s?.passes?.accuracy);
  return {
    team:        s?.team?.name ?? '',
    teamLogo:    s?.team?.logo ?? null,
    league:      s?.league?.name ?? '',
    leagueLogo:  s?.league?.logo ?? null,
    position:    s?.games?.position ?? null,
    appearances: nombre(s?.games?.appearences),
    lineups:     nombre(s?.games?.lineups),
    minutes:     nombre(s?.games?.minutes),
    rating:      Number.isFinite(note) ? Math.round(note * 100) / 100 : null,
    goals:       nombre(s?.goals?.total),
    assists:     nombre(s?.goals?.assists),
    yellowCards: nombre(s?.cards?.yellow) + nombre(s?.cards?.yellowred),
    redCards:    nombre(s?.cards?.red),
    shots:       nombre(s?.shots?.total),
    shotsOn:     nombre(s?.shots?.on),
    keyPasses:   nombre(s?.passes?.key),
    passAccuracy: Number.isFinite(precision) ? Math.round(precision) : null,
    dribblesSuccess: nombre(s?.dribbles?.success),
    duelsWon:    nombre(s?.duels?.won),
    penaltiesScored: nombre(s?.penalty?.scored),
    conceded:    nombre(s?.goals?.conceded),
    saves:       nombre(s?.goals?.saves),
  };
}

export class FichesJoueurs {
  constructor(
    private readonly client: AxiosInstance,
    private readonly hasKey: () => boolean,
  ) {}

  /**
   * La fiche d'un joueur, ou `'introuvable'` si l'API ne le connaît pas, ou
   * `null` si l'API n'a pas répondu.
   *
   * Sans saison demandée : la saison en cours, puis la précédente si le
   * joueur n'y a encore rien joué (début de saison, championnat sur l'année
   * civile).
   */
  async fiche(playerId: number, saison?: number): Promise<FicheJoueur | 'introuvable' | null> {
    if (!this.hasKey()) return null;

    const cle = `${playerId}_${saison ?? 'auto'}`;
    const hit = fichesCache.get(cle);
    if (hit && Date.now() - hit.ts < FICHE_TTL) return hit.data;

    try {
      const saisons = saison ? [saison] : [saisonParDefaut(), saisonParDefaut() - 1];
      let profil: any = null;
      let saisonRetenue = saisons[0];
      for (const s of saisons) {
        const r = await this.client.get('/players', { params: { id: playerId, season: s } });
        const p = r.data?.response?.[0];
        if (p) { profil = p; saisonRetenue = s; }
        if (p && (p.statistics ?? []).some((x: any) => nombre(x?.games?.appearences) > 0)) break;
      }
      if (!profil) {
        this.garder(cle, 'introuvable');
        return 'introuvable';
      }

      const [absences, transferts] = await Promise.all([
        this.absences(playerId), this.transferts(playerId),
      ]);

      const j = profil.player ?? {};
      const fiche: FicheJoueur = {
        id:          j.id ?? playerId,
        name:        j.name ?? '',
        firstname:   j.firstname ?? null,
        lastname:    j.lastname ?? null,
        age:         typeof j.age === 'number' ? j.age : null,
        birthDate:   j.birth?.date ?? null,
        birthPlace:  [j.birth?.place, j.birth?.country].filter(Boolean).join(', ') || null,
        nationality: j.nationality ?? null,
        height:      j.height ?? null,
        weight:      j.weight ?? null,
        photo:       j.photo ?? null,
        injured:     j.injured === true,
        season:      saisonRetenue,
        stats:       (profil.statistics ?? [])
          .map(versStats)
          .filter((s: StatsCompetition) => s.appearances > 0)
          .sort((a: StatsCompetition, b: StatsCompetition) => b.appearances - a.appearances || b.minutes - a.minutes),
        absences,
        transferts,
      };
      this.garder(cle, fiche);
      return fiche;
    } catch (e) {
      journal.error('[ApiFootball] fiche joueur indisponible:', (e as Error).message);
      return null;
    }
  }

  private async absences(playerId: number): Promise<AbsenceJoueur[]> {
    try {
      const r = await this.client.get('/sidelined', { params: { player: playerId } });
      return (r.data?.response ?? [])
        .map((a: any) => ({
          motif:      traduireAbsence(a?.type) || 'Absence',
          suspension: estSuspension(a?.type ?? ''),
          debut:      a?.start ?? null,
          fin:        a?.end ?? null,
        }))
        .sort((a: AbsenceJoueur, b: AbsenceJoueur) => (b.debut ?? '').localeCompare(a.debut ?? ''))
        .slice(0, 5);
    } catch (e) {
      journal.error('[ApiFootball] /sidelined indisponible:', (e as Error).message);
      return [];
    }
  }

  private async transferts(playerId: number): Promise<TransfertJoueur[]> {
    try {
      const r = await this.client.get('/transfers', { params: { player: playerId } });
      return (r.data?.response?.[0]?.transfers ?? [])
        .map((t: any) => ({
          date:       t?.date ?? null,
          type:       traduireTypeTransfert(t?.type),
          depuis:     t?.teams?.out?.name ?? '',
          depuisLogo: t?.teams?.out?.logo ?? null,
          vers:       t?.teams?.in?.name ?? '',
          versLogo:   t?.teams?.in?.logo ?? null,
        }))
        .sort((a: TransfertJoueur, b: TransfertJoueur) => (b.date ?? '').localeCompare(a.date ?? ''))
        .slice(0, 5);
    } catch (e) {
      journal.error('[ApiFootball] /transfers indisponible:', (e as Error).message);
      return [];
    }
  }

  private garder(cle: string, data: FicheJoueur | 'introuvable') {
    if (fichesCache.size >= FICHES_MAX) {
      const plusAncienne = fichesCache.keys().next().value;
      if (plusAncienne !== undefined) fichesCache.delete(plusAncienne);
    }
    fichesCache.set(cle, { data, ts: Date.now() });
  }
}
