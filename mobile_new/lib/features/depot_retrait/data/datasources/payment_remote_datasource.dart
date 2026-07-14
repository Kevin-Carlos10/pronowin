import 'package:dio/dio.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/failures.dart';
import '../../../../core/network/dio_exception_handler.dart';
import '../../domain/entities/transaction_entity.dart';
import '../models/transaction_model.dart';

abstract class PaymentRemoteDataSource {
  Future<PaymentInitModel>       initPayment({required TransactionType type, required double amount, required PaymentMethod method, required String provider, String? phoneNumber});
  Future<TransactionModel>       checkStatus(String transactionId);
  Future<List<TransactionModel>> getTransactions({int page});
  Future<WalletModel>            getWallet();
}

class PaymentRemoteDataSourceImpl implements PaymentRemoteDataSource {
  final Dio _dio;
  PaymentRemoteDataSourceImpl(this._dio);

  @override
  Future<PaymentInitModel> initPayment({
    required TransactionType type,
    required double amount,
    required PaymentMethod method,
    required String provider,
    String? phoneNumber,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.initPayment,
        data: {
          'type':           type == TransactionType.deposit ? 'deposit' : 'withdrawal',
          'amount':         amount,
          'payment_method': _methodStr(method),
          'provider':       provider,
          if (phoneNumber != null) 'phone_number': phoneNumber,
        },
      );
      return PaymentInitModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<TransactionModel> checkStatus(String txId) async {
    try {
      final r = await _dio.get('${ApiEndpoints.paymentStatus}/$txId');
      return TransactionModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<List<TransactionModel>> getTransactions({int page = 1}) async {
    try {
      final r = await _dio.get(ApiEndpoints.transactions, queryParameters: {'page': page});
      final list = r.data['data'] as List<dynamic>;
      return list.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) { throw _handle(e); }
  }

  @override
  Future<WalletModel> getWallet() async {
    try {
      final r = await _dio.get('/wallet');
      return WalletModel.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) { throw _handle(e); }
  }

  String _methodStr(PaymentMethod m) => switch (m) {
    PaymentMethod.mobileMoney   => 'mobile_money',
    PaymentMethod.card          => 'card',
    PaymentMethod.crypto        => 'crypto',
    PaymentMethod.bankTransfer  => 'bank_transfer',
  };

  Failure _handle(DioException e, [String? ctx]) =>
      handleDioException(e, context: ctx);
}
