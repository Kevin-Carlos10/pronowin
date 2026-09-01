import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../repositories/pronostics_repository.dart';

class GetMatchesParams {
  final String? leagueId;
  final String? dateFilter;
  final String? sport;
  final String? status;
  final bool?   hasPronostic;
  final String? cursor;
  final int     limit;
  const GetMatchesParams({
    this.leagueId,
    this.dateFilter,
    this.sport,
    this.status,
    this.hasPronostic,
    this.cursor,
    this.limit = 20,
  });
}

class GetMatchesUseCase {
  final PronosticsRepository _repo;
  GetMatchesUseCase(this._repo);

  Future<Either<Failure, MatchesPageResult>> call(GetMatchesParams params) =>
      _repo.getMatches(
        leagueId:     params.leagueId,
        dateFilter:   params.dateFilter,
        sport:        params.sport,
        status:       params.status,
        hasPronostic: params.hasPronostic,
        cursor:       params.cursor,
        limit:        params.limit,
      );
}
