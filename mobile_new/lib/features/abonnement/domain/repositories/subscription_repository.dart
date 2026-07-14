import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/plan_entity.dart';

abstract class SubscriptionRepository {
  Future<Either<Failure, List<PlanEntity>>>    getPlans();
  Future<Either<Failure, SubscriptionEntity>>  getCurrentSubscription();
  Future<Either<Failure, SubscriptionEntity>>  subscribe({required String planId, required String paymentMethod, String? promoCode});
  Future<Either<Failure, PromoCodeEntity>>     validatePromoCode(String code);
  Future<Either<Failure, void>>                cancelSubscription();
}
