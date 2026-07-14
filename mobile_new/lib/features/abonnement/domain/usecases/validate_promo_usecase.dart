import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/plan_entity.dart';
import '../repositories/subscription_repository.dart';

class ValidatePromoUseCase {
  final SubscriptionRepository _repo;
  ValidatePromoUseCase(this._repo);

  Future<Either<Failure, PromoCodeEntity>> call(String code) {
    if (code.trim().isEmpty) return Future.value(const Left(ValidationFailure('Code promo vide.')));
    return _repo.validatePromoCode(code.trim().toUpperCase());
  }
}
