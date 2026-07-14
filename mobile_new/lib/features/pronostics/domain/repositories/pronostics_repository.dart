import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/match_entity.dart';
import '../entities/league_entity.dart';

class MatchesPageResult {
  final List<MatchEntity> data;
  final String? nextCursor;
  final bool hasMore;
  const MatchesPageResult({required this.data, this.nextCursor, required this.hasMore});
}

abstract class PronosticsRepository {
  Future<Either<Failure, MatchesPageResult>> getMatches({
    String? leagueId,
    String? dateFilter,
    String? sport,
    String? cursor,
    int     limit,
  });

  Future<Either<Failure, MatchEntity>> getMatchDetail(String matchId);

  Future<Either<Failure, List<LeagueEntity>>> getLeagues();
}
