import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../entities/transaction_entity.dart';
import '../repositories/payment_repository.dart';

class GetWalletUseCase {
  final PaymentRepository _repo;
  GetWalletUseCase(this._repo);
  Future<Either<Failure, WalletEntity>> call() => _repo.getWalletBalance();
}
