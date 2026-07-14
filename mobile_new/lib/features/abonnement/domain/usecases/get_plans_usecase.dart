import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/plan_entity.dart';
import '../repositories/subscription_repository.dart';

class GetPlansUseCase {
  final SubscriptionRepository _repo;
  GetPlansUseCase(this._repo);
  Future<Either<Failure, List<PlanEntity>>> call() => _repo.getPlans();
}
