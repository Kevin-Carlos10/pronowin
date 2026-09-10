import type { AxiosInstance } from 'axios';
import { traduireRecommandation } from './traduction_recommandation';
import { extraireLigne, libelleSansLigne, marcheLisible, traduireMarche } from './cotes_live';
import { evaluerFiabilite } from './fiabilite_modele';

/**
 * Second volet du client API-Football : les données que le plan Pro débloque
 * et que l'application n'exploitait pas.
 *
 * Séparé de `api_football.service.ts` (déjà ~1 200 lignes) parce que ces
 * endpoints répondent à un besoin différent : ils n'alimentent pas le
 * catalogue de matchs, ils l'enrichissent. Ils sont donc tous optionnels —
 * une panne ici ne doit jamais empêcher un match de s'afficher, d'où le
 * `null` systématique plutôt qu'une exception.
 *
 * Budget quota (plan Pro, 7 500 req/jour) : ces appels ajoutent ~410 req/jour
 * grâce aux caches ci-dessous. Le poste le plus lourd est `/odds/live`, dont
 * un seul appel couvre *tous* les matchs en cours — ne jamais le filtrer par
 * fixture, ce serait multiplier le coût par le nombre de matchs.
 */

// ─── Pronostic du modèle ──────────────────────────────────────────────────────

export interface PredictionComparison {
  /** Axe de comparaison, ex. 'forme', 'attaque'… (libellés déjà traduits). */
  label: string;
  /** Part attribuée à l'équipe à domicile, 0–100. */
  home: number;
  away: number;
}

export interface MatchPrediction {
  /** Conseil brut du modèle, ex. « Combo Double chance : Nice or draw ». */
  advice:      string | null;
  winnerName:  string | null;
  winnerComment: string | null;
  percentHome: number;
  percentDraw: number;
  percentAway: number;
  /**
   * La sortie du modèle est-elle exploitable ?
   *
   * `false` quand les valeurs sont collées aux butées — 0 % pour une équipe,
   * tous les axes à 0/100. Ce n'est pas de la certitude, c'est une absence de
   * données déguisée en évidence, et l'écran doit se taire plutôt que de la
   * présenter sous « Pourquoi ce pronostic ».
   */
  modeleExploitable: boolean;
  /** Ligne de but conseillée, ex. '-2.5'. */
  underOver:   string | null;
  comparisons: PredictionComparison[];
  /** Forme récente, du plus ancien au plus récent, ex. 'LDDWW'. */
  formHome:    string | null;
  formAway:    string | null;
  /// Identifiants API-Football, repris de la même réponse : ils évitent un
  /// aller-retour supplémentaire (et une migration pour les stocker) quand on
  /// enchaîne sur /teams/statistics.
  leagueId:    number | null;
  season:      number | null;
  homeTeamId:  number | null;
  awayTeamId:  number | null;
  cleanSheetHome: number;
  cleanSheetAway: number;
  failedToScoreHome: number;
  failedToScoreAway: number;
}

/** Les prédictions d'un match ne bougent quasiment pas — cache long. */
const predictionCache = new Map<number, { data: MatchPrediction; ts: number }>();
const PREDICTION_TTL = 6 * 60 * 60 * 1000; // 6 h

/**
 * Libellés d'axes, dans l'ordre d'affichage.
 *
 * `total` s'appelait « Total » — un mot qui invite à vérifier l'addition. Or
 * ce n'est pas la moyenne des lignes du dessus : c'est l'agrégat pondéré du
 * fournisseur, et l'écart saute aux yeux (moyenne des six axes ≈ 36/47 pour un
 * « Total » affiché à 17/83). Le renommer « Synthèse » supprime la promesse
 * arithmétique que la donnée ne tient pas.
 */
const AXES: Array<[cle: string, libelle: string]> = [
  ['form',   'Forme'],
  ['att',    'Attaque'],
  ['def',    'Défense'],
  ['goals',  'Buts'],
  ['h2h',    'Confrontations'],
  ['poisson_distribution', 'Poisson'],
  ['total',  'Synthèse'],
];

const pct = (v: unknown): number => {
  const n = parseFloat(String(v ?? '').replace('%', ''));
  return Number.isFinite(n) ? n : 0;
};

// ─── Statistiques de saison ───────────────────────────────────────────────────

export interface TeamSeasonStats {
  form: string | null;
  /** Buts marqués par tranche de 15 minutes : { '0-15': 4, '16-30': 5, … } */
  goalsForByMinute:     Record<string, number>;
  goalsAgainstByMinute: Record<string, number>;
  goalsForAverage:     { home: string; away: string; total: string };
  /// Buts encaisses par match — fournis a cote de ceux marques, jamais lus.
  goalsAgainstAverage: { home: string; away: string; total: string };
  cleanSheetTotal:     number;
  failedToScoreTotal:  number;
  penaltyScored:       number;
  penaltyPercentage:   string | null;
}

const seasonStatsCache = new Map<string, { data: TeamSeasonStats; ts: number }>();
const SEASON_STATS_TTL = 24 * 60 * 60 * 1000;

// ─── Cotes en direct ──────────────────────────────────────────────────────────

export interface LiveOddValue {
  value: string;
  odd:   number;
  /** Seuil du marché — « 2.5 », « -0.5 ». Absent quand il n'y en a pas. */
  ligne?: string;
}
export interface LiveOddMarket { name: string; values: LiveOddValue[]; }

export interface LiveOdds {
  fixtureId: number;
  elapsed:   number | null;
  markets:   LiveOddMarket[];
}

/**
 * Cache **global** des cotes live : `/odds/live` sans paramètre renvoie tous
 * les matchs en cours d'un coup. Un appel toutes les 2 minutes suffit — les
 * cotes bougent, mais pas au point de justifier 30 s (× 4 le coût en quota).
 */
let liveOddsCache: { data: Map<number, LiveOdds>; ts: number } | null = null;
const LIVE_ODDS_TTL = 2 * 60 * 1000;

// ─── Notes de joueurs ─────────────────────────────────────────────────────────

export interface PlayerRating {
  id:      number | null;
  name:    string;
  photo:   string | null;
  team:    'home' | 'away';
  rating:  number;
  minutes: number;
  goals:   number;
  assists: number;
  shots:   number;
  passes:  number;
}

/** Un match terminé ne change plus : cache très long. */
const ratingsCache = new Map<number, { data: PlayerRating[]; ts: number }>();
const RATINGS_TTL = 7 * 24 * 60 * 60 * 1000;

// ─── Buteurs ──────────────────────────────────────────────────────────────────

export interface TopScorer {
  rank:    number;
  id:      number | null;
  name:    string;
  photo:   string | null;
  team:    string;
  teamLogo: string | null;
  goals:   number;
  assists: number;
  penalties: number;
  appearances: number;
}

const scorersCache = new Map<string, { data: TopScorer[]; ts: number }>();
const SCORERS_TTL = 6 * 60 * 60 * 1000;

// ══════════════════════════════════════════════════════════════════════════════

export class ApiFootballInsights {
  /**
   * Reçoit le client Axios déjà configuré par `ApiFootballService` plutôt que
   * d'en créer un second : une seule clé, un seul endroit où la lire, et les
   * quotas restent comptés au même endroit.
   */
  constructor(
    private readonly client: AxiosInstance,
    private readonly hasKey: () => boolean,
  ) {}

  /** Pronostic du modèle pour un match, ou null si indisponible. */
  async getPrediction(fixtureId: number): Promise<MatchPrediction | null> {
    if (!this.hasKey()) return null;

    const hit = predictionCache.get(fixtureId);
    if (hit && Date.now() - hit.ts < PREDICTION_TTL) return hit.data;

    try {
      const r = await this.client.get('/predictions', { params: { fixture: fixtureId } });
      const d = r.data?.response?.[0];
      if (!d) return null;

      const p = d.predictions ?? {};
      const c = d.comparison ?? {};
      const th = d.teams?.home?.league ?? {};
      const ta = d.teams?.away?.league ?? {};

      const data: MatchPrediction = {
        // Traduit ici, à la frontière du fournisseur : tous les consommateurs
        // en bénéficient, et aucun écran n'a à connaître l'anglais d'origine.
        advice:        traduireRecommandation(p.advice),
        winnerName:    p.winner?.name ?? null,
        winnerComment: p.winner?.comment ?? null,
        percentHome:   pct(p.percent?.home),
        percentDraw:   pct(p.percent?.draw),
        percentAway:   pct(p.percent?.away),
        underOver:     p.under_over ?? null,
        // Un axe à 0/0 n'est pas une égalité : c'est une absence de donnée. Le
        // filtre ne regardait que l'existence de l'objet, si bien que le
        // « Modèle de Poisson » s'affichait vide sur les matchs de début de
        // saison — une ligne qui n'apprend rien et occupe une place utile.
        comparisons: AXES
          .filter(([cle]) => c[cle])
          .map(([cle, libelle]) => ({
            label: libelle,
            home:  pct(c[cle].home),
            away:  pct(c[cle].away),
          }))
          .filter(a => a.home > 0 || a.away > 0),
        formHome: th.form ?? null,
        formAway: ta.form ?? null,
        cleanSheetHome:    th.clean_sheet?.total ?? 0,
        cleanSheetAway:    ta.clean_sheet?.total ?? 0,
        failedToScoreHome: th.failed_to_score?.total ?? 0,
        failedToScoreAway: ta.failed_to_score?.total ?? 0,
        leagueId:   d.league?.id ?? null,
        season:     d.league?.season ?? null,
        homeTeamId: d.teams?.home?.id ?? null,
        awayTeamId: d.teams?.away?.id ?? null,
        // Rempli juste après : l'évaluation a besoin de l'objet complet.
        modeleExploitable: true,
      };

      // Le fournisseur renvoie parfois des butées plutôt qu'une prédiction —
      // 0 % pour une équipe, tous les axes à 0/100. On le constate ici, une
      // seule fois, plutôt que dans chaque écran qui consomme la donnée.
      const verdict = evaluerFiabilite(data);
      data.modeleExploitable = verdict.exploitable;
      if (!verdict.exploitable) {
        console.warn(
          `[ApiFootball] prédiction inexploitable pour la fixture ${fixtureId} : ${verdict.raison}`);
      }

      predictionCache.set(fixtureId, { data, ts: Date.now() });
      return data;
    } catch (e) {
      console.error('[ApiFootball] /predictions indisponible:', (e as Error).message);
      return null;
    }
  }

  /** Statistiques de saison d'une équipe dans une compétition. */
  async getTeamSeasonStats(
    leagueId: number, season: number, teamId: number,
  ): Promise<TeamSeasonStats | null> {
    if (!this.hasKey()) return null;

    const cle = `${leagueId}_${season}_${teamId}`;
    const hit = seasonStatsCache.get(cle);
    if (hit && Date.now() - hit.ts < SEASON_STATS_TTL) return hit.data;

    try {
      const r = await this.client.get('/teams/statistics', {
        params: { league: leagueId, season, team: teamId },
      });
      const d = r.data?.response;
      if (!d?.goals) return null;

      const parMinute = (bloc: any): Record<string, number> => {
        const out: Record<string, number> = {};
        for (const [tranche, v] of Object.entries<any>(bloc ?? {})) {
          // L'API renvoie null quand aucun but n'est tombé dans la tranche.
          out[tranche] = v?.total ?? 0;
        }
        return out;
      };

      const data: TeamSeasonStats = {
        form: d.form ?? null,
        goalsForByMinute:     parMinute(d.goals.for?.minute),
        goalsAgainstByMinute: parMinute(d.goals.against?.minute),
        goalsForAverage: {
          home:  d.goals.for?.average?.home  ?? '0',
          away:  d.goals.for?.average?.away  ?? '0',
          total: d.goals.for?.average?.total ?? '0',
        },
        // Buts encaissés par match : fournis dans la même réponse, à côté de
        // ceux marqués, et jamais lus. Une attaque à 2,0 face à une défense à
        // 0,5 ne raconte pas la même chose qu'à 2,0 contre 2,0.
        goalsAgainstAverage: {
          home:  d.goals.against?.average?.home  ?? '0',
          away:  d.goals.against?.average?.away  ?? '0',
          total: d.goals.against?.average?.total ?? '0',
        },
        cleanSheetTotal:    d.clean_sheet?.total ?? 0,
        failedToScoreTotal: d.failed_to_score?.total ?? 0,
        penaltyScored:      d.penalty?.scored?.total ?? 0,
        penaltyPercentage:  d.penalty?.scored?.percentage ?? null,
      };

      seasonStatsCache.set(cle, { data, ts: Date.now() });
      return data;
    } catch (e) {
      console.error('[ApiFootball] /teams/statistics indisponible:', (e as Error).message);
      return null;
    }
  }

  /**
   * Cotes en direct d'un match.
   *
   * L'appel sous-jacent n'est **jamais** filtré par fixture : `/odds/live`
   * renvoie tous les matchs en cours pour une seule requête. Filtrer coûterait
   * une requête par match, pour la même donnée.
   */
  async getLiveOdds(fixtureId: number): Promise<LiveOdds | null> {
    const toutes = await this._getAllLiveOdds();
    return toutes?.get(fixtureId) ?? null;
  }

  private async _getAllLiveOdds(): Promise<Map<number, LiveOdds> | null> {
    if (!this.hasKey()) return null;
    if (liveOddsCache && Date.now() - liveOddsCache.ts < LIVE_ODDS_TTL) {
      return liveOddsCache.data;
    }

    try {
      const r = await this.client.get('/odds/live');
      const raw: any[] = r.data?.response ?? [];

      const map = new Map<number, LiveOdds>();
      for (const m of raw) {
        const id = m.fixture?.id;
        if (!id) continue;
        map.set(id, {
          fixtureId: id,
          elapsed:   m.fixture?.status?.elapsed ?? null,
          markets: (m.odds ?? []).map((o: any) => ({
            name: traduireMarche(o.name ?? ''),
            values: (o.values ?? [])
              .map((v: any) => {
                const ligne = extraireLigne(v);
                return {
                  // Le seuil est porté à part : le laisser dans le libellé le
                  // ferait apparaître deux fois là où l'API l'y met déjà.
                  value: libelleSansLigne(String(v.value ?? '')),
                  odd:   parseFloat(v.odd),
                  ...(ligne ? { ligne } : {}),
                };
              })
              // L'API renvoie parfois une cote à 0 sur un marché suspendu :
              // l'afficher ferait croire à une cote nulle.
              .filter((v: LiveOddValue) => Number.isFinite(v.odd) && v.odd > 1),
          }))
            .filter((o: LiveOddMarket) => o.values.length > 0)
            // Un marché à seuil dont le seuil manque se lit à l'envers — la
            // cote peut être prise pour le nombre de buts. On le retire plutôt
            // que d'exposer une ambiguïté.
            .filter((o: LiveOddMarket) => marcheLisible(o.values)),
        });
      }

      liveOddsCache = { data: map, ts: Date.now() };
      return map;
    } catch (e) {
      console.error('[ApiFootball] /odds/live indisponible:', (e as Error).message);
      return null;
    }
  }

  /** Notes des joueurs d'un match terminé, triées de la meilleure à la moins bonne. */
  async getPlayerRatings(
    fixtureId: number, homeTeamId?: number,
  ): Promise<PlayerRating[] | null> {
    if (!this.hasKey()) return null;

    const hit = ratingsCache.get(fixtureId);
    if (hit && Date.now() - hit.ts < RATINGS_TTL) return hit.data;

    try {
      const r = await this.client.get('/fixtures/players', { params: { fixture: fixtureId } });
      const raw: any[] = r.data?.response ?? [];

      const out: PlayerRating[] = [];
      for (const eq of raw) {
        const cote: 'home' | 'away' =
          homeTeamId != null && eq.team?.id === homeTeamId ? 'home'
          : homeTeamId != null ? 'away'
          : (raw.indexOf(eq) === 0 ? 'home' : 'away');

        for (const j of eq.players ?? []) {
          const st = j.statistics?.[0];
          const note = parseFloat(st?.games?.rating);
          // Sans note, le joueur n'a pas joué (ou l'API ne l'a pas évalué) :
          // l'afficher à 0 le ferait passer pour le pire du match.
          if (!Number.isFinite(note)) continue;

          out.push({
            id:      j.player?.id ?? null,
            name:    j.player?.name ?? '',
            photo:   j.player?.photo ?? null,
            team:    cote,
            rating:  note,
            minutes: st?.games?.minutes ?? 0,
            goals:   st?.goals?.total ?? 0,
            assists: st?.goals?.assists ?? 0,
            shots:   st?.shots?.total ?? 0,
            passes:  st?.passes?.total ?? 0,
          });
        }
      }

      out.sort((a, b) => b.rating - a.rating);
      ratingsCache.set(fixtureId, { data: out, ts: Date.now() });
      return out;
    } catch (e) {
      console.error('[ApiFootball] /fixtures/players indisponible:', (e as Error).message);
      return null;
    }
  }

  /** Meilleurs buteurs d'une compétition. */
  async getTopScorers(
    leagueId: number, season: number, limit = 15,
  ): Promise<TopScorer[] | null> {
    if (!this.hasKey()) return null;

    const cle = `${leagueId}_${season}`;
    const hit = scorersCache.get(cle);
    if (hit && Date.now() - hit.ts < SCORERS_TTL) return hit.data.slice(0, limit);

    try {
      const r = await this.client.get('/players/topscorers', {
        params: { league: leagueId, season },
      });
      const raw: any[] = r.data?.response ?? [];

      const data: TopScorer[] = raw.map((e, i) => {
        const st = e.statistics?.[0] ?? {};
        return {
          rank:        i + 1,
          id:          e.player?.id ?? null,
          name:        e.player?.name ?? '',
          photo:       e.player?.photo ?? null,
          team:        st.team?.name ?? '',
          teamLogo:    st.team?.logo ?? null,
          goals:       st.goals?.total ?? 0,
          assists:     st.goals?.assists ?? 0,
          penalties:   st.penalty?.scored ?? 0,
          appearances: st.games?.appearences ?? 0,
        };
      });

      scorersCache.set(cle, { data, ts: Date.now() });
      return data.slice(0, limit);
    } catch (e) {
      console.error('[ApiFootball] /players/topscorers indisponible:', (e as Error).message);
      return null;
    }
  }
}
