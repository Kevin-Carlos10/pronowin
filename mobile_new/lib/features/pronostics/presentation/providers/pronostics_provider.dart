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

/// Filtre statut côté client : null=tous, upcoming, live, finished
final statusFilterProvider = StateProvider<MatchStatus?>((ref) => null);

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

class MatchesPaginatedNotifier extends StateNotifier<MatchesPaginatedState> {
  final GetMatchesUseCase _usecase;
  PronosticsFilter        _filter;

  MatchesPaginatedNotifier(this._usecase, this._filter)
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

    final cacheKey = 'matches_${_filter.sport}_${_filter.dateFilter}_${_filter.leagueId ?? "all"}';

    try {
      final result = await _usecase(GetMatchesParams(
        sport:      _filter.sport == 'all' ? null : _filter.sport,
        dateFilter: _filter.dateFilter,
        leagueId:   _filter.leagueId,
        limit:      _limit,
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
        sport:      _filter.sport == 'all' ? null : _filter.sport,
        dateFilter: _filter.dateFilter,
        leagueId:   _filter.leagueId,
        cursor:     state.nextCursor,
        limit:      _limit,
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
  final filter  = ref.watch(pronosticsFilterProvider);
  final usecase = GetMatchesUseCase(ref.read(pronosticsRepoProvider));
  return MatchesPaginatedNotifier(usecase, filter);
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
