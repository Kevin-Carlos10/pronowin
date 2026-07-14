import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../repositories/tutorial_repository.dart';

class MarkProgressUseCase {
  final TutorialRepository _repo;
  MarkProgressUseCase(this._repo);
  Future<Either<Failure, void>> call(String id, int seconds, bool completed) =>
      _repo.markProgress(id, seconds, completed);
}
