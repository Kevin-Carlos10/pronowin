import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/transaction_entity.dart';
import '../repositories/payment_repository.dart';

class CheckPaymentUseCase {
  final PaymentRepository _repo;
  CheckPaymentUseCase(this._repo);
  Future<Either<Failure, TransactionEntity>> call(String transactionId) =>
      _repo.checkPaymentStatus(transactionId);
}
