import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../../domain/entities/plan_entity.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../datasources/subscription_remote_datasource.dart';

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  final SubscriptionRemoteDataSource _remote;
  SubscriptionRepositoryImpl(this._remote);

  @override Future<Either<Failure, List<PlanEntity>>> getPlans() async {
    try { return Right(await _remote.getPlans()); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, SubscriptionEntity>> getCurrentSubscription() async {
    try { return Right(await _remote.getCurrentSubscription()); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, SubscriptionEntity>> subscribe({required String planId, required String paymentMethod, String? promoCode}) async {
    try { return Right(await _remote.subscribe(planId: planId, paymentMethod: paymentMethod, promoCode: promoCode)); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, PromoCodeEntity>> validatePromoCode(String code) async {
    try { return Right(await _remote.validatePromoCode(code)); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
  @override Future<Either<Failure, void>> cancelSubscription() async {
    try { await _remote.cancelSubscription(); return const Right(null); } on Failure catch (f) { return Left(f); } catch (_) { return Left(UnknownFailure()); }
  }
}
