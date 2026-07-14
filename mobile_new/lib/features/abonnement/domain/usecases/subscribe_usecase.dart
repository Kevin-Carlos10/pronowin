import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/plan_entity.dart';
import '../repositories/subscription_repository.dart';

class SubscribeParams {
  final String planId, paymentMethod;
  final String? promoCode;
  const SubscribeParams({required this.planId, required this.paymentMethod, this.promoCode});
}

class SubscribeUseCase {
  final SubscriptionRepository _repo;
  SubscribeUseCase(this._repo);

  Future<Either<Failure, SubscriptionEntity>> call(SubscribeParams p) =>
      _repo.subscribe(planId: p.planId, paymentMethod: p.paymentMethod, promoCode: p.promoCode);
}
