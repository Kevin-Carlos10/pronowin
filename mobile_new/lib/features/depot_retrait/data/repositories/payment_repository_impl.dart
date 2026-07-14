import 'package:dartz/dartz.dart';
import '../../../../core/network/failures.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/payment_remote_datasource.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentRemoteDataSource _remote;
  PaymentRepositoryImpl(this._remote);

  @override
  Future<Either<Failure, PaymentInitEntity>> initPayment({
    required TransactionType type, required double amount,
    required PaymentMethod method, required String provider, String? phoneNumber,
  }) async {
    try {
      final r = await _remote.initPayment(
        type: type, amount: amount, method: method,
        provider: provider, phoneNumber: phoneNumber,
      );
      return Right(r);
    } on Failure catch (f) { return Left(f); }
    catch (e) { return Left(UnknownFailure()); }
  }

  @override
  Future<Either<Failure, TransactionEntity>> checkPaymentStatus(String txId) async {
    try { return Right(await _remote.checkStatus(txId)); }
    on Failure catch (f) { return Left(f); }
    catch (e) { return Left(UnknownFailure()); }
  }

  @override
  Future<Either<Failure, List<TransactionEntity>>> getTransactions({int page = 1}) async {
    try { return Right(await _remote.getTransactions(page: page)); }
    on Failure catch (f) { return Left(f); }
    catch (e) { return Left(UnknownFailure()); }
  }

  @override
  Future<Either<Failure, WalletEntity>> getWalletBalance() async {
    try { return Right(await _remote.getWallet()); }
    on Failure catch (f) { return Left(f); }
    catch (e) { return Left(UnknownFailure()); }
  }
}
