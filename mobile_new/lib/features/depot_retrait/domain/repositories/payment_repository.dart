import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/transaction_entity.dart';

abstract class PaymentRepository {
  Future<Either<Failure, PaymentInitEntity>> initPayment({
    required TransactionType type,
    required double amount,
    required PaymentMethod method,
    required String provider,
    String? phoneNumber,
  });

  Future<Either<Failure, TransactionEntity>> checkPaymentStatus(String transactionId);

  Future<Either<Failure, List<TransactionEntity>>> getTransactions({int page = 1});

  Future<Either<Failure, WalletEntity>> getWalletBalance();
}
