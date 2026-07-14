import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/tutorial_entity.dart';
import '../repositories/tutorial_repository.dart';

class GetTutorialsParams {
  final TutorialLevel?    level;
  final TutorialCategory? category;
  const GetTutorialsParams({this.level, this.category});
}

class GetTutorialsUseCase {
  final TutorialRepository _repo;
  GetTutorialsUseCase(this._repo);
  Future<Either<Failure, List<TutorialEntity>>> call(GetTutorialsParams p) =>
      _repo.getTutorials(level: p.level, category: p.category);
}
