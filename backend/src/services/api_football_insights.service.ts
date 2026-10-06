import type { AxiosInstance } from 'axios';
import { CacheFootball, responseFootball, exigerQuotaEnrichissement } from './cache_football';
import { enrichissementsFootball } from './enrichissements_football';
import { traduireRecommandation } from './traduction_recommandation';
import { extraireLigne, libelleSansLigne, marcheLisible, traduireMarche } from './cotes_live';
import { evaluerFiabilite } from './fiabilite_modele';
import { journal } from '../utils/logger';

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
  /** Matchs joués, gagnés, nuls, perdus — fournis dans la même réponse. */
  bilan?:              { joues: number; victoires: number; nuls: number; defaites: number };
  /** Le système le plus aligné cette saison, ex. « 4-3-3 ». */
  systeme?:            string | null;
}

const SEASON_STATS_TTL = 24 * 60 * 60 * 1000;

// ─── Cotes en direct ──────────────────────────────────────────────────────────

export interface LiveOddValue {
  value: string;
  odd:   number;
  /** Seuil du marché — « 2.5 », « -0.5 ». Absent quand il n'y en a pas. */
  ligne?: string;
}
export interface LiveOddMarket { key?: string; name: string; values: LiveOddValue[]; }

export interface LiveOdds {
  fixtureId: number;
  updated_at?: string | null;
  stale?: boolean;
  elapsed:   number | null;
  markets:   LiveOddMarket[];
}

/**
 * Cache **global** des cotes live : `/odds/live` sans paramètre renvoie tous
 * les matchs en cours d'un coup. Un appel toutes les 2 minutes suffit — les
 * cotes bougent, mais pas au point de justifier 30 s (× 4 le coût en quota).
 */
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
const RATINGS_TTL = 5 * 60 * 1000;

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
  yellowCards: number;
  redCards:    number;
}

/**
 * Les palmarès individuels d'une compétition que l'API publie.
 *
 * Seuls les buteurs étaient lus. Les passeurs et les cartons viennent du
 * même plan, au même prix — une requête par compétition et par saison, gardée
 * six heures — et les cartons servent directement les marchés « nombre de
 * cartons » sur lesquels portent des pronostics.
 */
export const CLASSEMENTS_JOUEURS = {
  buteurs:  '/players/topscorers',
  passeurs: '/players/topassists',
  jaunes:   '/players/topyellowcards',
  rouges:   '/players/topredcards',
} as const;
export type ClassementJoueurs = keyof typeof CLASSEMENTS_JOUEURS;

const SCORERS_TTL = 6 * 60 * 60 * 1000;

// ══════════════════════════════════════════════════════════════════════════════

export class ApiFootballInsights {
  private liveOddsCache = new CacheFootball<Map<number, LiveOdds>>(1, 5 * 60_000);
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

    try {
      const rows = await enrichissementsFootball(this.client).get('/predictions', { fixture: fixtureId }, PREDICTION_TTL);
      const d = rows[0];
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
        journal.warn(
          `[ApiFootball] prédiction inexploitable pour la fixture ${fixtureId} : ${verdict.raison}`);
      }

      return data;
    } catch (e) {
      journal.error('[ApiFootball] /predictions indisponible:', (e as Error).message);
      return null;
    }
  }

  /** Statistiques de saison d'une équipe dans une compétition. */
  async getTeamSeasonStats(
    leagueId: number, season: number, teamId: number,
  ): Promise<TeamSeasonStats | null> {
    if (!this.hasKey()) return null;

    try {
      const d = await enrichissementsFootball(this.client).object('/teams/statistics',
        { league: leagueId, season, team: teamId }, SEASON_STATS_TTL);
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
        bilan: {
          joues:     d.fixtures?.played?.total ?? 0,
          victoires: d.fixtures?.wins?.total ?? 0,
          nuls:      d.fixtures?.draws?.total ?? 0,
          defaites:  d.fixtures?.loses?.total ?? 0,
        },
        systeme: [...(d.lineups ?? [])]
          .sort((a: any, b: any) => (b?.played ?? 0) - (a?.played ?? 0))[0]?.formation ?? null,
      };

      return data;
    } catch (e) {
      journal.error('[ApiFootball] /teams/statistics indisponible:', (e as Error).message);
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
    const result = await this.liveOddsCache.read('all', LIVE_ODDS_TTL, () => this._getAllLiveOdds());
    const odds = result.data?.get(fixtureId);
    return odds ? { ...odds, updated_at: result.updatedAt, stale: result.stale } : null;
  }

  private async _getAllLiveOdds(): Promise<Map<number, LiveOdds>> {
    if (!this.hasKey()) throw new Error('Football API unavailable');

    try {
      exigerQuotaEnrichissement();
      const r = await this.client.get('/odds/live');
      const raw = responseFootball(r.data);

      const map = new Map<number, LiveOdds>();
      for (const m of raw) {
        const id = m.fixture?.id;
        if (!id || m.status?.blocked || m.status?.stopped || m.status?.finished) continue;
        map.set(id, {
          fixtureId: id,
          elapsed:   m.fixture?.status?.elapsed ?? null,
          markets: (m.odds ?? []).map((o: any) => ({
            key: String(o.name ?? '').trim().toLowerCase(),
            name: traduireMarche(o.name ?? ''),
            values: (o.values ?? [])
              .filter((v: any) => !o.suspended && !o.blocked && !o.stopped && !v.suspended && !v.blocked && !v.stopped)
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

      return map;
    } catch (e) {
      journal.error('[ApiFootball] /odds/live indisponible:', (e as Error).message);
      throw e;
    }
  }

  /** Notes des joueurs d'un match terminé, triées de la meilleure à la moins bonne. */
  async getPlayerRatings(
    fixtureId: number, homeTeamId?: number,
  ): Promise<PlayerRating[] | null> {
    if (!this.hasKey()) return null;

    try {
      const raw = await enrichissementsFootball(this.client).get('/fixtures/players', { fixture: fixtureId }, RATINGS_TTL);

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

      return out;
    } catch (e) {
      journal.error('[ApiFootball] /fixtures/players indisponible:', (e as Error).message);
      return null;
    }
  }

  /** Meilleurs buteurs d'une compétition. */
  async getTopScorers(
    leagueId: number, season: number, limit = 15,
  ): Promise<TopScorer[] | null> {
    return this.getTopPlayers('buteurs', leagueId, season, limit);
  }

  /**
   * Un palmarès individuel d'une compétition, dans l'ordre que l'API lui
   * donne (buts, passes décisives, cartons jaunes ou rouges).
   */
  async getTopPlayers(
    type: ClassementJoueurs, leagueId: number, season: number, limit = 15,
  ): Promise<TopScorer[] | null> {
    if (!this.hasKey()) return null;

    const chemin = CLASSEMENTS_JOUEURS[type];
    try {
      const raw = await enrichissementsFootball(this.client).get(chemin, { league: leagueId, season }, SCORERS_TTL);

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
          yellowCards: st.cards?.yellow ?? 0,
          redCards:    st.cards?.red ?? 0,
        };
      });

      return data.slice(0, limit);
    } catch (e) {
      journal.error(`[ApiFootball] ${chemin} indisponible:`, (e as Error).message);
      return null;
    }
  }
}
