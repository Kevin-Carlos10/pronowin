import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../../domain/entities/tutorial_entity.dart';
import '../../domain/repositories/tutorial_repository.dart';
import '../datasources/tutorial_remote_datasource.dart';

class TutorialRepositoryImpl implements TutorialRepository {
  final TutorialRemoteDataSource _remote;
  TutorialRepositoryImpl(this._remote);

  @override Future<Either<Failure, List<TutorialEntity>>> getTutorials({TutorialLevel? level, TutorialCategory? category, bool? premiumOnly}) async {
    try { return Right(await _remote.getTutorials(level: level, category: category)); }
    on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, TutorialEntity>> getTutorialDetail(String id) async {
    try { return Right(await _remote.getTutorialDetail(id)); }
    on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, void>> markProgress(String id, int s, bool c) async {
    try { await _remote.markProgress(id, s, c); return const Right(null); }
    on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, List<TutorialProgressEntity>>> getProgress() async =>
    const Right([]);
}
