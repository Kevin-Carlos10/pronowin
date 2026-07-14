import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/tutorial_entity.dart';

abstract class TutorialRepository {
  Future<Either<Failure, List<TutorialEntity>>> getTutorials({
    TutorialLevel?    level,
    TutorialCategory? category,
    bool?             premiumOnly,
  });
  Future<Either<Failure, TutorialEntity>>      getTutorialDetail(String id);
  Future<Either<Failure, void>>                markProgress(String id, int watchedSeconds, bool completed);
  Future<Either<Failure, List<TutorialProgressEntity>>> getProgress();
}
