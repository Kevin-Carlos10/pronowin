import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../repositories/referral_repository.dart';

class WithdrawEarningsUseCase {
  final ReferralRepository _repo;
  WithdrawEarningsUseCase(this._repo);

  Future<Either<Failure, void>> call(double amount, String phone) {
    if (amount < 2000) return Future.value(const Left(ValidationFailure('Minimum de retrait : 2 000 FCFA.')));
    if (phone.isEmpty) return Future.value(const Left(ValidationFailure('Numéro requis.')));
    return _repo.withdrawEarnings(amount, phone);
  }
}
