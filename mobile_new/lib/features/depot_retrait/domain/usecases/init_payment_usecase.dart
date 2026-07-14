import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/transaction_entity.dart';
import '../repositories/payment_repository.dart';

class InitPaymentParams {
  final TransactionType type;
  final double amount;
  final PaymentMethod method;
  final String provider;
  final String? phoneNumber;

  const InitPaymentParams({
    required this.type,
    required this.amount,
    required this.method,
    required this.provider,
    this.phoneNumber,
  });
}

class InitPaymentUseCase {
  final PaymentRepository _repo;
  InitPaymentUseCase(this._repo);

  Future<Either<Failure, PaymentInitEntity>> call(InitPaymentParams p) {
    if (p.amount < 500)  return Future.value(const Left(ValidationFailure('Montant minimum : 500 FCFA.')));
    if (p.amount > 2000000) return Future.value(const Left(ValidationFailure('Montant maximum : 2 000 000 FCFA.')));
    if (p.method == PaymentMethod.mobileMoney && (p.phoneNumber == null || p.phoneNumber!.isEmpty)) {
      return Future.value(const Left(ValidationFailure('Numéro Mobile Money requis.')));
    }
    return _repo.initPayment(
      type: p.type, amount: p.amount,
      method: p.method, provider: p.provider,
      phoneNumber: p.phoneNumber,
    );
  }
}
