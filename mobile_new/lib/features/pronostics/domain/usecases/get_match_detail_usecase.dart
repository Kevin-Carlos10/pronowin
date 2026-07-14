import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/match_entity.dart';
import '../repositories/pronostics_repository.dart';

class GetMatchDetailUseCase {
  final PronosticsRepository _repo;
  GetMatchDetailUseCase(this._repo);

  Future<Either<Failure, MatchEntity>> call(String matchId) =>
      _repo.getMatchDetail(matchId);
}
