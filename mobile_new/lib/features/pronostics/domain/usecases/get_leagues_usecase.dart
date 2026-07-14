import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/league_entity.dart';
import '../repositories/pronostics_repository.dart';

class GetLeaguesUseCase {
  final PronosticsRepository _repo;
  GetLeaguesUseCase(this._repo);

  Future<Either<Failure, List<LeagueEntity>>> call() => _repo.getLeagues();
}
