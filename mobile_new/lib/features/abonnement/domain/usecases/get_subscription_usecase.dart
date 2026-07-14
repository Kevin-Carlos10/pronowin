import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/plan_entity.dart';
import '../repositories/subscription_repository.dart';
class GetSubscriptionUseCase {
  final SubscriptionRepository _r;
  GetSubscriptionUseCase(this._r);
  Future<Either<Failure, SubscriptionEntity?>> call() => _r.getCurrentSubscription();
}
