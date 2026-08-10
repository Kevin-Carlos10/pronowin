import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/cache/cache_service.dart';
import '../../data/datasources/pronostics_remote_datasource.dart';
import '../../data/models/match_model.dart';
import '../../data/models/league_model.dart';
import '../../data/repositories/pronostics_repository_impl.dart';
import '../../domain/entities/match_entity.dart';
import '../../domain/entities/league_entity.dart';
import '../../domain/repositories/pronostics_repository.dart';
import '../../domain/usecases/get_matches_usecase.dart';
import '../../domain/usecases/get_match_detail_usecase.dart';
import '../../domain/usecases/get_leagues_usecase.dart';

// ─── DI ──────────────────────────────────────────────────────────────────────
final pronosticsDataSourceProvider = Provider<PronosticsRemoteDataSource>(
  (ref) => PronosticsRemoteDataSourceImpl(ref.read(dioProvider)),
);

final pronosticsRepoProvider = Provider<PronosticsRepository>(
  (ref) => PronosticsRepositoryImpl(ref.read(pronosticsDataSourceProvider)),
);

// ─── Filtres état ─────────────────────────────────────────────────────────────
class PronosticsFilter {
  final String sport;
  final String dateFilter;
  final String? leagueId;

  const PronosticsFilter({
    this.sport      = 'all',
    this.dateFilter = 'past30',
    this.leagueId,
  });

  PronosticsFilter copyWith({String? sport, String? dateFilter, String? leagueId}) =>
      PronosticsFilter(
        sport:      sport      ?? this.sport,
        dateFilter: dateFilter ?? this.dateFilter,
        leagueId:   leagueId   ?? this.leagueId,
      );
}

String _todayStr() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4,'0')}-'
      '${d.month.toString().padLeft(2,'0')}-'
      '${d.day.toString().padLeft(2,'0')}';
}

final pronosticsFilterProvider = StateProvider<PronosticsFilter>(
  (_) => PronosticsFilter(dateFilter: _todayStr()),
);

/// Filtre statut côté serveur : null=tous, upcoming, live, finished
final statusFilterProvider = StateProvider<MatchStatus?>((ref) => null);

/// Filtre "avec pronostic uniquement" côté serveur : false = tous les matchs
/// (avec ou sans pronostic, y compris "analyse en cours")
final hasPronosticFilterProvider = StateProvider<bool>((ref) => false);

/// Filtre ligue côté client : null = toutes
final leagueFilterProvider = StateProvider<String?>((ref) => null);

/// Plage de cote recommandée côté client
enum OddsRange { all, under15, from15to25, from25to4, over4 }

final oddsRangeFilterProvider = StateProvider<OddsRange>((ref) => OddsRange.all);

// ─── État paginé ──────────────────────────────────────────────────────────────
class MatchesPaginatedState {
  final List<MatchEntity> matches;
  final String?           nextCursor;
  final bool              hasMore;
  final bool              isInitialLoading;
  final bool              isLoadingMore;
  final String?           error;

  const MatchesPaginatedState({
    this.matches          = const [],
    this.nextCursor,
    this.hasMore          = true,
    this.isInitialLoading = true,
    this.isLoadingMore    = false,
    this.error,
  });

  MatchesPaginatedState copyWith({
    List<MatchEntity>? matches,
    String?            nextCursor,
    bool?              hasMore,
    bool?              isInitialLoading,
    bool?              isLoadingMore,
    String?            error,
    bool               clearError = false,
    bool               clearCursor = false,
  }) => MatchesPaginatedState(
    matches:          matches          ?? this.matches,
    nextCursor:       clearCursor ? null : (nextCursor ?? this.nextCursor),
    hasMore:          hasMore          ?? this.hasMore,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isLoadingMore:    isLoadingMore    ?? this.isLoadingMore,
    error:            clearError ? null : (error ?? this.error),
  );
}

String? _statusParam(MatchStatus? status) => switch (status) {
  MatchStatus.upcoming => 'upcoming',
  MatchStatus.live     => 'live',
  MatchStatus.finished => 'finished',
  null                 => null,
};

class MatchesPaginatedNotifier extends StateNotifier<MatchesPaginatedState> {
  final GetMatchesUseCase _usecase;
  PronosticsFilter        _filter;
  final MatchStatus?      _status;
  final bool              _hasPronostic;

  MatchesPaginatedNotifier(this._usecase, this._filter, this._status, this._hasPronostic)
      : super(const MatchesPaginatedState()) {
    _loadInitial();
  }

  static const _limit = 20;

  Future<void> _loadInitial() async {
    state = state.copyWith(
      isInitialLoading: true,
      matches:          [],
      clearCursor:      true,
      hasMore:          true,
      clearError:       true,
    );

    final cacheKey = 'matches_${_filter.sport}_${_filter.dateFilter}_${_filter.leagueId ?? "all"}_${_statusParam(_status) ?? "all"}_$_hasPronostic';

    try {
      final result = await _usecase(GetMatchesParams(
        sport:        _filter.sport == 'all' ? null : _filter.sport,
        dateFilter:   _filter.dateFilter,
        leagueId:     _filter.leagueId,
        status:       _statusParam(_status),
        hasPronostic: _hasPronostic,
        limit:        _limit,
      ));

      result.fold(
        (failure) => state = state.copyWith(
          isInitialLoading: false,
          error:            failure.message,
        ),
        (page) async {
          await CacheService.save(cacheKey,
              page.data.map((m) => (m as MatchModel).toJson()).toList());
          state = state.copyWith(
            matches:          page.data,
            nextCursor:       page.nextCursor,
            hasMore:          page.hasMore,
            isInitialLoading: false,
          );
        },
      );
    } catch (e) {
      // Fallback cache
      final cached = await CacheService.load<List<MatchEntity>>(
        cacheKey,
        (d) => (d as List).map((e) => MatchModel.fromJson(e as Map<String, dynamic>)).toList(),
      );
      if (cached != null) {
        state = state.copyWith(
          matches:          cached,
          hasMore:          false,
          isInitialLoading: false,
        );
      } else {
        state = state.copyWith(
          isInitialLoading: false,
          error:            e.toString().replaceAll('Exception:', '').trim(),
        );
      }
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isInitialLoading) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _usecase(GetMatchesParams(
        sport:        _filter.sport == 'all' ? null : _filter.sport,
        dateFilter:   _filter.dateFilter,
        leagueId:     _filter.leagueId,
        status:       _statusParam(_status),
        hasPronostic: _hasPronostic,
        cursor:       state.nextCursor,
        limit:        _limit,
      ));

      result.fold(
        (failure) => state = state.copyWith(isLoadingMore: false),
        (page) => state = state.copyWith(
          matches:       [...state.matches, ...page.data],
          nextCursor:    page.nextCursor,
          hasMore:       page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void resetWithFilter(PronosticsFilter filter) {
    _filter = filter;
    _loadInitial();
  }

  void refresh() => _loadInitial();
}

final matchesPaginatedProvider =
    StateNotifierProvider.autoDispose<MatchesPaginatedNotifier, MatchesPaginatedState>((ref) {
  final filter       = ref.watch(pronosticsFilterProvider);
  final status       = ref.watch(statusFilterProvider);
  final hasPronostic = ref.watch(hasPronosticFilterProvider);
  final usecase      = GetMatchesUseCase(ref.read(pronosticsRepoProvider));
  return MatchesPaginatedNotifier(usecase, filter, status, hasPronostic);
});

// ─── Détail d'un match ────────────────────────────────────────────────────────
final matchDetailProvider = FutureProvider.autoDispose.family<MatchEntity, String>((ref, id) async {
  final usecase  = GetMatchDetailUseCase(ref.read(pronosticsRepoProvider));
  final cacheKey = 'match_detail_$id';
  try {
    final result = await usecase(id);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (match) async {
        await CacheService.save(cacheKey, (match as MatchModel).toJson());
        return match;
      },
    );
  } catch (_) {
    final cached = await CacheService.loadStale<MatchEntity>(
      cacheKey, (d) => MatchModel.fromJson(d as Map<String, dynamic>));
    if (cached != null) return cached;
    rethrow;
  }
});

// ─── Score live (polling léger) ───────────────────────────────────────────────
class LiveScore {
  final int? homeScore, awayScore;
  final String status;
  const LiveScore({this.homeScore, this.awayScore, required this.status});
}

final liveScoreProvider = FutureProvider.autoDispose.family<LiveScore, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/score');
  return LiveScore(
    homeScore: r.data['homeScore'] as int?,
    awayScore: r.data['awayScore'] as int?,
    status:    r.data['status']    as String? ?? 'SCHEDULED',
  );
});

// ─── Analyse IA ──────────────────────────────────────────────────────────────
class AiAnalysis {
  final int    probability;
  final String explanation;
  const AiAnalysis({required this.probability, required this.explanation});
}

final aiAnalysisProvider = FutureProvider.autoDispose.family<AiAnalysis, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/ai-analyze');
  return AiAnalysis(
    probability: (r.data['probability'] as num).toInt(),
    explanation: r.data['explanation'] as String,
  );
});

// ─── H2H ─────────────────────────────────────────────────────────────────────
class H2HMatchResult {
  final DateTime date;
  final String   homeTeam;
  final String   awayTeam;
  final int      homeScore;
  final int      awayScore;
  final String   winner;
  final String   league;
  const H2HMatchResult({
    required this.date, required this.homeTeam, required this.awayTeam,
    required this.homeScore, required this.awayScore,
    required this.winner, required this.league,
  });
}

class H2HData {
  final String homeTeam;
  final String awayTeam;
  final int    homeWins;
  final int    awayWins;
  final int    draws;
  final int    totalMatches;
  final List<H2HMatchResult> matches;
  const H2HData({
    required this.homeTeam, required this.awayTeam,
    required this.homeWins, required this.awayWins,
    required this.draws, required this.totalMatches,
    required this.matches,
  });
}

final h2hProvider = FutureProvider.autoDispose.family<H2HData, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/h2h');
  final d   = r.data as Map<String, dynamic>;
  final agg = d['aggregates'] as Map<String, dynamic>;
  final hAgg = agg['homeTeam'] as Map<String, dynamic>;
  final aAgg = agg['awayTeam'] as Map<String, dynamic>;

  final matches = (d['matches'] as List).map((m) {
    final mm = m as Map<String, dynamic>;
    return H2HMatchResult(
      date:      DateTime.parse(mm['date'] as String),
      homeTeam:  mm['home_team'] as String,
      awayTeam:  mm['away_team'] as String,
      homeScore: (mm['home_score'] as num).toInt(),
      awayScore: (mm['away_score'] as num).toInt(),
      winner:    mm['winner'] as String? ?? 'DRAW',
      league:    mm['league']  as String? ?? '',
    );
  }).toList();

  return H2HData(
    homeTeam:     d['home_team'] as String,
    awayTeam:     d['away_team'] as String,
    homeWins:     (hAgg['wins']   as num).toInt(),
    awayWins:     (aAgg['wins']   as num).toInt(),
    draws:        (hAgg['draws']  as num).toInt(),
    totalMatches: (agg['numberOfMatches'] as num).toInt(),
    matches:      matches,
  );
});

// ─── Compositions d'équipe ─────────────────────────────────────────────────────
class LineupPlayer {
  final int?    id;
  final String  name;
  final int?    number;
  final String? pos;
  /// Position sur le terrain renvoyée par API-Football, "ligne:colonne"
  /// (ex. "1:1" = gardien). null pour les remplaçants.
  final String? grid;
  const LineupPlayer({required this.name, this.id, this.number, this.pos, this.grid});

  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
    id:     (j['id'] as num?)?.toInt(),
    name:   j['name'] as String? ?? '',
    number: (j['number'] as num?)?.toInt(),
    pos:    j['pos'] as String?,
    grid:   j['grid'] as String?,
  );

  /// Ligne du joueur sur le terrain (1 = gardien), null si non placé.
  int? get gridRow => _gridPart(0);
  /// Colonne du joueur dans sa ligne, null si non placé.
  int? get gridCol => _gridPart(1);

  int? _gridPart(int i) {
    final parts = grid?.split(':');
    if (parts == null || parts.length != 2) return null;
    return int.tryParse(parts[i]);
  }

  /// Photo officielle API-Football, null si le joueur n'a pas d'id.
  String? get photoUrl =>
    id == null ? null : 'https://media.api-sports.io/football/players/$id.png';

  /// "M. Kovář" — nom compact pour tenir sous une pastille du terrain.
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }
}

class TeamLineup {
  final String? formation;
  final String? coach;
  final List<LineupPlayer> startXI;
  final List<LineupPlayer> substitutes;
  const TeamLineup({
    this.formation, this.coach,
    required this.startXI, required this.substitutes,
  });

  factory TeamLineup.fromJson(Map<String, dynamic> j) => TeamLineup(
    formation:   j['formation'] as String?,
    coach:       j['coach'] as String?,
    startXI:     (j['startXI'] as List? ?? [])
      .map((p) => LineupPlayer.fromJson(p as Map<String, dynamic>)).toList(),
    substitutes: (j['substitutes'] as List? ?? [])
      .map((p) => LineupPlayer.fromJson(p as Map<String, dynamic>)).toList(),
  );
}

class LineupsData {
  final bool available;
  final TeamLineup? home;
  final TeamLineup? away;
  const LineupsData({required this.available, this.home, this.away});
}

final lineupsProvider = FutureProvider.autoDispose.family<LineupsData, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/lineups');
  final d   = r.data as Map<String, dynamic>;
  return LineupsData(
    available: d['available'] as bool? ?? false,
    home: d['home'] != null ? TeamLineup.fromJson(d['home'] as Map<String, dynamic>) : null,
    away: d['away'] != null ? TeamLineup.fromJson(d['away'] as Map<String, dynamic>) : null,
  );
});

// ─── Blessures / suspensions ───────────────────────────────────────────────────
class InjuredPlayer {
  final String name;
  final bool   isHome;
  final String type;
  final String reason;
  const InjuredPlayer({
    required this.name, required this.isHome,
    required this.type, required this.reason,
  });

  factory InjuredPlayer.fromJson(Map<String, dynamic> j) => InjuredPlayer(
    name:   j['name'] as String? ?? '',
    isHome: j['team'] == 'home',
    type:   j['type'] as String? ?? 'Injured',
    reason: j['reason'] as String? ?? '',
  );
}

final injuriesProvider = FutureProvider.autoDispose.family<List<InjuredPlayer>, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/injuries');
  return (r.data as List)
    .map((e) => InjuredPlayer.fromJson(e as Map<String, dynamic>))
    .toList();
});

// ─── Classement ─────────────────────────────────────────────────────────────────
class StandingRow {
  final int    rank;
  final String teamName;
  final String? teamLogo;
  final int    played, win, draw, lose, goalsDiff, points;
  final String? form;
  const StandingRow({
    required this.rank, required this.teamName, this.teamLogo,
    required this.played, required this.win, required this.draw, required this.lose,
    required this.goalsDiff, required this.points, this.form,
  });

  factory StandingRow.fromJson(Map<String, dynamic> j) => StandingRow(
    rank:      (j['rank'] as num).toInt(),
    teamName:  j['teamName'] as String? ?? '',
    teamLogo:  j['teamLogo'] as String?,
    played:    (j['played'] as num?)?.toInt() ?? 0,
    win:       (j['win'] as num?)?.toInt() ?? 0,
    draw:      (j['draw'] as num?)?.toInt() ?? 0,
    lose:      (j['lose'] as num?)?.toInt() ?? 0,
    goalsDiff: (j['goalsDiff'] as num?)?.toInt() ?? 0,
    points:    (j['points'] as num?)?.toInt() ?? 0,
    form:      j['form'] as String?,
  );
}

final standingsProvider = FutureProvider.autoDispose.family<List<StandingRow>, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/$id/standings');
  return (r.data as List)
    .map((e) => StandingRow.fromJson(e as Map<String, dynamic>))
    .toList();
});

// ─── Statistiques match terminé (API-Football) ───────────────────────────────
class MatchEvent {
  final int    minute;
  final int?   extra;
  final String team;
  final String player;
  final String? assist;
  final String type;
  final String detail;
  const MatchEvent({
    required this.minute, this.extra, required this.team,
    required this.player, this.assist,
    required this.type, required this.detail,
  });
}

class MatchStat {
  final String label;
  final dynamic home;
  final dynamic away;
  const MatchStat({required this.label, this.home, this.away});
}

class MatchStatsData {
  final int             fixtureId;
  final List<MatchEvent> events;
  final List<MatchStat>  stats;
  final String          homeTeam;
  final String          awayTeam;
  const MatchStatsData({
    required this.fixtureId, required this.events,
    required this.stats, required this.homeTeam, required this.awayTeam,
  });
}

final matchStatsProvider = FutureProvider.autoDispose.family<MatchStatsData?, String>((ref, id) async {
  final dio = ref.read(dioProvider);
  try {
    final r = await dio.get('/pronostics/$id/match-stats');
    final d = r.data as Map<String, dynamic>;
    final events = (d['events'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return MatchEvent(
        minute: (m['minute'] as num).toInt(),
        extra:  m['extra'] != null ? (m['extra'] as num).toInt() : null,
        team:   m['team']   as String? ?? '',
        player: m['player'] as String? ?? '',
        assist: m['assist'] as String?,
        type:   m['type']   as String? ?? '',
        detail: m['detail'] as String? ?? '',
      );
    }).toList();
    final stats = (d['stats'] as List).map((s) {
      final m = s as Map<String, dynamic>;
      return MatchStat(label: m['label'] as String, home: m['home'], away: m['away']);
    }).toList();
    return MatchStatsData(
      fixtureId: (d['fixture_id'] as num).toInt(),
      events:    events,
      stats:     stats,
      homeTeam:  d['home_team'] as String,
      awayTeam:  d['away_team'] as String,
    );
  } catch (_) {
    return null;
  }
});

// ─── Prono gratuit du jour ────────────────────────────────────────────────────
final dailyPronoProvider = FutureProvider<MatchEntity?>((ref) async {
  final dio = ref.read(dioProvider);
  try {
    final r = await dio.get('/pronostics/daily');
    if (r.data == null) return null;
    return MatchModel.fromJson(r.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

// ─── Pronostics IA personnalisés ──────────────────────────────────────────────
class ForYouRec {
  final int            score;
  final List<String>   reasons;
  final ForYouProno    pronostic;
  const ForYouRec({required this.score, required this.reasons, required this.pronostic});

  factory ForYouRec.fromJson(Map<String, dynamic> j) => ForYouRec(
    score:     (j['score'] as num).toInt(),
    reasons:   List<String>.from(j['reasons'] as List),
    pronostic: ForYouProno.fromJson(j['pronostic'] as Map<String, dynamic>),
  );
}

class ForYouProno {
  final String  id, league, leagueCode, homeTeam, awayTeam;
  final String  predictionType, predictionLabel;
  final double  oddsRecommended;
  final int     confidenceScore, aiProbability;
  final String? analystNote, analystName;
  final bool    isPremium;
  final DateTime matchDate;
  const ForYouProno({
    required this.id, required this.league, required this.leagueCode,
    required this.homeTeam, required this.awayTeam,
    required this.predictionType, required this.predictionLabel,
    required this.oddsRecommended, required this.confidenceScore,
    required this.aiProbability, required this.matchDate,
    this.analystNote, this.analystName, this.isPremium = false,
  });
  factory ForYouProno.fromJson(Map<String, dynamic> j) => ForYouProno(
    id:               j['id'] as String,
    league:           j['league'] as String,
    leagueCode:       j['league_code'] as String,
    homeTeam:         j['home_team'] as String,
    awayTeam:         j['away_team'] as String,
    predictionType:   j['prediction_type'] as String,
    predictionLabel:  j['prediction_label'] as String,
    oddsRecommended:  (j['odds_recommended'] as num).toDouble(),
    confidenceScore:  (j['confidence_score'] as num).toInt(),
    aiProbability:    (j['ai_probability'] as num).toInt(),
    matchDate:        DateTime.parse(j['match_date'] as String),
    analystNote:      j['analyst_note'] as String?,
    analystName:      j['analyst_name'] as String?,
    isPremium:        (j['is_premium'] as bool?) ?? false,
  );
}

class ForYouProfile {
  final int      totalBets, winRate;
  final List<String> topLeagues, topBetTypes;
  final double   oddsSweetMin, oddsSweetMax;
  final bool     isNewUser;
  const ForYouProfile({
    required this.totalBets, required this.winRate,
    required this.topLeagues, required this.topBetTypes,
    required this.oddsSweetMin, required this.oddsSweetMax,
    required this.isNewUser,
  });
  factory ForYouProfile.fromJson(Map<String, dynamic> j) => ForYouProfile(
    totalBets:    (j['total_bets']     as num).toInt(),
    winRate:      (j['win_rate']       as num).toInt(),
    topLeagues:   List<String>.from(j['top_leagues'] as List),
    topBetTypes:  List<String>.from(j['top_bet_types'] as List),
    oddsSweetMin: (j['odds_sweet_min'] as num).toDouble(),
    oddsSweetMax: (j['odds_sweet_max'] as num).toDouble(),
    isNewUser:    (j['is_new_user']    as bool?) ?? true,
  );
}

class ForYouData {
  final ForYouProfile      profile;
  final List<ForYouRec>    recommendations;
  const ForYouData({required this.profile, required this.recommendations});
}

final forYouProvider = FutureProvider.autoDispose<ForYouData>((ref) async {
  final dio = ref.read(dioProvider);
  final r   = await dio.get('/pronostics/for-you');
  final d   = r.data as Map<String, dynamic>;
  return ForYouData(
    profile:         ForYouProfile.fromJson(d['profile'] as Map<String, dynamic>),
    recommendations: (d['recommendations'] as List)
        .map((e) => ForYouRec.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

// ─── Comptage de matchs par jour (sélecteur de dates) ──────────────────────────
// Fenêtre complète (30j passés + 7j à venir) indépendante du jour sélectionné —
// contrairement à matchesPaginatedProvider qui ne charge que le jour en cours.
final dayCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  const cacheKey = 'pronostics_day_counts';
  try {
    final r    = await ref.read(dioProvider).get('/pronostics/counts-by-day');
    final data = (r.data as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    await CacheService.save(cacheKey, data);
    return data;
  } catch (_) {
    return await CacheService.loadStale<Map<String, int>>(
      cacheKey, (d) => (d as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int))) ?? {};
  }
});

// ─── Totaux réels du jour (barre de stats) ─────────────────────────────────────
// Indépendant de matchesPaginatedProvider, qui ne reflète que la page déjà
// chargée : sans ça, "0 prono" ne veut souvent rien dire (les premiers matchs
// du jour, triés par heure, n'ont pas encore de pronostic publié).
class DaySummary {
  final int total;
  final int withPronostic;
  final int live;
  const DaySummary({required this.total, required this.withPronostic, required this.live});

  factory DaySummary.fromJson(Map<String, dynamic> j) => DaySummary(
    total:         j['total']         as int? ?? 0,
    withPronostic: j['withPronostic'] as int? ?? 0,
    live:          j['live']          as int? ?? 0,
  );

  Map<String, dynamic> toJson() =>
      {'total': total, 'withPronostic': withPronostic, 'live': live};
}

final daySummaryProvider =
    FutureProvider.autoDispose.family<DaySummary, String>((ref, dateFilter) async {
  final cacheKey = 'pronostics_day_summary_$dateFilter';
  try {
    final r = await ref.read(dioProvider).get(
      '/pronostics/day-summary',
      queryParameters: {'date_filter': dateFilter},
    );
    final summary = DaySummary.fromJson(r.data as Map<String, dynamic>);
    await CacheService.save(cacheKey, summary.toJson());
    return summary;
  } catch (_) {
    return await CacheService.loadStale<DaySummary>(
        cacheKey, (d) => DaySummary.fromJson(d as Map<String, dynamic>)) ??
        const DaySummary(total: 0, withPronostic: 0, live: 0);
  }
});

// ─── Ligues ───────────────────────────────────────────────────────────────────
final leaguesProvider = FutureProvider<List<LeagueEntity>>((ref) async {
  const cacheKey = 'leagues';
  final usecase  = GetLeaguesUseCase(ref.read(pronosticsRepoProvider));
  try {
    final result = await usecase();
    return result.fold(
      (f) => throw Exception(f.message),
      (leagues) async {
        await CacheService.save(cacheKey,
            leagues.map((l) => (l as LeagueModel).toJson()).toList());
        return leagues;
      },
    );
  } catch (_) {
    final cached = await CacheService.loadStale<List<LeagueEntity>>(
      cacheKey,
      (d) => (d as List).map((e) => LeagueModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
    if (cached != null) return cached;
    rethrow;
  }
});
