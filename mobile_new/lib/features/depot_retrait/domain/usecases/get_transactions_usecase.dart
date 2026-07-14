import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/transaction_entity.dart';
import '../repositories/payment_repository.dart';

class GetTransactionsUseCase {
  final PaymentRepository _repo;
  GetTransactionsUseCase(this._repo);
  Future<Either<Failure, List<TransactionEntity>>> call({int page = 1}) =>
      _repo.getTransactions(page: page);
}
