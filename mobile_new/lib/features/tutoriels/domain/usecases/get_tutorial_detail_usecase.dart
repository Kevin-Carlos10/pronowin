import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/tutorial_entity.dart';
import '../repositories/tutorial_repository.dart';

class GetTutorialDetailUseCase {
  final TutorialRepository _repo;
  GetTutorialDetailUseCase(this._repo);
  Future<Either<Failure, TutorialEntity>> call(String id) => _repo.getTutorialDetail(id);
}
