import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../../domain/entities/match_entity.dart';
import '../../domain/entities/league_entity.dart';
import '../../domain/repositories/pronostics_repository.dart';
import '../datasources/pronostics_remote_datasource.dart';

class PronosticsRepositoryImpl implements PronosticsRepository {
  final PronosticsRemoteDataSource _remote;
  PronosticsRepositoryImpl(this._remote);

  @override
  Future<Either<Failure, MatchesPageResult>> getMatches({
    String? leagueId,
    String? dateFilter,
    String? sport,
    String? cursor,
    int     limit = 20,
  }) async {
    try {
      final page = await _remote.getMatches(
        leagueId: leagueId, dateFilter: dateFilter, sport: sport,
        cursor: cursor, limit: limit,
      );
      return Right(MatchesPageResult(
        data:       page.data,
        nextCursor: page.nextCursor,
        hasMore:    page.hasMore,
      ));
    } on Failure catch (f) { return Left(f); }
    catch (e)              { return Left(UnknownFailure()); }
  }

  @override
  Future<Either<Failure, MatchEntity>> getMatchDetail(String matchId) async {
    try {
      final match = await _remote.getMatchDetail(matchId);
      return Right(match);
    } on Failure catch (f) { return Left(f); }
    catch (e)              { return Left(UnknownFailure()); }
  }

  @override
  Future<Either<Failure, List<LeagueEntity>>> getLeagues() async {
    try {
      final leagues = await _remote.getLeagues();
      return Right(leagues);
    } on Failure catch (f) { return Left(f); }
    catch (e)              { return Left(UnknownFailure()); }
  }
}
